import Foundation
import Testing

@Suite struct LibraryLaunchTests {
    private let temporary = URL(filePath: "/tmp/sandbox", directoryHint: .isDirectory)

    @Test func withoutTheArgumentTheAppOpensTheLiveLibrary() {
        let launch = LibraryLaunch(arguments: ["Tsuzuri"], environment: [LibraryLaunch.libraryDirectoryKey: "/tmp/x"],
                                   temporaryDirectory: temporary)

        #expect(launch == .live)
    }

    @Test func uiTestingWithoutADirectoryGetsANewOneUnderTemporary() {
        let launch = LibraryLaunch(arguments: ["Tsuzuri", "-TsuzuriUITesting"], environment: [:],
                                   temporaryDirectory: temporary, newName: { "fresh" })

        #expect(launch == .uiTesting(root: temporary.appending(path: "fresh", directoryHint: .isDirectory)))
    }

    @Test func eachUITestingLaunchWithoutADirectoryGetsADifferentOne() {
        let first = LibraryLaunch(arguments: ["-TsuzuriUITesting"], environment: [:], temporaryDirectory: temporary)
        let second = LibraryLaunch(arguments: ["-TsuzuriUITesting"], environment: [:], temporaryDirectory: temporary)

        #expect(first != second)
    }

    @Test func uiTestingReopensTheDirectoryTheEnvironmentNames() {
        let launch = LibraryLaunch(arguments: ["-TsuzuriUITesting"],
                                   environment: [LibraryLaunch.libraryDirectoryKey: "run-1"],
                                   temporaryDirectory: temporary)

        #expect(launch == .uiTesting(root: temporary.appending(path: "run-1", directoryHint: .isDirectory)))
    }

    @Test func anEmptyDirectoryIsIgnored() {
        let launch = LibraryLaunch(arguments: ["-TsuzuriUITesting"], environment: [LibraryLaunch.libraryDirectoryKey: ""],
                                   temporaryDirectory: temporary, newName: { "fresh" })

        #expect(launch == .uiTesting(root: temporary.appending(path: "fresh", directoryHint: .isDirectory)))
    }
}
