import XCTest
@testable import LaunchX

final class TomlKitTests: XCTestCase {

    // MARK: - 解析测试

    func testParseTopLevelKeyValue() {
        let doc = TomlDocument(content: "model = \"gpt-4\"\n")
        XCTAssertEqual(doc.getString("model"), "gpt-4")
    }

    func testParseSection() {
        let content = """
        model = "gpt-4"

        [model_providers.myapi]
        name = "MyAPI"
        base_url = "https://api.example.com/v1"
        """
        let doc = TomlDocument(content: content)
        XCTAssertEqual(doc.getString("base_url", in: "model_providers.myapi"), "https://api.example.com/v1")
        XCTAssertEqual(doc.getString("name", in: "model_providers.myapi"), "MyAPI")
    }

    func testParseNestedSection() {
        let content = """
        [mcp_servers.filesystem]
        command = "npx"
        args = "something"
        """
        let doc = TomlDocument(content: content)
        XCTAssertEqual(doc.getString("command", in: "mcp_servers.filesystem"), "npx")
    }

    func testParsePreservesComments() {
        let content = """
        # This is a comment
        model = "gpt-4"

        # Provider section
        [model_providers.test]
        base_url = "http://localhost"
        """
        let doc = TomlDocument(content: content)
        let output = doc.serialize()
        XCTAssertTrue(output.contains("# This is a comment"))
        XCTAssertTrue(output.contains("# Provider section"))
    }

    func testParseEmptyContent() {
        let doc = TomlDocument(content: "")
        XCTAssertEqual(doc.serialize(), "")
    }

    // MARK: - 写入测试

    func testSetTopLevelValue() {
        let content = "model = \"old\"\n"
        let doc = TomlDocument(content: content)
        doc.set("model", value: "new-model")
        XCTAssertTrue(doc.serialize().contains("model = \"new-model\""))
    }

    func testSetNewTopLevelValue() {
        let doc = TomlDocument(content: "")
        doc.set("model", value: "gpt-4")
        let output = doc.serialize()
        XCTAssertTrue(output.contains("model = \"gpt-4\""))
    }

    func testSetSectionValue() {
        let content = """
        [model_providers.test]
        base_url = "http://old.com"
        """
        let doc = TomlDocument(content: content)
        doc.set("base_url", value: "http://new.com/v1", in: "model_providers.test")
        let output = doc.serialize()
        XCTAssertTrue(output.contains("base_url = \"http://new.com/v1\""))
        XCTAssertFalse(output.contains("old.com"))
    }

    func testSetNewSection() {
        let doc = TomlDocument(content: "model = \"gpt-4\"\n")
        doc.set("base_url", value: "http://api.com", in: "model_providers.newapi")
        let output = doc.serialize()
        XCTAssertTrue(output.contains("[model_providers.newapi]"))
        XCTAssertTrue(output.contains("base_url = \"http://api.com\""))
    }

    // MARK: - 删除测试

    func testRemoveSection() {
        let content = """
        model = "gpt-4"

        [model_providers.old]
        name = "Old"
        """
        let doc = TomlDocument(content: content)
        doc.removeSection("model_providers.old")
        let output = doc.serialize()
        XCTAssertFalse(output.contains("[model_providers.old]"))
        XCTAssertFalse(output.contains("name = \"Old\""))
        XCTAssertTrue(output.contains("model = \"gpt-4\""))
    }

    func testRemoveKeyInSection() {
        let content = """
        [model_providers.test]
        name = "Test"
        base_url = "http://test.com"
        """
        let doc = TomlDocument(content: content)
        doc.removeKey("base_url", in: "model_providers.test")
        let output = doc.serialize()
        XCTAssertFalse(output.contains("base_url"))
        XCTAssertTrue(output.contains("name = \"Test\""))
    }

    // MARK: - 语法保留测试

    func testPreservesUnmanagedContent() {
        let content = """
        # User comment
        model = "gpt-4"
        custom_flag = true

        [user_section]
        foo = "bar"

        [model_providers.managed]
        base_url = "http://api.com"
        """
        let doc = TomlDocument(content: content)
        doc.set("base_url", value: "http://new-api.com", in: "model_providers.managed")
        let output = doc.serialize()
        XCTAssertTrue(output.contains("# User comment"))
        XCTAssertTrue(output.contains("custom_flag = true"))
        XCTAssertTrue(output.contains("[user_section]"))
        XCTAssertTrue(output.contains("foo = \"bar\""))
    }

    // MARK: - Section 查询测试

    func testSectionsWithPrefix() {
        let content = """
        [mcp_servers.server1]
        command = "a"
        [mcp_servers.server2]
        command = "b"
        [other_section]
        """
        let doc = TomlDocument(content: content)
        let sections = doc.sectionsWithPrefix("mcp_servers.")
        XCTAssertEqual(sections, ["mcp_servers.server1", "mcp_servers.server2"])
    }

    // MARK: - 特殊字符测试

    func testQuotedValueWithSpecialChars() {
        let content = """
        [mcp_servers.test]
        url = "https://api.example.com/path?key=val&foo=bar"
        """
        let doc = TomlDocument(content: content)
        XCTAssertEqual(doc.getString("url", in: "mcp_servers.test"), "https://api.example.com/path?key=val&foo=bar")
    }

    func testSetKeyValuesBatch() {
        let content = """
        [mcp_servers.test]
        old_key = "remove_me"
        keep = "yes"
        """
        let doc = TomlDocument(content: content)
        doc.setKeyValues(["keep": "yes", "new_key": "added"], in: "mcp_servers.test")
        let output = doc.serialize()
        XCTAssertTrue(output.contains("keep = \"yes\""))
        XCTAssertTrue(output.contains("new_key = \"added\""))
        XCTAssertFalse(output.contains("old_key"))
    }
}
