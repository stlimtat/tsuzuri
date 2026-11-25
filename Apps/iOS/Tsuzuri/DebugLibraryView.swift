import ComicStructure
import Persistence
import SwiftUI

/// Debug screen listing the Works in the Library; the App Shell replaces it.
struct DebugLibraryView: View {
    let model: DebugLibraryModel
    var buildInfo = BuildInfo(infoDictionary: Bundle.main.infoDictionary ?? [:])

    @State private var renaming: DebugLibraryRow?
    @State private var newName = ""
    @State private var deleting: DebugLibraryRow?
    @State private var failure: String?
    @State private var viewing: PageFile?

    var body: some View {
        NavigationStack {
            List(model.rows) { row in
                VStack(alignment: .leading) {
                    Text(verbatim: row.name).font(.headline)
                    Text("Pages: \(row.pageCount)")
                    Text("Downloaded: \(row.downloadedPageCount)")
                }
                .font(.subheadline)
                .contentShape(.rect)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("workRow")
                .onTapGesture { run { viewing = PageFile(url: try await model.firstPageFile(of: row.id)) } }
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
                        .accessibilityIdentifier("emptyLibrary")
                }
            }
            .safeAreaInset(edge: .top) {
                if let banner = model.banner { SyncBannerView(banner: banner) }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 2) {
                    if let status = model.syncStatus {
                        Text("iCloud: \(SyncStatusLine.text(for: status))", comment: "Debug screen: the Library's sync status.")
                            .accessibilityIdentifier("syncStatus")
                    }
                    Text("Build \(buildInfo.buildNumber) · \(buildInfo.shortCommit)")
                        .font(.caption.monospaced())
                        .accessibilityIdentifier("buildInfo")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .navigationTitle("Library (Debug)")
            .toolbar {
                Button("Add Sample Work", systemImage: "plus") { run { try await addSample() } }
                    .accessibilityIdentifier("addSampleWork")
            }
            .task { run { try await model.reload() } }
            .refreshable { do { try await model.refresh() } catch { failure = error.localizedDescription } }
            .alert("Rename Work", isPresented: isPresented($renaming)) {
                TextField("Name", text: $newName)
                    .accessibilityIdentifier("renameField")
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
                Text("This removes the Work and its files from this device, your other devices and iCloud.")
            }
            .sheet(item: $viewing) { page in
                NavigationStack {
                    Group {
                        if let picture = UIImage(contentsOfFile: page.url.path) {
                            Image(uiImage: picture).resizable().scaledToFit()
                                .accessibilityIdentifier("pageImage")
                        }
                    }
                    .toolbar { Button("Done") { viewing = nil } }
                }
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

/// A downloaded Page file the debug screen is showing.
struct PageFile: Identifiable {
    let url: URL
    var id: URL { url }
}

/// Says why changes aren't reaching iCloud; shown above the list without blocking anything.
struct SyncBannerView: View {
    let banner: SyncBanner

    var body: some View {
        Label {
            switch banner {
            case .offline:
                Text("iCloud is unavailable. Your changes are kept on this device and sync when iCloud is back.")
            case .iCloudFull:
                Text("Your iCloud storage is full. Your changes are kept on this device and sync when there is space.")
            }
        } icon: {
            Image(systemName: banner == .offline ? "icloud.slash" : "exclamationmark.icloud")
        }
        .font(.footnote)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.yellow.opacity(0.25), in: .rect(cornerRadius: 10))
        .padding(.horizontal)
        .accessibilityIdentifier("syncBanner")
    }
}
