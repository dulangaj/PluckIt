//
//  TextRecognizer.swift
//  PluckIt
//

import CoreGraphics
import CoreText
import Foundation
import Vision

/// Wraps Vision text recognition behind a small async API.
struct TextRecognizer {
    struct Extraction {
        let text: String
        /// Length-weighted average confidence (0...1); nil when no text was found.
        let confidence: Float?
    }

    func recognize(in image: CGImage) async throws -> Extraction {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let observations = try await request.perform(on: image)
        let candidates = observations.compactMap { $0.topCandidates(1).first }

        // Weight each line's confidence by its length so a short, low-scoring
        // fragment doesn't drag down the average for a clear block of text.
        let totalCharacters = candidates.reduce(0) { $0 + $1.string.count }
        let confidence: Float? = totalCharacters == 0
            ? nil
            : candidates.reduce(Float(0)) { $0 + $1.confidence * Float($1.string.count) } / Float(totalCharacters)

        return Extraction(
            text: candidates.map(\.string).joined(separator: "\n"),
            confidence: confidence
        )
    }

    /// Runs recognition once on a small generated image so the system compiles
    /// and caches the recognition models before the first real extraction.
    ///
    /// After an OS update invalidates the compiled-model cache, the first
    /// recognition can take tens of seconds; doing it at launch keeps that
    /// cost off the user's first real request.
    func warmUp() async {
        guard let image = Self.makeWarmUpImage() else { return }
        _ = try? await recognize(in: image)
    }

    /// A white bitmap with a line of text — real glyphs, so the warm-up
    /// exercises the full detection and recognition pipeline.
    private static func makeWarmUpImage() -> CGImage? {
        let width = 240
        let height = 64
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

        let font = CTFontCreateWithName("Helvetica" as CFString, 28, nil)
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(
                string: "Warming up 123",
                attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]
            )
        )
        context.textPosition = CGPoint(x: 16, y: 20)
        CTLineDraw(line, context)

        return context.makeImage()
    }
}
