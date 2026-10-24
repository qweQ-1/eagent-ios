import XCTest
@testable import EAgent

final class ToolCatalogTests: XCTestCase {

    func testEveryToolHasUsageAndSummary() {
        for spec in ToolCatalog.specs {
            XCTAssertFalse(spec.name.isEmpty)
            XCTAssertFalse(spec.usage.isEmpty)
            XCTAssertFalse(spec.displaySummary.isEmpty)
            XCTAssertTrue(spec.usage.contains(spec.name), "工具 \(spec.name) 的用法示例里应当出现自己的名字")
        }
    }

    func testToolNamesAreUnique() {
        let names = ToolCatalog.specs.map(\.name)
        XCTAssertEqual(Set(names).count, names.count)
    }

    func testSpecLookup() {
        XCTAssertEqual(ToolCatalog.spec(named: "write_file")?.risk, .mutating)
        XCTAssertEqual(ToolCatalog.spec(named: "list_files")?.risk, .readonly)
        XCTAssertNil(ToolCatalog.spec(named: "nope"))
    }

    func testSystemPromptContainsProtocolAndTools() {
        let prompt = ToolCatalog.systemPrompt(workspacePath: "/tmp/work",
                                             extraPrompt: "",
                                             autoApproveReadOnly: true,
                                             maxSteps: 8)
        XCTAssertTrue(prompt.contains("/tmp/work"))
        XCTAssertTrue(prompt.contains(ToolCallParser.openTag))
        XCTAssertTrue(prompt.contains(ToolCallParser.resultOpenTag))
        XCTAssertTrue(prompt.contains("write_file"))
        XCTAssertTrue(prompt.contains("执行 shell"))
    }

    func testSystemPromptAppendsExtraRequirements() {
        let prompt = ToolCatalog.systemPrompt(workspacePath: "/tmp/work",
                                             extraPrompt: "回答一律用中文",
                                             autoApproveReadOnly: false,
                                             maxSteps: 3)
        XCTAssertTrue(prompt.contains("回答一律用中文"))
        XCTAssertTrue(prompt.contains("所有工具在执行前都要用户确认"))
        XCTAssertTrue(prompt.contains("连续调用 3 轮工具"))
    }
}
