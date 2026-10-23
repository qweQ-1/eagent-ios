import Foundation

/// 工作区：App 沙盒里的一个目录，所有文件工具都只在这里面活动。
///
/// 路径安全：所有相对路径都会被标准化（消掉 `..`），并要求最终路径仍位于根目录内，
/// 否则一律拒绝，防止模型读写到沙盒外的位置。
struct Workspace: Sendable {
    let root: URL

    static let defaultFolderName = "AgentWorkspace"

    static func defaultRoot(folderName: String = defaultFolderName) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let name = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        let safe = name.isEmpty ? defaultFolderName : name
        return docs.appendingPathComponent(safe, isDirectory: true)
    }

    init(root: URL) {
        self.root = root
    }

    init(folderName: String = Workspace.defaultFolderName) {
        self.init(root: Workspace.defaultRoot(folderName: folderName))
    }

    enum WorkspaceError: LocalizedError {
        case pathEscapesRoot(String)
        case notFound(String)
        case isDirectory(String)

        var errorDescription: String? {
            switch self {
            case .pathEscapesRoot(let path):
                return "路径「\(path)」超出了工作区范围，已拒绝。"
            case .notFound(let path):
                return "文件不存在：\(path)"
            case .isDirectory(let path):
                return "「\(path)」是一个目录，不能按文件读取。"
            }
        }
    }

    /// 把相对路径解析成绝对 URL，越界返回 nil
    func resolve(_ relativePath: String) -> URL? {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.isEmpty ? root : root.appendingPathComponent(trimmed)
        let standardized = candidate.standardizedFileURL
        let rootPath = root.standardizedFileURL.path
        let path = standardized.path
        if path == rootPath { return standardized }
        guard path.hasPrefix(rootPath + "/") else { return nil }
        return standardized
    }

    /// 相对路径（相对工作区根），用于展示
    func relativePath(of url: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if path == rootPath { return "." }
        if path.hasPrefix(rootPath + "/") {
            return String(path.dropFirst(rootPath.count + 1))
        }
        return path
    }

    func ensureRootExists() {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    // MARK: - 读

    func readFile(_ relativePath: String, maxBytes: Int = 200_000) throws -> String {
        guard let url = resolve(relativePath) else {
            throw WorkspaceError.pathEscapesRoot(relativePath)
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
            throw WorkspaceError.notFound(relativePath)
        }
        if isDir.boolValue { throw WorkspaceError.isDirectory(relativePath) }
        let data = try Data(contentsOf: url)
        let slice = data.count > maxBytes ? data.prefix(maxBytes) : data
        var text = String(decoding: slice, as: UTF8.self)
        if data.count > maxBytes {
            text += "\n\n（内容超过 \(maxBytes) 字节，已截断）"
        }
        return text
    }

    // MARK: - 写

    @discardableResult
    func writeFile(_ relativePath: String, content: String) throws -> Int {
        guard let url = resolve(relativePath) else {
            throw WorkspaceError.pathEscapesRoot(relativePath)
        }
        ensureRootExists()
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let data = Data(content.utf8)
        try data.write(to: url, options: .atomic)
        return data.count
    }

    // MARK: - 列目录

    struct Entry: Identifiable, Equatable {
        var id: String { path }
        var name: String
        var path: String
        var isDirectory: Bool
        var size: Int
        var modified: Date?
    }

    func listFiles(_ relativePath: String) throws -> [Entry] {
        guard let url = resolve(relativePath) else {
            throw WorkspaceError.pathEscapesRoot(relativePath)
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            throw WorkspaceError.notFound(relativePath.isEmpty ? "." : relativePath)
        }
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        let items = try FileManager.default.contentsOfDirectory(at: url,
                                                               includingPropertiesForKeys: keys,
                                                               options: [.skipsHiddenFiles])
        return items
            .map { item in
                let values = try? item.resourceValues(forKeys: Set(keys))
                return Entry(name: item.lastPathComponent,
                             path: relativePath(of: item),
                             isDirectory: values?.isDirectory ?? false,
                             size: values?.fileSize ?? 0,
                             modified: values?.contentModificationDate)
            }
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    // MARK: - 删 / 移

    func deleteFile(_ relativePath: String) throws {
        guard let url = resolve(relativePath) else {
            throw WorkspaceError.pathEscapesRoot(relativePath)
        }
        guard url.standardizedFileURL.path != root.standardizedFileURL.path else {
            throw WorkspaceError.pathEscapesRoot(relativePath)
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw WorkspaceError.notFound(relativePath)
        }
        try FileManager.default.removeItem(at: url)
    }

    func moveFile(from: String, to: String) throws -> String {
        guard let source = resolve(from) else { throw WorkspaceError.pathEscapesRoot(from) }
        guard let destination = resolve(to) else { throw WorkspaceError.pathEscapesRoot(to) }
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw WorkspaceError.notFound(from)
        }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: source, to: destination)
        return relativePath(of: destination)
    }

    // MARK: - 搜索

    struct Hit: Equatable {
        var path: String
        var line: Int
        var preview: String
    }

    func searchFiles(query: String, in relativePath: String = "") throws -> [Hit] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        guard let folder = resolve(relativePath) else {
            throw WorkspaceError.pathEscapesRoot(relativePath)
        }
        guard let enumerator = FileManager.default.enumerator(at: folder,
                                                             includingPropertiesForKeys: [.isRegularFileKey],
                                                             options: [.skipsHiddenFiles]) else {
            return []
        }
        var hits: [Hit] = []
        let lowerNeedle = needle.lowercased()
        for case let fileURL as URL in enumerator {
            if hits.count >= 200 { break }
            guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            for (index, line) in text.components(separatedBy: .newlines).enumerated() {
                if line.lowercased().contains(lowerNeedle) {
                    hits.append(Hit(path: relativePath(of: fileURL),
                                    line: index + 1,
                                    preview: String(line.prefix(200))))
                    break
                }
            }
        }
        return hits
    }

    /// 工作区占用统计
    func statistics() -> (files: Int, bytes: Int) {
        guard let enumerator = FileManager.default.enumerator(at: root,
                                                             includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                                                             options: [.skipsHiddenFiles]) else {
            return (0, 0)
        }
        var files = 0
        var bytes = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values?.isRegularFile == true {
                files += 1
                bytes += values?.fileSize ?? 0
            }
        }
        return (files, bytes)
    }
}
