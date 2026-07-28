//
//  TextTransformation.swift
//  PluckIt
//

import Foundation

/// A one-shot cleanup applied to the extracted text, e.g. removing the line
/// breaks Vision inserts between recognized fragments.
enum TextTransformation: CaseIterable, Identifiable {
    case joinLines
    case joinHyphenatedLineBreaks
    case removeNewlines
    case removeSpaces
    case collapseSpaces
    case trimLines
    case removeEmptyLines

    var id: Self { self }

    var label: String {
        switch self {
        case .joinLines: "Join Lines"
        case .joinHyphenatedLineBreaks: "Join Hyphenated Line Breaks"
        case .removeNewlines: "Remove Newlines"
        case .removeSpaces: "Remove Spaces"
        case .collapseSpaces: "Collapse Spaces"
        case .trimLines: "Trim Line Whitespace"
        case .removeEmptyLines: "Remove Empty Lines"
        }
    }

    var help: String {
        switch self {
        case .joinLines:
            "Replace line breaks with a single space"
        case .joinHyphenatedLineBreaks:
            "Rejoin words split across lines, e.g. “exam-” / “ple” becomes “example”"
        case .removeNewlines:
            "Delete line breaks without adding spaces"
        case .removeSpaces:
            "Delete all spaces and tabs"
        case .collapseSpaces:
            "Reduce runs of spaces and tabs to a single space"
        case .trimLines:
            "Remove leading and trailing whitespace from every line"
        case .removeEmptyLines:
            "Delete blank lines"
        }
    }

    func apply(to text: String) -> String {
        switch self {
        case .joinLines:
            text.replacing(#/[ \t]*\n[ \t]*/#, with: " ")
        case .joinHyphenatedLineBreaks:
            text.replacing(#/(\p{L})-\n(\p{L})/#) { "\($0.output.1)\($0.output.2)" }
        case .removeNewlines:
            text.replacing("\n", with: "")
        case .removeSpaces:
            text.replacing(#/[ \t]/#, with: "")
        case .collapseSpaces:
            text.replacing(#/[ \t]{2,}/#, with: " ")
        case .trimLines:
            text.split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: "\n")
        case .removeEmptyLines:
            text.replacing(#/\n(?:[ \t]*\n)+/#, with: "\n")
        }
    }
}
