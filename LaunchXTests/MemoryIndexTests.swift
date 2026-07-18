import Testing

@testable import LaunchX

struct MemoryIndexTests {
    @Test func identityBackedTrieReturnsAllSharedPrefixMatches() async {
        let index = MemoryIndex()
        await build(
            index,
            records: [
                directory(name: "Alpha", path: "/tmp/one/Alpha"),
                directory(name: "Alpha", path: "/tmp/two/Alpha"),
                directory(name: "Alpine", path: "/tmp/Alpine"),
                directory(name: "Beta", path: "/tmp/Beta"),
            ]
        )

        let paths = Set(index.search(query: "al").map(\.path))

        #expect(paths == ["/tmp/one/Alpha", "/tmp/two/Alpha", "/tmp/Alpine"])
    }

    @Test func removingOneItemKeepsSharedTrieNodesIntact() async {
        let index = MemoryIndex()
        await build(
            index,
            records: [
                directory(name: "Alpha", path: "/tmp/Alpha"),
                directory(name: "Alpine", path: "/tmp/Alpine"),
            ]
        )

        index.remove(path: "/tmp/Alpha")
        let paths = Set(index.search(query: "al").map(\.path))

        #expect(paths == ["/tmp/Alpine"])
    }

    @Test func pinyinTrieDeduplicatesTheSameItemByIdentity() async {
        let index = MemoryIndex()
        await build(
            index,
            records: [
                directory(
                    name: "Chinese Name",
                    path: "/tmp/ChineseName",
                    pinyinFull: "ceshi",
                    pinyinAcronym: "cs"
                )
            ]
        )

        let results = index.search(query: "c")

        #expect(results.map(\.path) == ["/tmp/ChineseName"])
    }

    private func build(_ index: MemoryIndex, records: [FileRecord]) async {
        await withCheckedContinuation { continuation in
            index.build(from: records) {
                continuation.resume()
            }
        }
    }

    private func directory(
        name: String,
        path: String,
        pinyinFull: String? = nil,
        pinyinAcronym: String? = nil
    ) -> FileRecord {
        FileRecord(
            name: name,
            path: path,
            isDirectory: true,
            pinyinFull: pinyinFull,
            pinyinAcronym: pinyinAcronym
        )
    }
}
