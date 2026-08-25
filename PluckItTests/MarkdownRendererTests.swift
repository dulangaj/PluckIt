//
//  MarkdownRendererTests.swift
//  PluckItTests
//

import XCTest
@testable import PluckIt

/// Markdown emission is a pure function of the node tree, so these run without
/// Vision — no recognition, no flakiness, no dependence on the OS model.
final class MarkdownRendererTests: XCTestCase {
    func testRendersHeadingsAndParagraphs() {
        let markdown = MarkdownRenderer.render([
            .heading(level: 1, text: "  Exclusive Welcome Offer  "),
            .paragraph("Available for New Cardmembers 全新卡會員專享")
        ])

        XCTAssertEqual(markdown, """
        # Exclusive Welcome Offer

        Available for New Cardmembers 全新卡會員專享

        """)
    }

    func testClampsHeadingLevelsToMarkdownRange() {
        XCTAssertEqual(MarkdownRenderer.render([.heading(level: 9, text: "Deep")]), "###### Deep\n")
        XCTAssertEqual(MarkdownRenderer.render([.heading(level: 0, text: "Shallow")]), "# Shallow\n")
    }

    func testEscapesPipesAndNewlinesInsideTableCells() {
        let markdown = MarkdownRenderer.render([
            .table(
                header: ["", "Explorer"],
                rows: [["Welcome Offer", "HK$4,400\nup to 高達"], ["Choice", "a | b"]]
            )
        ])

        XCTAssertEqual(markdown, """
        |  | Explorer |
        | --- | --- |
        | Welcome Offer | HK$4,400<br>up to 高達 |
        | Choice | a \\| b |

        """)
    }

    func testPadsShortRowsToTheHeaderWidth() {
        let markdown = MarkdownRenderer.render([
            .table(header: ["A", "B", "C"], rows: [["only"]])
        ])

        XCTAssertTrue(markdown.contains("| only |  |  |"), markdown)
    }

    func testNumbersFootnotesAndRendersBarcodesAsBlockquotes() {
        let markdown = MarkdownRenderer.render([
            .barcode(symbology: "QR", payload: "https://example.com/apply"),
            .rule,
            .footnotes(["Get HK$100 statement credit…", "Upon designated aggregate spending…"])
        ])

        XCTAssertEqual(markdown, """
        > **QR** `https://example.com/apply`

        ---

        [^1]: Get HK$100 statement credit…
        [^2]: Upon designated aggregate spending…

        """)
    }

    func testSkipsEmptyBlocks() {
        XCTAssertEqual(MarkdownRenderer.render([]), "")
        XCTAssertEqual(MarkdownRenderer.render([.paragraph("   "), .table(header: [], rows: [])]), "")
    }
}
