//
//  TextRecognizerTests.swift
//  PluckItTests
//

import CoreImage.CIFilterBuiltins
import CoreText
import Vision
import XCTest
@testable import PluckIt

final class DocumentPipelineTests: XCTestCase {
    /// A caption and a QR code is a simple image: a flat transcript reads
    /// better than markdown, and Auto should say so.
    func testRecognizesTextAndQRCodeInTheSameImage() async throws {
        let payload = "https://example.com/pluckit"
        let caption = "Scan me"
        let image = try XCTUnwrap(CGImage.makeQRCodeWithCaption(payload: payload, caption: caption))

        let extraction = try await DocumentPipeline().extract(from: image)

        XCTAssertTrue(extraction.plainText.contains(caption), "Expected caption in \(extraction.plainText)")
        XCTAssertEqual(extraction.barcodes.map(\.payload), [payload])
        XCTAssertEqual(extraction.barcodes.first?.symbology, .qr)
        XCTAssertEqual(extraction.barcodes.first?.symbologyLabel, "QR")
        XCTAssertEqual(extraction.layout, .simple)
        XCTAssertEqual(extraction.text(for: .automatic), extraction.plainText)
    }
}

private extension CGImage {
    /// A white canvas with a QR code above a line of real text.
    static func makeQRCodeWithCaption(payload: String, caption: String) -> CGImage? {
        let width = 400
        let height = 480
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.setFillColor(CGColor.white)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let generator = CIFilter.qrCodeGenerator()
        generator.message = Data(payload.utf8)
        guard let output = generator.outputImage,
              let qrCode = CIContext().createCGImage(output, from: output.extent) else { return nil }
        context.interpolationQuality = .none
        context.draw(qrCode, in: CGRect(x: 60, y: 140, width: 280, height: 280))

        let font = CTFontCreateWithName("Helvetica" as CFString, 40, nil)
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(
                string: caption,
                attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]
            )
        )
        context.textPosition = CGPoint(x: 60, y: 60)
        CTLineDraw(line, context)

        return context.makeImage()
    }
}
