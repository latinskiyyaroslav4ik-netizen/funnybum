import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// GPX is declared by the system as `com.topografix.gpx`; fall back to XML when unknown.
    static let gpx: UTType = UTType("com.topografix.gpx")
        ?? UTType(filenameExtension: "gpx", conformingTo: .xml)
        ?? .xml
}

/// In-memory GPX document used by `fileExporter`.
struct GPXFile: FileDocument {
    static var readableContentTypes: [UTType] { [.gpx, .xml] }
    static var writableContentTypes: [UTType] { [.gpx] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = string
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
