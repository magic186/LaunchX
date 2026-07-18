# LaunchX 搜索性能与质量优化

> 2026-07 完成的搜索优化工作记录。三阶段：**P0 去冗余 → P1 异步化 → P2 模糊匹配**。
> 本文用于日后复看：为什么改、改了什么、关键决策与权衡、可调项。

---

## 一、背景

用户反馈「搜索性能差强人意」。经调研，匹配算法本身已较快（Trie 前缀 + 分层检索），**真正的瓶颈在每次按键做了大量与匹配无关的重复工作**，以及搜索在主线程同步执行。

分三阶段推进，每阶段独立可回退：

| 阶段 | 目标 | 风险 |
|---|---|---|
| **P0** | 砍掉每次按键的冗余开销 | 低 |
| **P1** | 搜索移出主线程 + 防抖 | 中（线程安全 / 竞态） |
| **P2** | apps/tools 引入子序列模糊匹配 | 低（小数据集） |

---

## 二、搜索架构现状（优化前）

### 搜索链路

```
controlTextDidChange (主线程)
  → performSearch                          SearchPanelViewController+Search.swift
    → searchEngine.searchSync              SearchEngine.swift
      → searchCache (LRU 50)               命中则 O(1) 返回
      → memoryIndex.search → queue.sync    MemoryIndex.swift  (串行队列)
        → 5 层分层检索:
            1. Alias     别名 Trie + 精确
            2. Trie      名称/拼音前缀
            3. Apps+Tools 全量线性扫描
            4. Dirs      最近 50 条线性扫描
            5. Files     最近 200 条线性扫描
      → searchBookmarks (全量线性 filter)
    → checkXxxAliasMatch × 4
    → sortSearchResults + 增量刷新 TableView
```

### 匹配算法（优化前）

`SearchItem.matchesQuery` 返回分层 `MatchType`：`exact > prefix > contains`，外加 `matchesPinyin`（拼音全称/缩写 + 英文词缩写）。**不是真正的模糊匹配**（无容错、无子序列、无打分）。

### 数据源

- 持久化：自定义 SQLite（C API），表 `files` 带多列索引。**搜索时不查 SQLite**，仅启动/重建/增量更新时读。
- 运行时索引：`MemoryIndex` 把全部记录放在内存（`apps`/`files`/`directories`/`tools`/`allItems` 字典 + 3 个 Trie）。设计支持 **60 万文件**。
- Trie 仅服务**前缀**匹配；`contains` 无法走 Trie，只能在截断窗口内线性扫描。

### 关键文件

| 文件 | 职责 |
|---|---|
| `Views/Search/SearchPanelViewController+Search.swift` | `performSearch`、别名入口检查、结果组装 |
| `Views/Search/SearchPanelViewController+Delegates.swift` | `controlTextDidChange` 输入入口 |
| `Views/SearchPanelViewController.swift` | VC 主类、存储属性 |
| `Services/Features/Search/SearchEngine/SearchEngine.swift` | `searchSync`、settings 缓存、observer |
| `Services/Features/Search/SearchEngine/MemoryIndex.swift` | `SearchItem`、`MatchType`、5 层检索、Trie |
| `Services/Features/Search/SearchEngine/SearchCache.swift` | 结果 LRU 缓存（已有 NSLock） |
| `Services/Features/Bookmark/BookmarkService.swift` | 书签加载与搜索 |
| `Services/FuzzyMatcher.swift` | P2 新增：子序列模糊匹配 |

---

## 三、性能瓶颈诊断（P0 前）

| # | 瓶颈 | 位置 | 严重度 |
|---|---|---|---|
| 1 | 每次按键 4 次 `JSONDecoder().decode`：4 个 `checkXxxAliasMatch` 各调 `XxxSettings.load()`（读 UserDefaults + 完整 JSON 反序列化） | `+Search.swift` 的 4 个 check 方法 | 🔴 高 |
| 2 | 书签全量线性扫描 + 循环内 `lowercased()`：每个书签每次按键 2 次字符串分配 | `BookmarkService.search` | 🔴 高 |
| 3 | 搜索在主线程同步执行（`queue.sync` 阻塞主线程），无防抖，慢查询只记日志不丢弃 | `MemoryIndex.search` / `+Delegates.swift` | 🟠 中高 |
| 4 | `BookmarkService.cachedBookmarks` 完全无锁（仅因主线程访问才安全） | `BookmarkService` | P1 暴露 |
| 5 | `contains` 无法走 Trie，只能在 `files.prefix(200)`/`dirs.prefix(50)` 内暴力扫——老文件/深目录搜不到 | `MemoryIndex.searchFiles/searchDirectories` | 🟠 中（搜索质量） |
| 6 | `excludedPaths` 是数组，`contains(where: hasPrefix)` 每候选 O(n) | `MemoryIndex` | 🟢 低（默认空配置零影响） |

> 注释里写的「sub-5ms for 600k files」只覆盖 `memoryIndex.search` 内部，不含上面 1/2 项的主线程开销。

---

## 四、P0：去冗余（已落地）

