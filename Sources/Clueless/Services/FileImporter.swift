import Foundation
import PDFKit
import CluelessCore

enum ImportError: Error, LocalizedError {
    case unsupportedType(String)
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedType(let ext): return "Unsupported file type: .\(ext) (pdf, docx, txt, md supported)"
        case .unreadable(let name): return "Could not read \(name)"
        }
    }
}

/// Extracts plain text from uploaded files: PDF (PDFKit), docx (unzip + XML strip),
/// txt/md (plain read).
enum FileImporter {
    static func importFile(at url: URL) throws -> ContextFile {
        let name = url.lastPathComponent
        switch url.pathExtension.lowercased() {
        case "pdf":
            guard let doc = PDFDocument(url: url), let text = doc.string, !text.isEmpty else {
                throw ImportError.unreadable(name)
            }
            return ContextFile(name: name, text: text)
        case "docx":
            return ContextFile(name: name, text: try extractDocxText(url: url))
        case "txt", "md", "markdown", "text":
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                throw ImportError.unreadable(name)
            }
            return ContextFile(name: name, text: text)
        default:
            throw ImportError.unsupportedType(url.pathExtension)
        }
    }

    /// docx = zip; body text lives in word/document.xml. Paragraphs → newlines,
    /// remaining tags stripped.
    private static func extractDocxText(url: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", url.path, "word/document.xml"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, !data.isEmpty else {
            throw ImportError.unreadable(url.lastPathComponent)
        }
        var xml = String(decoding: data, as: UTF8.self)
        xml = xml.replacingOccurrences(of: "</w:p>", with: "\n")
        xml = xml.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        // Decode the handful of XML entities Word actually emits.
        xml = xml
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
        let text = xml.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ImportError.unreadable(url.lastPathComponent) }
        return text
    }
}
