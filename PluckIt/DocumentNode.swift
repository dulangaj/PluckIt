//
//  DocumentNode.swift
//  PluckIt
//

import Foundation

/// A structural element of an extracted document.
///
/// This is deliberately independent of Vision so markdown generation stays a
/// pure, synchronous function that tests can drive without running recognition.
indirect enum DocumentNode: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case table(header: [String], rows: [[String]])
    case barcode(symbology: String, payload: String)
    case footnotes([String])
    case rule
}

enum MarkdownRenderer {
    static func render(_ nodes: [DocumentNode]) -> String {
        let blocks = nodes.map(block(for:)).filter { !$0.isEmpty }
        return blocks.isEmpty ? "" : blocks.joined(separator: "\n\n") + "\n"
    }

    private static func block(for node: DocumentNode) -> String {
        switch node {
        case let .heading(level, text):
            String(repeating: "#", count: min(max(level, 1), 6)) + " " + trimmed(text)
        case let .paragraph(text):
            trimmed(text)
        case let .table(header, rows):
            table(header: header, rows: rows)
        case let .barcode(symbology, payload):
            "> **\(symbology)** `\(payload)`"
        case let .footnotes(items):
            items.enumerated()
                .map { "[^\($0.offset + 1)]: \(trimmed($0.element))" }
                .joined(separator: "\n")
        case .rule:
            "---"
        }
    }

    private static func table(header: [String], rows: [[String]]) -> String {
        guard !header.isEmpty else { return "" }
        // Every row is padded to the header width; markdown has no ragged rows.
        let body = rows.map { row($0, width: header.count) }
        let separator = "|" + String(repeating: " --- |", count: header.count)
        return ([row(header, width: header.count), separator] + body).joined(separator: "\n")
    }

    private static func row(_ cells: [String], width: Int) -> String {
        let padded = (0 ..< width).map { $0 < cells.count ? cells[$0] : "" }
        return "| " + padded.map(cell(for:)).joined(separator: " | ") + " |"
    }

    /// A cell can hold neither a raw pipe nor a newline.
    private static func cell(for text: String) -> String {
        trimmed(text)
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: "<br>")
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