### 1. 缓存 4 个功能 Settings

`SearchEngine` 已有现成模式：`cachedBookmarkSettings` + `setupSettingsObserver()`（监听 `UserDefaults.didChangeNotification` 自动刷新）。**复用该模式**补齐另外 3 个。

- `SearchEngine` 新增 `cachedTwoFactorAuthSettings`/`cachedClaudeCodeSettings`/`cachedCodexSettings`（`cachedBookmarkSettings` 改 `private(set)`），在 observer 闭包里统一刷新。
- VC 的 4 个 `checkXxxAliasMatch` 由 `XxxSettings.load()` 改读 `searchEngine.cachedXxx`。

**收益**：每次按键省 4 次 JSON 解码 + UserDefaults 读。

### 2. 书签预计算小写

- `BookmarkItem` 新增 `lowerTitle`/`lowerUrl`，在 `init` 预计算一次（值类型，随 `cachedBookmarks` 长期复用）。
- `BookmarkService.search` 改用预计算值。

**收益**：每次按键省「书签数 × 2」次字符串分配。

### 3. 清理死代码

删除零引用文件（工程用 Xcode 16 `fileSystemSynchronizedGroups`，删文件即自动移出工程，无需改 `project.pbxproj`）：
- `Services/StringFuzzyMatcher.swift`（**但保留了被广泛使用的 `String.pinyin`/`pinyinAcronym` 扩展**，拆到新建的 `Services/String+Pinyin.swift`）
- `ViewModels/SearchViewModel.swift`、`Views/SearchTextField.swift`（历史 SwiftUI 路径，未被实例化）

### 明确不做

- **`excludedPaths` 优化移出 P0**：`SearchConfig.defaultExcludedPaths = []`，空数组 `contains(where:)` 已是 O(1)，默认配置零收益。

---

## 五、P1：异步化（已落地）

把搜索移出主线程 + 防抖，彻底解决主线程卡顿。

### 并发安全边界（探查结论）

后台线程只碰 `searchSync`，其内部依赖均已确认线程安全：

| 共享状态 | 线程安全？ | 说明 |
|---|---|---|
| `MemoryIndex` | ✅ | `queue.sync` 保护 |
| `SearchCache` | ✅ | 已有 `NSLock` |
| `SearchPerformanceMonitor` | ✅ | 无状态（只计时 + print） |
| `BookmarkService.cachedBookmarks` | ❌→✅ | **P1 加 `NSLock` 修复** |

`checkAlias`/`sortSearchResults`/`getDefaultSearchWebLinks`/UI 全部回主线程，后台「危险面」缩到最小。

### 改动

- **BookmarkService 加 `NSLock`**：`getAllBookmarks` 快速路径返回快照拷贝、慢路径 IO 在锁外；`clearCache` 也在锁内。
- **`performSearch` 重构**：
  - 防抖 ~20ms（`searchDebounceInterval`，复用项目 `DispatchWorkItem.cancel()`+`asyncAfter` 模式）；
  - 后台 `userInteractive` 队列跑 `searchSync`；
  - `searchGeneration` 代际计数——每次新搜索 bump，后台结果回来若 generation 过期则丢弃，杜绝旧结果覆盖新输入；
  - 空查询走同步 `applyEmptyQueryResults` 立即响应 + bump generation 让在途后台搜索失效。
- 新增 `executeSearchAsync`/`finalizeSearch`/`applyEmptyQueryResults`。

### 行为变化（需知晓）

1. 单次输入后结果延迟约 20ms 出现（人眼不可见）；
2. 快速连击只搜最后一次（中间状态不逐个搜）；
3. 结果不会「串」（generation 保护）。

### 调用方安全确认

已确认所有 `performSearch` 调用方均不依赖带查询路径的同步 `results`：`controlTextDidChange` 之后只调 `updateCalculatorPreview`；`+Keyboard` 的 3 处 `performSearch(result)` 调完即 `return nil`；空查询调用方走同步路径。

---

## 六、P2：模糊匹配（已落地）

apps/tools 引入 **fzf 风格子序列匹配 + 打分**，让缩写/输错字母也能命中。**自己实现，未引依赖**。

### 为什么自己实现（不引依赖）

- **fzf 本身是 Go CLI**，不是 Swift 库，只能 shell out（笨重，不适合 GUI）。
- Swift 现成库不合适：`Fuse-Swift`（最知名）是 **Bitap** 算法且已不维护；`FuzzyMatchingSwift` 偏数据清洗场景；Ordo One 的高速匹配器针对 25 万~100 万条（杀鸡用牛刀）。
- LaunchX 刻意保持依赖最小化（唯一第三方依赖是 Sparkle），为一个 ~40 行算法加 SPM 依赖不划算。

### 改动

