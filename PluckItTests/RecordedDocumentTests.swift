//
//  RecordedDocumentTests.swift
//  PluckItTests
//

import Vision
import XCTest
@testable import PluckIt

/// Replays `DocumentObservation`s recorded from real recognition runs.
///
/// `DocumentObservation` is `Codable`, so the layout inference and markdown
/// emission can be exercised with no Vision calls at all: these run in
/// microseconds and, when an OS update shifts recognition, they keep failing
/// for "our inference broke" separately from "Vision changed".
final class RecordedDocumentTests: XCTestCase {
    func testTwoColumnCardBecomesATable() throws {
        let container = try recordedDocument(named: "two-column-card")
        let markdown = MarkdownRenderer.render(DocumentPipeline.nodes(in: container))

        XCTAssertEqual(DocumentPipeline.layout(of: container), .structured)
        XCTAssertTrue(markdown.contains("| --- | --- |"), "Expected an inferred table:\n\(markdown)")
        XCTAssertTrue(markdown.contains("[^1]:"), "Expected footnotes:\n\(markdown)")
        XCTAssertTrue(markdown.contains("> **QR**"), "Expected the QR code:\n\(markdown)")
        // The two product columns pair up rather than staircasing past each other.
        XCTAssertTrue(markdown.contains("| Platinum Card | Gold Card |"), markdown)
    }

    func testSimpleLineStaysFlat() throws {
        let container = try recordedDocument(named: "simple-line")
        let markdown = MarkdownRenderer.render(DocumentPipeline.nodes(in: container))

        XCTAssertEqual(DocumentPipeline.layout(of: container), .simple)
        XCTAssertFalse(markdown.contains("| --- |"), "A single line is not a table:\n\(markdown)")
    }

    /// Photographed-poster regression, checked against a golden rendering.
    ///
    /// OCR of a photograph is never character-exact across model revisions, so
    /// the gate is token overlap rather than equality: a broken layout collapses
    /// it long before ordinary recognition drift does.
    func testPosterPhotoMatchesGolden() throws {
        let container = try recordedDocument(named: "amex-poster")
        let markdown = MarkdownRenderer.render(DocumentPipeline.nodes(in: container))
        let golden = try String(contentsOf: fixture("amex-poster.md"), encoding: .utf8)

        XCTAssertEqual(DocumentPipeline.layout(of: container), .structured)
        for required in [
            "| American Express Explorer® Credit Card | The Platinum Card® |",
            "| HK$4,400* | HK$6,800* |",
            "> **QR** `https://chg.la/tentcard+cashier`",
        ] {
            XCTAssertTrue(markdown.contains(required), "Missing \(required):\n\(markdown)")
        }
        // The comparison must swallow neither the banner above it nor the small print below.
        XCTAssertFalse(markdown.contains("| Promotion Period"), markdown)
        XCTAssertTrue(markdown.contains("Terms and Conditions apply"), markdown)
        XCTAssertGreaterThanOrEqual(Self.tokenF1(markdown, golden), 0.8, markdown)
    }

    /// Harmonic mean of token precision and recall — order-insensitive, so
    /// reflowed output is only penalised when the words themselves change.
    private static func tokenF1(_ lhs: String, _ rhs: String) -> Double {
        let tokens = { (text: String) in
            Set(text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        }
        let (left, right) = (tokens(lhs), tokens(rhs))
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        return 2 * Double(left.intersection(right).count) / Double(left.count + right.count)
    }

    private func fixture(_ name: String) -> URL {
        URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/\(name)")
    }

    /// Fixtures are read from the source tree rather than the test bundle so
    /// they stay plain files that `record.swift` can rewrite in place.
    private func recordedDocument(named name: String) throws -> DocumentObservation.Container {
        let data = try Data(contentsOf: fixture("\(name).observation.json"))
        return try JSONDecoder().decode(DocumentObservation.self, from: data).document
    }
}
