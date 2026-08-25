//
//  LayoutInferenceTests.swift
//  PluckItTests
//

import XCTest
@testable import PluckIt

/// Column inference is pure geometry, so it is tested on hand-built blocks
/// rather than through recognition.
final class LayoutInferenceTests: XCTestCase {
    func testFindsTwoColumnsInASideBySideComparison() throws {
        let blocks = comparison()
        let bands = try XCTUnwrap(LayoutInference.columnBands(in: blocks))

        XCTAssertEqual(bands.count, 2)
        XCTAssertEqual(bands.map(\.count), [4, 4])
        XCTAssertEqual(LayoutInference.rows(pairing: bands), [
            ["Explorer", "Platinum"],
            ["HK$4,400", "HK$6,800"],
            ["Waived", "HK$9,500"],
            ["20% credit", "HK$5,800"]
        ])
    }

    /// Columns are seldom typeset on a shared baseline; a consistent offset
    /// between them must not slide the rows out of step.
    func testAlignsColumnsThatSitAtDifferentHeights() throws {
        let blocks = comparison(rightOffset: 0.03)
        let bands = try XCTUnwrap(LayoutInference.columnBands(in: blocks))

        XCTAssertEqual(LayoutInference.rows(pairing: bands).first, ["Explorer", "Platinum"])
    }

    func testRejectsOrdinaryProse() {
        let blocks = (0 ..< 10).map { index in
            TextBlock(
                id: index,
                text: "line \(index)",
                frame: CGRect(x: 0.08, y: 0.9 - Double(index) * 0.08, width: 0.84, height: 0.05)
            )
        }

        XCTAssertNil(LayoutInference.columnBands(in: blocks))
    }

    func testRejectsStackedSectionsThatDoNotOverlapVertically() {
        var blocks = (0 ..< 4).map { index in
            TextBlock(id: index, text: "top \(index)",
                      frame: CGRect(x: 0.05, y: 0.9 - Double(index) * 0.05, width: 0.3, height: 0.04))
        }
        blocks += (0 ..< 4).map { index in
            TextBlock(id: index + 4, text: "bottom \(index)",
                      frame: CGRect(x: 0.6, y: 0.3 - Double(index) * 0.05, width: 0.3, height: 0.04))
        }

        XCTAssertNil(LayoutInference.columnBands(in: blocks))
    }

    /// Two aligned columns of four rows, optionally with the right column
    /// shifted up the page.
    private func comparison(rightOffset: Double = 0) -> [TextBlock] {
        let left = ["Explorer", "HK$4,400", "Waived", "20% credit"]
        let right = ["Platinum", "HK$6,800", "HK$9,500", "HK$5,800"]

        return left.enumerated().map { index, text in
            TextBlock(id: index, text: text,
                      frame: CGRect(x: 0.08, y: 0.8 - Double(index) * 0.15, width: 0.3, height: 0.05))
        } + right.enumerated().map { index, text in
            TextBlock(id: index + 4, text: text,
                      frame: CGRect(x: 0.6, y: 0.8 + rightOffset - Double(index) * 0.15, width: 0.3, height: 0.05))
        }
    }
}
