import Testing

@Suite struct BuildInfoTests {
    @Test func releaseBuildShowsItsBuildNumberAndCommit() {
        let info = BuildInfo(infoDictionary: [
            "CFBundleVersion": "42",
            "TsuzuriCommit": "0123456789abcdef0123456789abcdef01234567",
        ])

        #expect(info.buildNumber == "42")
        #expect(info.commit == "0123456789abcdef0123456789abcdef01234567")
    }

    @Test func buildWithoutACommitShowsDev() {
        let info = BuildInfo(infoDictionary: ["CFBundleVersion": "1"])

        #expect(info.commit == "dev")
    }

    /// A local build leaves the `TSUZURI_COMMIT` build setting empty, so Info.plist holds an empty string.
    @Test func buildWithAnEmptyCommitShowsDev() {
        let info = BuildInfo(infoDictionary: ["CFBundleVersion": "1", "TsuzuriCommit": ""])

        #expect(info.commit == "dev")
    }

    @Test func shortCommitIsTheFirstSevenCharacters() {
        let info = BuildInfo(infoDictionary: ["TsuzuriCommit": "0123456789abcdef0123456789abcdef01234567"])

        #expect(info.shortCommit == "0123456")
    }
}
