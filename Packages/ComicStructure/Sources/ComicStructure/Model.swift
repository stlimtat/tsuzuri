import Foundation

// The shared domain model. Terms follow CONTEXT.md exactly.

/// Opaque reference to a file (Source, Page image, reference crop, Render video), resolved by Persistence.
public struct FileRef: Hashable, Codable, Sendable {
    public var id: String
    public init(_ id: String) { self.id = id }
}

public typealias ImageRef = FileRef

public enum WorkKind: String, Codable, Sendable, CaseIterable { case comic, book }

public enum ReadingDirection: String, Codable, Sendable, CaseIterable { case rightToLeft, leftToRight, verticalScroll }

public struct PixelSize: Hashable, Codable, Sendable {
    public var width: Int
    public var height: Int
    public init(width: Int, height: Int) { self.width = width; self.height = height }
}

public struct Work: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var kind: WorkKind
    public var title: String
    public var readingDirection: ReadingDirection
    /// BCP 47 language code, e.g. "ja".
    public var sourceLanguage: String
    /// BCP 47 language code, e.g. "en".
    public var targetLanguage: String
    public var sources: [Source]
    /// Comics only; empty for books.
    public var chapters: [Chapter]
    public var cast: Cast
    public var renders: [Render]

    public init(
        id: UUID = UUID(), createdAt: Date = Date(), updatedAt: Date? = nil, kind: WorkKind, title: String,
        readingDirection: ReadingDirection, sourceLanguage: String = "ja", targetLanguage: String = "en",
        sources: [Source] = [], chapters: [Chapter] = [], cast: Cast = Cast(), renders: [Render] = []
    ) {
        self.id = id; self.createdAt = createdAt; self.updatedAt = updatedAt ?? createdAt
        self.kind = kind; self.title = title; self.readingDirection = readingDirection
        self.sourceLanguage = sourceLanguage; self.targetLanguage = targetLanguage
        self.sources = sources; self.chapters = chapters; self.cast = cast; self.renders = renders
    }
}

public struct Source: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var fileName: String
    /// Uniform type identifier, e.g. "public.zip-archive".
    public var contentType: String
    public var byteSize: Int64
    public var fileRef: FileRef

    public init(id: UUID = UUID(), createdAt: Date = Date(), updatedAt: Date? = nil, fileName: String, contentType: String, byteSize: Int64, fileRef: FileRef) {
        self.id = id; self.createdAt = createdAt; self.updatedAt = updatedAt ?? createdAt
        self.fileName = fileName; self.contentType = contentType; self.byteSize = byteSize; self.fileRef = fileRef
    }
}

public struct Chapter: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var title: String
    /// Position in the Work's chapter list; kept equal to the array position by every operation.
    public var index: Int
    public var pages: [Page]
    /// The Panels of this Chapter (a Panel belongs to exactly one Chapter).
    public var panels: [Panel]
    public var storySummary: String?

    public init(id: UUID = UUID(), createdAt: Date = Date(), updatedAt: Date? = nil, title: String, index: Int, pages: [Page] = [], panels: [Panel] = [], storySummary: String? = nil) {
        self.id = id; self.createdAt = createdAt; self.updatedAt = updatedAt ?? createdAt
        self.title = title; self.index = index; self.pages = pages; self.panels = panels; self.storySummary = storySummary
    }
}

public enum PageOrigin: Hashable, Codable, Sendable {
    /// Taken as-is from an entry of the Source (e.g. the path inside a CBZ).
    case sourceEntry(String)
    /// Split from another Page; `crop` is absolute, in normalized coordinates of `imageRef`.
    case split(from: UUID, crop: Rect)
}

public struct Page: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var imageRef: ImageRef
    public var pixelSize: PixelSize
    /// Position in the Chapter's page list; kept equal to the array position by every operation.
    public var index: Int
    public var origin: PageOrigin

    public init(id: UUID = UUID(), createdAt: Date = Date(), updatedAt: Date? = nil, imageRef: ImageRef, pixelSize: PixelSize, index: Int, origin: PageOrigin) {
        self.id = id; self.createdAt = createdAt; self.updatedAt = updatedAt ?? createdAt
        self.imageRef = imageRef; self.pixelSize = pixelSize; self.index = index; self.origin = origin
    }

    /// The region of `imageRef` this Page shows.
    public var crop: Rect {
        if case .split(_, let crop) = origin { return crop }
        return .unit
    }
}