- 新增 `Services/FuzzyMatcher.swift`：`score(query:in:)` 返回打分（越高越优）或 nil（非子序列）。
- `SearchItem.MatchType` 加 `case fuzzy`：`exact(0) > prefix(1) > contains(2) > fuzzy(3) > pinyin(4)`。
- `SearchItem` 新增 `fuzzyMatchScore`：对 `lowerName`/`wordAcronym` 取最高分。
- **仅在 `searchHighValueItems`（apps/tools）启用** fuzzy 分支；files/dirs 行为不变（不碰 60 万文件）；query 非 ASCII 时 fuzzy 不触发。
- 最终排序识别 `.fuzzy`，让缩写/容错命中排在拼音之前。

### 打分维度（`FuzzyMatcher.score`）

| 维度 | 分值 | 说明 |
|---|---|---|
| 基础命中 | +16 | 每个匹配字符 |
| 连续奖励 | +consecutive×8 | 连续匹配递增 |
| 词边界奖励 | +10 | 单词首字母（空格/标点/-/_ 之后） |
| 靠前奖励 | +max(0, 8-firstOffset) | 首次命中越靠前越高 |

### 效果举例

| 输入 | 命中 | 原理 |
|---|---|---|
| `vsc` | Visual Studio Code | 词边界子序列 |
| `vcode` | Visual Studio Code | 非连续子序列 |
| `visaul` | Visual… | 输错字母也能中 |
| `am` | Activity Monitor | 缩写词边界 |

---

## 七、关键设计决策

1. **`excludedPaths` 不优化**：默认空数组，`contains(where:)` 已 O(1)，默认配置零收益。仅当用户大量配置排除路径才有意义。
2. **fuzzy 只对 apps/tools**：数据量小（几百条），线性子序列匹配 <0.5ms；60 万文件做线性子序列扫描 = 几千万次比较，不可接受（必须靠索引）。
3. **fuzzy 自己实现**：见上「为什么自己实现」。核心代码 ~40 行，与现有 `MatchType`/`typePriority` 排序无缝集成。
4. **P1 generation 而非 Operation 取消**：`DispatchWorkItem.cancel()` 对已开始执行的任务无效，generation 计数是更可靠的「过期丢弃」机制；读写都在主线程，无竞争。
5. **后台范围最小化**：只把 `searchSync` 丢后台（其内部已线程安全），其余回主线程——避免大面积处理线程安全。

---

## 八、可调项

| 项 | 位置 | 说明 |
|---|---|---|
| 防抖间隔 | `SearchPanelViewController.searchDebounceInterval` | 默认 0.02s。有延迟感→0.01；想更省→0.03 |
| fuzzy 基础分 | `FuzzyMatcher.score` 内 `16` | 调整整体分数量级 |
| 连续奖励系数 | `FuzzyMatcher.score` 内 `×8` | 调大→连续匹配更优先 |
| 词边界奖励 | `FuzzyMatcher.score` 内 `+10` | 调大→单词首字母命中更优先 |
| 靠前奖励 | `FuzzyMatcher.score` 内 `max(0, 8-firstOffset)` | 调整位置权重 |
| fuzzy 噪音控制 | （未实现） | 若短查询弱匹配噪音多，可加 score 最低阈值 |

---

## 九、后续可选方向（未做）

- **文件 `contains` 走 bigram 倒排索引**：当前 `files.prefix(200)` 截断导致老文件子串搜不到；建字符 bigram 倒排索引可让子串匹配覆盖全量文件且不退化到线性扫描。成本较高，建议先评估需求。
- **fuzzy 打分阈值**：实测若弱匹配噪音多再加。
- **`excludedPaths` 前缀结构化**：仅当用户大量配置排除路径时值得做。

---

## 十、踩坑记录

### 误删 `StringFuzzyMatcher.swift` 导致编译失败

判断「死代码」时只 grep 了顶层类型名 `StringFuzzyMatcher`/`CachedSearchableString`（确实零引用），**但漏看了文件内的 `extension String { pinyin / pinyinAcronym / ... }`**——这段扩展被 `MemoryIndex`/`FileIndexer`/`SearchEngine` 大量调用。

**教训**：判断文件是否死代码，除 grep 顶层类型名外，**必须检查文件内的 `extension` 成员**是否被引用。

**修复**：新建 `Services/String+Pinyin.swift`，只保留被使用的 `pinyin`/`pinyinAcronym`，丢弃未用的 `hasMultiByteCharacters`/`isAscii` 及两个死类型。

---

## 附：变更文件清单

### P0
- 修改：`SearchEngine.swift`、`SearchPanelViewController+Search.swift`、`BookmarkService.swift`
- 新增：`Services/String+Pinyin.swift`
- 删除：`Services/StringFuzzyMatcher.swift`、`ViewModels/SearchViewModel.swift`、`Views/SearchTextField.swift`

### P1
- 修改：`BookmarkService.swift`（加 NSLock）、`SearchPanelViewController+Search.swift`（performSearch 重构）、`SearchPanelViewController.swift`（加 searchDebounceWorkItem/searchGeneration 属性）

### P2
- 新增：`Services/FuzzyMatcher.swift`
- 修改：`MemoryIndex.swift`（MatchType 加 .fuzzy、fuzzyMatchScore 方法、searchHighValueItems 分支、最终排序）
