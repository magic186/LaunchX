import Foundation

/// fzf 风格子序列模糊匹配 + 打分。
///
/// 仅用于 apps/tools 等小数据集（几百条）的线性扫描；不要用于大规模文件集。
/// 返回打分（越高越优）；nil 表示 query 不是 target 的子序列。
enum FuzzyMatcher {

    /// 判断 query 是否为 target 的子序列并打分。
    /// - Note: 调用方应传入已小写的字符串以省去大小写处理。
    static func score(_ query: String, in target: String) -> Int? {
        guard !query.isEmpty else { return nil }

        var qi = query.startIndex
        var prevTargetIdx = target.startIndex
        var score = 0
        var consecutive = 0
        var prevHit = false
        var firstOffset = -1
        var offset = 0

        var ti = target.startIndex
        while qi < query.endIndex, ti < target.endIndex {
            if query[qi] == target[ti] {
                if firstOffset < 0 { firstOffset = offset }
                score += 16
                if prevHit {
                    consecutive += 1
                    score += consecutive * 8  // 连续匹配奖励
                } else {
                    consecutive = 0
                }
                if offset == 0 || isBoundary(target[prevTargetIdx]) {
                    score += 10  // 词边界奖励（单词首字母）
                }
                prevHit = true
                qi = query.index(after: qi)
            } else {
                prevHit = false
                consecutive = 0
            }
            prevTargetIdx = ti
            ti = target.index(after: ti)
            offset += 1
        }

        // 必须消耗完整个 query 才算子序列命中
        guard qi == query.endIndex else { return nil }
        score += max(0, 8 - firstOffset)  // 靠前奖励
        return score
    }

    /// 单词边界字符：空格 / 标点 / 连字符。命中这些之后的首字母视为词边界。
    private static func isBoundary(_ char: Character) -> Bool {
        char.isWhitespace || char.isPunctuation || char == "-" || char == "_"
    }
}
