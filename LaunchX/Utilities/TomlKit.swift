import Foundation

/// 轻量 TOML 解析/编辑器
/// 仅支持 LaunchX 需要操作的子集：顶层键值对、[section]、[nested.section]
/// 保留非管理段的内容和注释
final class TomlDocument {
    /// 原始行数据，用于语法保留编辑
    private var lines: [TomlLine]

    init() {
        lines = []
    }

    init(content: String) {
        lines = TomlParser.parse(content)
    }

    // MARK: - 读取

    /// 获取顶层字符串值
    func getString(_ key: String) -> String? {
        for line in lines {
            if case .keyValue(let k, let v) = line.kind, k == key {
                return v.unquotedValue
            }
        }
        return nil
    }

    /// 获取指定 section 下的字符串值
    func getString(_ key: String, in section: String) -> String? {
        var inSection = false
        for line in lines {
            if case .section(let name) = line.kind, name == section {
                inSection = true
                continue
            }
            if case .section = line.kind { inSection = false; continue }
            if inSection, case .keyValue(let k, let v) = line.kind, k == key {
                return v.unquotedValue
            }
        }
        return nil
    }

    /// 获取指定 section 下的所有键值对
    func getAllKeyValues(in section: String) -> [String: String] {
        var result: [String: String] = [:]
        var inSection = false
        for line in lines {
            if case .section(let name) = line.kind {
                inSection = (name == section)
                continue
            }
            if inSection, case .keyValue(let k, let v) = line.kind {
                result[k] = v.unquotedValue
            }
        }
        return result
    }

    /// 获取匹配前缀的所有 section 名
    func sectionsWithPrefix(_ prefix: String) -> [String] {
        lines.compactMap { line in
            if case .section(let name) = line.kind, name.hasPrefix(prefix) {
                return name
            }
            return nil
        }
    }

    // MARK: - 写入

    /// 设置顶层字符串值
    func set(_ key: String, value: String) {
        let quoted = value.tomlQuoted
        for i in lines.indices {
            if case .keyValue(let k, _) = lines[i].kind, k == key {
                lines[i] = TomlLine(kind: .keyValue(key, quoted), raw: "\(key) = \(quoted)")
                return
            }
        }
        // 新增：找到第一个 section 前面插入
        let insertIndex = lines.firstIndex(where: { if case .section = $0.kind { return true } else { return false } }) ?? lines.endIndex
        let newLine = TomlLine(kind: .keyValue(key, quoted), raw: "\(key) = \(quoted)")
        lines.insert(newLine, at: insertIndex)
    }

    /// 设置指定 section 下的字符串值
    func set(_ key: String, value: String, in section: String) {
        let quoted = value.tomlQuoted
        var sectionIndex: Int?
        var nextSectionIndex: Int?

        for i in lines.indices {
            if case .section(let name) = lines[i].kind {
                if name == section { sectionIndex = i }
                else if sectionIndex != nil && nextSectionIndex == nil { nextSectionIndex = i }
            }
        }

        guard let si = sectionIndex else {
            // section 不存在，追加
            let sectionLine = TomlLine(kind: .section(section), raw: "[\(section)]")
            let kvLine = TomlLine(kind: .keyValue(key, quoted), raw: "\(key) = \(quoted)")
            let blankLine = TomlLine(kind: .blank, raw: "")
            lines.append(blankLine)
            lines.append(sectionLine)
            lines.append(kvLine)
            return
        }

        let endIndex = nextSectionIndex ?? lines.endIndex

        for i in (si + 1)..<endIndex {
            if case .keyValue(let k, _) = lines[i].kind, k == key {
                lines[i] = TomlLine(kind: .keyValue(key, quoted), raw: "\(key) = \(quoted)")
                return
            }
        }

        // key 不存在于 section 中，在 section 末尾插入
        let kvLine = TomlLine(kind: .keyValue(key, quoted), raw: "\(key) = \(quoted)")
        lines.insert(kvLine, at: endIndex)
    }

    /// 删除指定 section
    func removeSection(_ section: String) {
        var sectionRange: Range<Int>?
        var start: Int?

        for i in lines.indices {
            if case .section(let name) = lines[i].kind {
                if name == section { start = i }
                else if start != nil {
                    sectionRange = start!..<(i)
                    break
                }
            }
        }
        if let s = start, sectionRange == nil {
            sectionRange = s..<lines.endIndex
        }

        if let range = sectionRange {
            lines.removeSubrange(range)
        }
    }

    /// 删除指定 section 下的某个 key
    func removeKey(_ key: String, in section: String) {
        var inSection = false
        var removeIndices: [Int] = []

        for i in lines.indices {
            if case .section(let name) = lines[i].kind {
                inSection = (name == section)
                continue
            }
            if inSection, case .keyValue(let k, _) = lines[i].kind, k == key {
                removeIndices.append(i)
            }
        }

        for i in removeIndices.reversed() {
            lines.remove(at: i)
        }
    }

