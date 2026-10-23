import XCTest
@testable import EAgent

final class ToolCallParserTests: XCTestCase {

    func testParsesSingleToolCall() {
        let text = """
        我先看看工作区。
        <iagent-tool>
        {"tool":"list_files","args":{"path":"notes"}}
        </iagent-tool>
        """
        let calls = ToolCallParser.parse(text)
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.name, "list_files")
        XCTAssertEqual(calls.first?.string("path"), "notes")
    }

    func testParsesMultipleToolCalls() {
        let text = """
        <iagent-tool>
        {"tool":"read_file","args":{"path":"a.txt"}}
        </iagent-tool>
        <iagent-tool>
        {"tool":"clipboard_write","args":{"text":"hello"}}
        </iagent-tool>
        """
        let calls = ToolCallParser.parse(text)
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls.map(\.name), ["read_file", "clipboard_write"])
        XCTAssertEqual(calls[1].string("text"), "hello")
    }

    func testStripsMarkdownCodeFence() {
        let text = """
        <iagent-tool>
        ```json
        {"tool":"device_info","args":{}}
        ```
        </iagent-tool>
        """
        let calls = ToolCallParser.parse(text)
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.name, "device_info")
    }

    func testAcceptsFlatArguments() {
        let text = """
        <iagent-tool>
        {"tool":"write_file","path":"x.txt","content":"data"}
        </iagent-tool>
        """
        let calls = ToolCallParser.parse(text)
        XCTAssertEqual(calls.first?.name, "write_file")
        XCTAssertEqual(calls.first?.string("path"), "x.txt")
        XCTAssertEqual(calls.first?.string("content"), "data")
    }

    func testAcceptsAlternateToolNameKeys() {
        let text = """
        <iagent-tool>
        {"name":"screenshot","arguments":{"note":"看看"}}
        </iagent-tool>
        """
        let calls = ToolCallParser.parse(text)
        XCTAssertEqual(calls.first?.name, "screenshot")
        XCTAssertEqual(calls.first?.string("note"), "看看")
    }

    func testIgnoresMalformedBlocks() {
        let text = """
        <iagent-tool>
        这不是 JSON
        </iagent-tool>
        <iagent-tool>
        {"args":{}}
        </iagent-tool>
        """
        XCTAssertTrue(ToolCallParser.parse(text).isEmpty)
    }

    func testNoToolCallInPlainText() {
        XCTAssertTrue(ToolCallParser.parse("今天天气不错。").isEmpty)
    }

    func testStringifyKeepsBooleansAndNumbers() {
        XCTAssertEqual(ToolCallParser.stringify(true), "true")
        XCTAssertEqual(ToolCallParser.stringify(false), "false")
        XCTAssertEqual(ToolCallParser.stringify(42), "42")
        XCTAssertEqual(ToolCallParser.stringify("文本"), "文本")
    }

    func testWrapsResultInResultTag() {
        let wrapped = ToolCallParser.wrapResult(tool: "list_files", ok: true, summary: "3 项", detail: nil)
        XCTAssertTrue(wrapped.contains(ToolCallParser.resultOpenTag))
        XCTAssertTrue(wrapped.contains(ToolCallParser.resultCloseTag))
        XCTAssertTrue(wrapped.contains("\"ok\":true"))
    }

    func testToolCallArgumentCoercion() {
        let call = ToolCall(name: "x", args: ["n": "12", "flag": "true", "no": "否"])
        XCTAssertEqual(call.int("n"), 12)
        XCTAssertEqual(call.bool("flag"), true)
        XCTAssertEqual(call.bool("no"), false)
        XCTAssertNil(call.bool("missing"))
    }
}
