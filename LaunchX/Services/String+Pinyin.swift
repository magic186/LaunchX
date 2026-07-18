import Foundation

// MARK: - Pinyin Extensions
// 中文转拼音扩展，供 MemoryIndex / FileIndexer / SearchEngine 构建索引时使用。

extension String {
    /// Converts "微信" to "Wei Xin"
    public var pinyin: String {
        let mutableString = NSMutableString(string: self)
        // Convert to Latin (Pinyin)
        CFStringTransform(mutableString, nil, kCFStringTransformToLatin, false)
        // Remove tone marks
        CFStringTransform(mutableString, nil, kCFStringTransformStripDiacritics, false)
        return String(mutableString)
    }

    /// Converts "微信" to "wx"
    public var pinyinAcronym: String {
        let pinyinStr = self.pinyin
        let components = pinyinStr.components(separatedBy: " ")
        var acronym = ""
        for comp in components {
            if let first = comp.first {
                acronym.append(first)
            }
        }
        return acronym
    }
}
