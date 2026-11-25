import Foundation

/// The build number and commit the app was built from, as the debug screen shows them.
struct BuildInfo: Equatable, Sendable {
    /// Shown in place of a commit by builds that were not given one (local and unsigned CI builds).
    static let placeholder = "dev"

    let buildNumber: String
    let commit: String

    init(infoDictionary: [String: Any]) {
        buildNumber = infoDictionary["CFBundleVersion"] as? String ?? ""
        let commit = infoDictionary["TsuzuriCommit"] as? String ?? ""
        self.commit = commit.isEmpty ? Self.placeholder : commit
    }

    /// The commit abbreviated the way `git log --oneline` shows it; the placeholder is already short.
    var shortCommit: String { String(commit.prefix(7)) }
}
