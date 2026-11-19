import ComicStructure
import SwiftUI

/// Debug screen listing the Works in the Library; the App Shell replaces it.
struct DebugLibraryView: View {
    let model: DebugLibraryModel
    var buildInfo = BuildInfo(infoDictionary: Bundle.main.infoDictionary ?? [:])

    @State private var renaming: DebugLibraryRow?
    @State private var newName = ""
    @State private var deleting: DebugLibraryRow?
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            List(model.rows) { row in
                VStack(alignment: .leading) {
                    Text(verbatim: row.name).font(.headline)
                    Text("Pages: \(row.pageCount)")
                    Text("Downloaded: \(row.downloadedPageCount)")
                }
                .font(.subheadline)
                .swipeActions {
                    Button("Delete", role: .destructive) { deleting = row }
                    Button("Rename") { newName = row.name; renaming = row }
                }
                .contextMenu {
                    Button("Rename") { newName = row.name; renaming = row }
                    Button("Delete", role: .destructive) { deleting = row }
                }
            }
            .overlay {
                if model.rows.isEmpty {
                    ContentUnavailableView("No Works", systemImage: "books.vertical",
                                           description: Text("Add a sample Work to try the Library."))
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text("Build \(buildInfo.buildNumber) · \(buildInfo.shortCommit)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("buildInfo")
            }
            .navigationTitle("Library (Debug)")
            .toolbar {
                Button("Add Sample Work", systemImage: "plus") { run { try await addSample() } }
            }
            .task { run { try await model.reload() } }
            .refreshable { run { try await model.reload() } }
            .alert("Rename Work", isPresented: isPresented($renaming)) {
                TextField("Name", text: $newName)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    guard let row = renaming else { return }
                    run { try await model.rename(row.id, to: newName) }
                }
                .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .confirmationDialog(deletingPrompt, isPresented: isPresented($deleting), titleVisibility: .visible,
                                presenting: deleting) { row in
                Button("Delete", role: .destructive) { run { try await model.delete(row.id) } }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("This removes the Work and its files from this device.")
            }
            .alert("Something went wrong", isPresented: isPresented($failure)) {
                Button("OK") {}
            } message: {
                Text(verbatim: failure ?? "")
            }
        }
    }

    private var deletingPrompt: Text {
        Text("Delete “\(deleting?.name ?? "")”?")
    }

    private func addSample() async throws {
        guard let page = Bundle.main.url(forResource: "p01-vertical-grid", withExtension: "png") else {
            throw CocoaError(.fileNoSuchFile)
        }
        try await model.createSampleWork(fromPage: page, name: String(localized: "Sample Work"))
    }

    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        Task {
            do { try await action() } catch { failure = error.localizedDescription }
        }
    }

    private func isPresented<Value>(_ value: Binding<Value?>) -> Binding<Bool> {
        Binding(get: { value.wrappedValue != nil }, set: { if !$0 { value.wrappedValue = nil } })
    }
}
