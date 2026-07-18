import Foundation

enum SearchIndexPathFilter {
    private static let packageExtensions: Set<String> = [
        "app",
        "bundle",
        "framework",
        "plugin",
        "kext",
        "prefpane",
        "osax",
        "qlgenerator",
        "mdimporter",
        "action",
        "menu",
        "pkg",
    ]

    static func shouldExclude(path: String, config: SearchConfig) -> Bool {
        if isUnderExcludedPath(path, excludedPaths: config.excludedPaths) {
            return true
        }

        let components = (path as NSString).pathComponents
        let excludedFolderNames = Set(config.excludedFolderNames)
        if components.contains(where: excludedFolderNames.contains) {
            return true
        }

        if isInsidePackage(components: components) {
            return true
        }

        let ext = (path as NSString).pathExtension.lowercased()
        return !ext.isEmpty && config.excludedExtensions.contains(ext)
    }

    private static func isUnderExcludedPath(_ path: String, excludedPaths: [String]) -> Bool {
        let normalizedPath = (path as NSString).standardizingPath

        return excludedPaths.contains { excludedPath in
            let normalizedExcludedPath = (excludedPath as NSString).standardizingPath
            guard !normalizedExcludedPath.isEmpty else { return false }
            if normalizedPath == normalizedExcludedPath {
                return true
            }

            let prefix =
                normalizedExcludedPath == "/"
                ? normalizedExcludedPath
                : normalizedExcludedPath + "/"
            return normalizedPath.hasPrefix(prefix)
        }
    }

    private static func isInsidePackage(components: [String]) -> Bool {
        guard components.count > 1 else { return false }

        for component in components.dropLast() {
            let ext = (component as NSString).pathExtension.lowercased()
            if packageExtensions.contains(ext) {
                return true
            }
        }

        return false
    }
}
