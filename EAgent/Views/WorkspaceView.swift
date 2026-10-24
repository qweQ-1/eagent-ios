import SwiftUI
import QuickLook

/// 工作区：查看 AI 能碰到的那些文件（Documents/AgentWorkspace）。
struct WorkspaceView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var shareBroker: ShareBroker
    @State private var path: String = ""
    @State private var entries: [Workspace.Entry] = []
    @State private var errorText: String?
    @State private var previewItem: PreviewItem?
    @State private var showingCreate = false
    @State private var newFileName = ""
    @State private var newFileContent = ""

    private var workspace: Workspace {
        Workspace(folderName: store.settings.workspaceFolder)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Label(workspace.root.lastPathComponent, systemImage: "folder.fill")
                        Spacer()
                        Text("\(entries.count) 项")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }

                if let errorText {
                    Section {
                        Label(errorText, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }

                Section {
                    ForEach(entries) { entry in
                        if entry.isDirectory {
                            NavigationLink {
                                WorkspaceDirectoryView(path: entry.path, workspace: workspace)
                            } label: {
                                row(entry)
                            }
                        } else {
                            Button {
                                open(entry)
                            } label: {
                                row(entry)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("工作区")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingCreate = true
                        } label: {
                            Label("新建文本文件", systemImage: "doc.badge.plus")
                        }
                        Button {
                            shareFolder()
                        } label: {
                            Label("分享整个工作区", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showingCreate) {
                NavigationStack {
                    Form {
                        TextField("文件名，例如 notes.txt", text: $newFileName)
                        TextEditor(text: $newFileContent)
                            .frame(minHeight: 200)
                    }
                    .navigationTitle("新建文件")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("取消") { showingCreate = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("创建") { createFile() }
                        }
                    }
                }
            }
            .sheet(item: $previewItem) { item in
                PreviewSheet(item: item)
            }
            .onAppear(perform: reload)
            .onChange(of: store.settings.workspaceFolder) { _, _ in reload() }
        }
    }

    private func row(_ entry: Workspace.Entry) -> some View {
        HStack {
            Image(systemName: entry.isDirectory ? "folder" : "doc.text")
                .foregroundStyle(entry.isDirectory ? .blue : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.body)
                if !entry.isDirectory {
                    Text("\(entry.size) 字节")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private func reload() {
        do {
            workspace.ensureRootExists()
            entries = try workspace.listFiles(path)
            errorText = nil
        } catch {
            entries = []
            errorText = error.localizedDescription
        }
    }

    private func open(_ entry: Workspace.Entry) {
        guard let url = workspace.resolve(entry.path) else { return }
        previewItem = PreviewItem(url: url)
    }

    private func createFile() {
        let name = newFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            try workspace.writeFile(name, content: newFileContent)
            newFileName = ""
            newFileContent = ""
            showingCreate = false
            reload()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func shareFolder() {
        // 先把 broker 取出来再用，避免在 Task 里回头访问 EnvironmentObject
        let broker = shareBroker
        Task { _ = await broker.present(text: "iAgent 工作区：\(workspace.root.path)", fileURL: workspace.root) }
    }
}

/// 预览一个文件
struct PreviewItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// 预览面板：文本直接显示，其它类型用 QuickLook
struct PreviewSheet: View {
    let item: PreviewItem
    @Environment(\.dismiss) private var dismiss
    @State private var text: String?

    var body: some View {
        NavigationStack {
            Group {
                if let text {
                    ScrollView {
                        Text(text)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                } else {
                    QuickLookPreview(url: item.url)
                        .ignoresSafeArea()
                }
            }
            .navigationTitle(item.url.lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .task {
            if let data = try? Data(contentsOf: item.url),
               let content = String(data: data, encoding: .utf8) {
                text = content
            }
        }
    }
}

/// QuickLook 预览
struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

/// 子目录浏览
struct WorkspaceDirectoryView: View {
    let path: String
    let workspace: Workspace
    @State private var entries: [Workspace.Entry] = []
    @State private var previewItem: PreviewItem?

    var body: some View {
        List {
            ForEach(entries) { entry in
                if entry.isDirectory {
                    NavigationLink {
                        WorkspaceDirectoryView(path: entry.path, workspace: workspace)
                    } label: {
                        Label(entry.name, systemImage: "folder")
                    }
                } else {
                    Button {
                        if let url = workspace.resolve(entry.path) {
                            previewItem = PreviewItem(url: url)
                        }
                    } label: {
                        Label(entry.name, systemImage: "doc.text")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle(path)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $previewItem) { PreviewSheet(item: $0) }
        .onAppear {
            entries = (try? workspace.listFiles(path)) ?? []
        }
    }
}