public struct Panel: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    /// 1 or 2 Pages; if 2, adjacent and in Chapter page order.
    public var pageIDs: [UUID]
    /// Convex polygon in normalized coordinates of a virtual canvas spanning `pageIDs` (see `Canvas`).
    public var shape: Polygon
    public var readingIndex: Int
    /// `.user` once the user moves the Panel; recomputing reading order keeps it at its index.
    public var readingOrderSource: ReadingOrderSource
    public var bubbles: [Bubble]

    public init(id: UUID = UUID(), createdAt: Date = Date(), updatedAt: Date? = nil, pageIDs: [UUID], shape: Polygon, readingIndex: Int, readingOrderSource: ReadingOrderSource = .detected, bubbles: [Bubble] = []) {
        self.id = id; self.createdAt = createdAt; self.updatedAt = updatedAt ?? createdAt
        self.pageIDs = pageIDs; self.shape = shape; self.readingIndex = readingIndex
        self.readingOrderSource = readingOrderSource; self.bubbles = bubbles
    }
}

public enum ReadingOrderSource: String, Codable, Sendable { case detected, user }

public enum TextOrientation: String, Codable, Sendable, CaseIterable { case horizontal, vertical }
public enum OrientationSource: String, Codable, Sendable { case detected, user }

public struct Bubble: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    /// Convex polygon in the same coordinates as its Panel's shape.
    public var shape: Polygon
    public var textOrientation: TextOrientation
    public var orientationSource: OrientationSource
    public var line: Line?

    public init(id: UUID = UUID(), createdAt: Date = Date(), updatedAt: Date? = nil, shape: Polygon, textOrientation: TextOrientation, orientationSource: OrientationSource = .detected, line: Line? = nil) {
        self.id = id; self.createdAt = createdAt; self.updatedAt = updatedAt ?? createdAt
        self.shape = shape; self.textOrientation = textOrientation; self.orientationSource = orientationSource; self.line = line
    }
}

public enum OCRSource: String, Codable, Sendable { case onDevice, cloud, user }
public enum TranslationSource: String, Codable, Sendable { case onDevice, user }
public enum SpeakerSource: String, Codable, Sendable { case proposed, user }

/// Furigana over `sourceText[start ..< start + length]`, counted in Characters (grapheme clusters).
public struct RubySpan: Hashable, Codable, Sendable {
    public var start: Int
    public var length: Int
    public var reading: String
    public init(start: Int, length: Int, reading: String) { self.start = start; self.length = length; self.reading = reading }
}

public struct Line: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var sourceText: String
    public var translation: String
    public var ocrSource: OCRSource
    public var translationSource: TranslationSource
    public var speakerID: UUID?
    public var speakerSource: SpeakerSource
    public var furigana: [RubySpan]

    public init(id: UUID = UUID(), createdAt: Date = Date(), updatedAt: Date? = nil, sourceText: String, translation: String = "", ocrSource: OCRSource, translationSource: TranslationSource = .onDevice, speakerID: UUID? = nil, speakerSource: SpeakerSource = .proposed, furigana: [RubySpan] = []) {
        self.id = id; self.createdAt = createdAt; self.updatedAt = updatedAt ?? createdAt
        self.sourceText = sourceText; self.translation = translation; self.ocrSource = ocrSource
        self.translationSource = translationSource; self.speakerID = speakerID; self.speakerSource = speakerSource; self.furigana = furigana
    }
}

public struct Character: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var name: String
    /// At least one.
    public var referenceCrops: [ImageRef]
    public var voiceDescription: String

    public init(id: UUID = UUID(), createdAt: Date = Date(), updatedAt: Date? = nil, name: String, referenceCrops: [ImageRef], voiceDescription: String = "") {
        self.id = id; self.createdAt = createdAt; self.updatedAt = updatedAt ?? createdAt
        self.name = name; self.referenceCrops = referenceCrops; self.voiceDescription = voiceDescription
    }
}

public struct Cast: Hashable, Codable, Sendable {
    public var characters: [Character]
    public init(characters: [Character] = []) { self.characters = characters }
}

public enum RenderStatus: Hashable, Codable, Sendable {
    case queued, running, ready
    case failed(reason: String)
    case blocked(reason: String)
}

public struct Render: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var chapterID: UUID
    /// 1–10 Panels, consecutive by reading index when created.
    public var panelIDs: [UUID]
    public var status: RenderStatus
    public var videoRef: FileRef?
    public var deliveredResolution: PixelSize?
    public var presets: [String]
    public var note: String
    /// `ComicEditor.inputsHash` at creation; a mismatch means the Render is stale.
    public var inputsHash: String
    public var providerID: String

    public init(id: UUID = UUID(), createdAt: Date = Date(), updatedAt: Date? = nil, chapterID: UUID, panelIDs: [UUID], status: RenderStatus = .queued, videoRef: FileRef? = nil, deliveredResolution: PixelSize? = nil, presets: [String] = [], note: String = "", inputsHash: String, providerID: String) {
        self.id = id; self.createdAt = createdAt; self.updatedAt = updatedAt ?? createdAt
        self.chapterID = chapterID; self.panelIDs = panelIDs; self.status = status; self.videoRef = videoRef
        self.deliveredResolution = deliveredResolution; self.presets = presets; self.note = note
        self.inputsHash = inputsHash; self.providerID = providerID
    }
}
