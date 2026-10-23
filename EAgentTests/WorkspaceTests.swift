import XCTest
@testable import EAgent

final class WorkspaceTests: XCTestCase {

    private var root: URL!
    private var workspace: Workspace!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("iagent-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        workspace = Workspace(root: root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testResolveStaysInsideRoot() {
        XCTAssertNotNil(workspace.resolve("notes/a.txt"))
        XCTAssertNil(workspace.resolve("../outside.txt"))
        XCTAssertNil(workspace.resolve("notes/../../outside.txt"))
        XCTAssertNil(workspace.resolve("/etc/passwd"))
    }

    func testWriteReadRoundTrip() throws {
        try workspace.writeFile("notes/a.txt", content: "你好，世界")
        let text = try workspace.readFile("notes/a.txt")
        XCTAssertEqual(text, "你好，世界")
    }

    func testWriteCreatesIntermediateDirectories() throws {
        try workspace.writeFile("a/b/c/d.txt", content: "x")
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("a/b/c/d.txt").path))
    }

    func testReadMissingFileThrows() {
        XCTAssertThrowsError(try workspace.readFile("nope.txt"))
    }

    func testListFilesSortsDirectoriesFirst() throws {
        try workspace.writeFile("b.txt", content: "b")
        try workspace.writeFile("z.txt", content: "z")
        try workspace.writeFile("sub/inner.txt", content: "i")
        let entries = try workspace.listFiles("")
        XCTAssertEqual(entries.count, 3)
        XCTAssertTrue(entries[0].isDirectory)
        XCTAssertEqual(entries[0].name, "sub")
    }

    func testDeleteAndMove() throws {
        try workspace.writeFile("a.txt", content: "a")
        try workspace.writeFile("b.txt", content: "b")
        let newPath = try workspace.moveFile(from: "a.txt", to: "sub/a.txt")
        XCTAssertEqual(newPath, "sub/a.txt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("a.txt").path))
        try workspace.deleteFile("b.txt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("b.txt").path))
    }

    func testDeleteRootIsRejected() {
        XCTAssertThrowsError(try workspace.deleteFile(""))
        XCTAssertThrowsError(try workspace.deleteFile("."))
    }

    func testSearchFilesFindsContent() throws {
        try workspace.writeFile("notes/todo.md", content: "第一行\n第二行关键词\n第三行")
        let hits = try workspace.searchFiles(query: "关键词")
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.path, "notes/todo.md")
        XCTAssertEqual(hits.first?.line, 2)
    }

    func testSearchOutsideRootIsRejected() {
        XCTAssertThrowsError(try workspace.searchFiles(query: "x", in: "../"))
    }

    func testStatisticsCountsFiles() throws {
        try workspace.writeFile("a.txt", content: "12345")
        try workspace.writeFile("b.txt", content: "123")
        let stats = workspace.statistics()
        XCTAssertEqual(stats.files, 2)
        XCTAssertEqual(stats.bytes, 8)
    }
}
