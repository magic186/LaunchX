import Testing

@testable import LaunchX

struct SearchIndexPathFilterTests {
    private let config = SearchConfig(
        excludedPaths: ["/Users/test/Private"],
        excludedExtensions: ["log"],
        excludedFolderNames: ["node_modules", ".git", "dist"]
    )

    @Test func excludesDescendantsOfConfiguredFolderNames() {
        #expect(
            SearchIndexPathFilter.shouldExclude(
                path: "/Users/test/project/node_modules/package/index.js",
                config: config
            ))
        #expect(
            SearchIndexPathFilter.shouldExclude(
                path: "/Users/test/project/.git/objects/ab/cd",
                config: config
            ))
        #expect(
            SearchIndexPathFilter.shouldExclude(
                path: "/Users/test/project/dist/assets/app.js",
                config: config
            ))
    }

    @Test func doesNotExcludeSimilarFolderNames() {
        #expect(
            !SearchIndexPathFilter.shouldExclude(
                path: "/Users/test/project/node_modules_backup/index.js",
                config: config
            ))
    }

    @Test func excludesPackageDescendantsButKeepsPackageItself() {
        #expect(
            SearchIndexPathFilter.shouldExclude(
                path: "/Applications/Example.app/Contents/Info.plist",
                config: config
            ))
        #expect(
            !SearchIndexPathFilter.shouldExclude(
                path: "/Applications/Example.app",
                config: config
            ))
    }

    @Test func excludedPathUsesComponentBoundary() {
        #expect(
            SearchIndexPathFilter.shouldExclude(
                path: "/Users/test/Private/file.txt",
                config: config
            ))
        #expect(
            !SearchIndexPathFilter.shouldExclude(
                path: "/Users/test/PrivateBackup/file.txt",
                config: config
            ))
    }

    @Test func excludesConfiguredExtension() {
        #expect(
            SearchIndexPathFilter.shouldExclude(
                path: "/Users/test/project/debug.log",
                config: config
            ))
    }
}
