import Foundation
import Testing

/// specs/R1/app-shell.md: no glossary _Avoid_ term appears in a UI string.
@Suite struct UIStringsTests {
    static let repo = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Every term after `_Avoid_:` in CONTEXT.md, without its parenthesised note, lowercased.
    static func avoidTerms(glossary: String) -> [String] {
        glossary.split(separator: "\n")
            .filter { $0.hasPrefix("_Avoid_:") }
            .flatMap { $0.dropFirst("_Avoid_:".count).replacing(/\([^)]*\)/, with: "").split(separator: ",") }
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
    }

    /// Every key and every localized value in a String Catalog.
    static func uiStrings(catalog: Data) throws -> [String] {
        let json = try #require(try JSONSerialization.jsonObject(with: catalog) as? [String: Any])
        let strings = try #require(json["strings"] as? [String: Any])
        var found = Array(strings.keys)
        func collect(_ node: Any) {
            if let dict = node as? [String: Any] {
                if let value = dict["value"] as? String { found.append(value) }
                dict.values.forEach(collect)
            } else if let array = node as? [Any] {
                array.forEach(collect)
            }
        }
        collect(strings)
        return found
    }

    /// The Avoid terms that appear as whole words in `text`, ignoring case.
    static func avoidTermsUsed(in text: String, terms: [String]) -> [String] {
        terms.filter { term in
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: term) + "\\b"
            return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    @Test func glossaryTermsAreReadFromAvoidLines() {
        let glossary = """
            **Work**:
            One title in the Library.
            _Avoid_: Item, title, book (when the kind is unknown)
            """
        #expect(Self.avoidTerms(glossary: glossary) == ["item", "title", "book"])
    }

    @Test func avoidTermsMatchWholeWordsOnly() {
        let terms = ["image", "text box"]
        #expect(Self.avoidTermsUsed(in: "Add an Image", terms: terms) == ["image"])
        #expect(Self.avoidTermsUsed(in: "Edit the text box", terms: terms) == ["text box"])
        #expect(Self.avoidTermsUsed(in: "Imagery", terms: terms).isEmpty)
    }

    @Test func appStringCatalogUsesNoAvoidTerms() throws {
        let terms = Self.avoidTerms(glossary: try String(contentsOf: Self.repo.appending(path: "CONTEXT.md"), encoding: .utf8))
        let strings = try Self.uiStrings(catalog: Data(contentsOf: Self.repo.appending(path: "Apps/iOS/Tsuzuri/Localizable.xcstrings")))
        #expect(!terms.isEmpty)
        #expect(!strings.isEmpty)
        for string in strings {
            #expect(Self.avoidTermsUsed(in: string, terms: terms).isEmpty, "UI string uses a glossary Avoid term: \(string)")
        }
    }

    /// Literals in the app's own Swift sources, in case one reaches the UI before the String Catalog lists it.
    @Test func appSourceStringLiteralsUseNoAvoidTerms() throws {
        let terms = Self.avoidTerms(glossary: try String(contentsOf: Self.repo.appending(path: "CONTEXT.md"), encoding: .utf8))
        var literals: [String] = []
        for dir in ["Apps/iOS/Tsuzuri", "Apps/iOS/LibraryDebug"] {
            let files = try FileManager.default.contentsOfDirectory(at: Self.repo.appending(path: dir), includingPropertiesForKeys: nil)
            for file in files where file.pathExtension == "swift" {
                let source = try String(contentsOf: file, encoding: .utf8)
                literals += source.matches(of: /"(?:[^"\\\n]|\\.)*"/).map { String($0.output) }
            }
        }
        #expect(!literals.isEmpty)
        for literal in literals {
            #expect(Self.avoidTermsUsed(in: literal, terms: terms).isEmpty, "App string uses a glossary Avoid term: \(literal)")
        }
    }
}