    /// 设置指定 section 下的键值对（批量），移除不在 newKeys 中的键
    func setKeyValues(_ newKeyValues: [String: String], in section: String) {
        // 先删除 section 中现有的键
        var inSection = false
        var existingKeys: [String] = []

        for line in lines {
            if case .section(let name) = line.kind {
                inSection = (name == section)
                continue
            }
            if inSection, case .keyValue(let k, _) = line.kind {
                existingKeys.append(k)
            }
        }

        for key in existingKeys where newKeyValues[key] == nil {
            removeKey(key, in: section)
        }

        for (key, value) in newKeyValues {
            set(key, value: value, in: section)
        }
    }

    /// 设置指定 section 下的原始 TOML 值（不自动加引号，用于数组、内联表等）
    func setRaw(_ key: String, value: String, in section: String? = nil) {
        if let section = section {
            var sectionIndex: Int?
            var nextSectionIndex: Int?

            for i in lines.indices {
                if case .section(let name) = lines[i].kind {
                    if name == section { sectionIndex = i }
                    else if sectionIndex != nil && nextSectionIndex == nil { nextSectionIndex = i }
                }
            }

            guard let si = sectionIndex else {
                let sectionLine = TomlLine(kind: .section(section), raw: "[\(section)]")
                let kvLine = TomlLine(kind: .keyValue(key, value), raw: "\(key) = \(value)")
                let blankLine = TomlLine(kind: .blank, raw: "")
                lines.append(blankLine)
                lines.append(sectionLine)
                lines.append(kvLine)
                return
            }

            let endIndex = nextSectionIndex ?? lines.endIndex

            for i in (si + 1)..<endIndex {
                if case .keyValue(let k, _) = lines[i].kind, k == key {
                    lines[i] = TomlLine(kind: .keyValue(key, value), raw: "\(key) = \(value)")
                    return
                }
            }

            let kvLine = TomlLine(kind: .keyValue(key, value), raw: "\(key) = \(value)")
            lines.insert(kvLine, at: endIndex)
        } else {
            // 顶层
            for i in lines.indices {
                if case .keyValue(let k, _) = lines[i].kind, k == key {
                    lines[i] = TomlLine(kind: .keyValue(key, value), raw: "\(key) = \(value)")
                    return
                }
            }
            let insertIndex = lines.firstIndex(where: { if case .section = $0.kind { return true } else { return false } }) ?? lines.endIndex
            let newLine = TomlLine(kind: .keyValue(key, value), raw: "\(key) = \(value)")
            lines.insert(newLine, at: insertIndex)
        }
    }

    /// 获取顶层原始值（不含引号处理）
    func getRaw(_ key: String) -> String? {
        for line in lines {
            if case .keyValue(let k, let v) = line.kind, k == key {
                return v
            }
        }
        return nil
    }

    /// 获取指定 section 下的原始值
    func getRaw(_ key: String, in section: String) -> String? {
        var inSection = false
        for line in lines {
            if case .section(let name) = line.kind, name == section {
                inSection = true
                continue
            }
            if case .section = line.kind { inSection = false; continue }
            if inSection, case .keyValue(let k, let v) = line.kind, k == key {
                return v
            }
        }
        return nil
    }

    /// 检查指定 section 是否存在
    func hasSection(_ section: String) -> Bool {
        lines.contains { if case .section(let name) = $0.kind, name == section { return true } else { return false } }
    }

    // MARK: - 输出

    /// 序列化为 TOML 字符串
    func serialize() -> String {
        lines.map { $0.raw }.joined(separator: "\n")
    }
}

// MARK: - 内部类型

private struct TomlLine {
    enum Kind {
        case blank
        case comment(String)
        case section(String)
        case keyValue(String, String)  // key, rawValue
    }

    let kind: Kind
    var raw: String
}

private enum TomlParser {
    static func parse(_ content: String) -> [TomlLine] {
        content.components(separatedBy: "\n").map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                return TomlLine(kind: .blank, raw: line)
            }

            if trimmed.hasPrefix("#") {
                return TomlLine(kind: .comment(trimmed), raw: line)
            }

            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                let name = String(trimmed.dropFirst().dropLast())
                return TomlLine(kind: .section(name), raw: line)
            }

            if let eqRange = trimmed.range(of: "=", options: .literal) {
                let key = trimmed[..<eqRange.lowerBound].trimmingCharacters(in: .whitespaces)
                let value = trimmed[eqRange.upperBound...].trimmingCharacters(in: .whitespaces)
                return TomlLine(kind: .keyValue(key, value), raw: line)
            }

            return TomlLine(kind: .blank, raw: line)
        }
    }
}

// MARK: - String Helpers

extension String {
    var tomlQuoted: String {
        "\"\(replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    /// 去除 TOML 引号获取实际值
    var unquotedValue: String {
        let trimmed = trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") {
            return String(trimmed.dropFirst().dropLast())
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
        }
        return trimmed
    }
}
