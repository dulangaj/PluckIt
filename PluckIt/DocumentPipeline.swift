//
//  DocumentPipeline.swift
//  PluckIt
//

import CoreGraphics
import CoreImage.CIFilterBuiltins
import CoreText
import Foundation
import Vision

/// Turns an image into text, running Vision's document recognizer over a
/// cropped, perspective-corrected view of whatever document is in frame.
struct DocumentPipeline {
    struct Extraction {
        /// Structured rendering of the document.
        let markdown: String
        /// Flat transcript, in reading order.
        let plainText: String
        let barcodes: [Barcode]
        let layout: Layout

        /// The text to show for a given output mode.
        func text(for mode: OutputMode) -> String {
            switch mode {
            case .automatic: layout == .structured ? markdown : plainText
            case .markdown: markdown
            case .plainText: plainText
            }
        }
    }

    /// How much structure the recognized document turned out to have.
    enum Layout: Equatable {
        /// A sign, a phone number, a snippet — a flat transcript reads best.
        case simple
        /// Tables, columns or footnotes — worth rendering as markdown.
        case structured
    }

    /// Which rendering the user wants, overriding the detected layout.
    enum OutputMode: String, CaseIterable, Identifiable {
        case automatic, markdown, plainText

        var id: Self { self }

        var label: String {
            switch self {
            case .automatic: "Auto"
            case .markdown: "Markdown"
            case .plainText: "Plain Text"
            }
        }
    }

    struct Barcode: Identifiable, Hashable {
        let id: UUID
        let symbology: BarcodeSymbology
        let payload: String

        /// Human-readable symbology name for display, e.g. "QR", "Data Matrix".
        var symbologyLabel: String {
            switch symbology {
            case .qr, .microQR: "QR"
            case .aztec: "Aztec"
            case .dataMatrix: "Data Matrix"
            case .pdf417, .microPDF417: "PDF417"
            default: String(describing: symbology).uppercased()
            }
        }
    }

    func extract(from image: CGImage) async throws -> Extraction {
        // Photographed documents rarely fill the frame; cropping to the page
        // keeps whatever else is in shot out of the transcript.
        let canvas = (try? await Self.rectifiedDocument(in: image)) ?? image
        guard let document = try await Self.documentRequest().perform(on: canvas).first?.document else {
            return Extraction(markdown: "", plainText: "", barcodes: [], layout: .simple)
        }

        let nodes = Self.nodes(in: document)
        return Extraction(
            markdown: MarkdownRenderer.render(nodes),
            plainText: Self.transcript(of: document),
            barcodes: Self.barcodes(from: document.barcodes),
            layout: Self.layout(of: document)
        )
    }

    private static func documentRequest() -> RecognizeDocumentsRequest {
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.automaticallyDetectLanguage = true
        // Barcode detection is off by default; without this there are no QR codes.
        request.barcodeDetectionOptions.enabled = true
        return request
    }

    /// Crops and de-skews the document in the image, or nil when there isn't one.
    private static func rectifiedDocument(in image: CGImage) async throws -> CGImage? {
        guard let observation = try await DetectDocumentSegmentationRequest().perform(on: image) else { return nil }

        let size = CGSize(width: image.width, height: image.height)
        let correction = CIFilter.perspectiveCorrection()
        correction.inputImage = CIImage(cgImage: image)
        correction.topLeft = observation.topLeft.toImageCoordinates(size)
        correction.topRight = observation.topRight.toImageCoordinates(size)
        correction.bottomRight = observation.bottomRight.toImageCoordinates(size)
        correction.bottomLeft = observation.bottomLeft.toImageCoordinates(size)
        correction.crop = true

        guard let output = correction.outputImage else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }

    // MARK: - Container to nodes

    /// Internal so tests can replay a recorded observation without Vision.
    static func nodes(in container: DocumentObservation.Container) -> [DocumentNode] {
        let footnotes = container.lists.flatMap { $0.items.map(\.itemString) }
        // A footnote's paragraph still carries its "1." marker, so compare on
        // the text either side of it rather than on a prefix.
        let footnoteKeys = footnotes.map(Self.comparisonKey)
        let blocks = textBlocks(in: container)
            .filter { block in
                let key = Self.comparisonKey(block.text)
                return !key.isEmpty && !footnoteKeys.contains { $0.hasPrefix(key) || key.hasPrefix($0) }
            }

        var nodes: [DocumentNode] = []
        if let bands = LayoutInference.columnBands(in: blocks) {
            nodes = columnLayoutNodes(blocks: blocks, bands: bands)
        } else {
            nodes = flowNodes(blocks: blocks)
        }

        for table in container.tables {
            let cells = table.rows.map { $0.map { $0.content.text.transcript } }
            guard let header = cells.first else { continue }
            nodes.append(.table(header: header, rows: Array(cells.dropFirst())))
        }

        for barcode in barcodes(from: container.barcodes) {
            nodes.append(.barcode(symbology: barcode.symbologyLabel, payload: barcode.payload))
        }

        if !footnotes.isEmpty {
            nodes.append(.rule)
            nodes.append(.footnotes(footnotes))
        }

        return nodes
    }

    /// Content above the columns, then the inferred table, then content below.
    private static func columnLayoutNodes(blocks: [TextBlock], bands: [[TextBlock]]) -> [DocumentNode] {
        let table = LayoutInference.table(pairing: bands)
        guard let header = table.rows.first else { return flowNodes(blocks: blocks) }

        let inTable = Set(bands.flatMap { $0 }.map(\.id)).subtracting(table.excluded.map(\.id))
        let top = blocks.filter { inTable.contains($0.id) }.map(\.frame.maxY).max() ?? 1
        let outside = blocks.filter { !inTable.contains($0.id) }

        var nodes = flowNodes(blocks: outside.filter { $0.frame.midY > top })
        nodes.append(.table(header: header, rows: Array(table.rows.dropFirst())))
        // Anything below the top of the table is trailing matter — captions,
        // a promotion period, small print — never a heading.
        nodes += outside.filter { $0.frame.midY <= top }
            .sorted { $0.id < $1.id }
            .map { .paragraph($0.text) }
        return nodes
    }

    /// Blocks in Vision's reading order, promoting outsized lines to headings.
    ///
    /// The recognizer groups related blocks — a banner and its translation, a
    /// badge in the corner — better than sorting on vertical position does,
    /// which interleaves anything typeset side by side.
    private static func flowNodes(blocks: [TextBlock]) -> [DocumentNode] {
        let heights = blocks.map(\.frame.height).sorted()
        let median = heights.isEmpty ? 1 : heights[heights.count / 2]

        var sawHeading = false
        return blocks.sorted { $0.id < $1.id }.map { block in
            guard block.frame.height >= median * 1.35 else { return .paragraph(block.text) }
            defer { sawHeading = true }
            return .heading(level: sawHeading ? 2 : 1, text: block.text)
        }
    }

    /// Leading list markers and punctuation differ between a list item and the
    /// paragraph it came from; strip them before comparing.
    private static func comparisonKey(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .drop { $0.isNumber || $0 == "." || $0 == ")" || $0 == "•" || $0 == "*" || $0 == " " }
            .prefix(40)
            .lowercased()
    }

    private static func textBlocks(in container: DocumentObservation.Container) -> [TextBlock] {
        container.paragraphs.enumerated().map { index, paragraph in
            let frame = boundingBox(of: paragraph)
            return TextBlock(
                id: index,
                text: paragraph.transcript,
                frame: frame,
                isCentered: paragraph.textAlignment == .center || abs(frame.midX - 0.5) < 0.05
            )
        }
    }

    private static func transcript(of container: DocumentObservation.Container) -> String {
        container.text.transcript
    }

    /// Structure worth rendering as markdown, using signals that separated
    /// cleanly in testing: simple images land at 1-6 paragraphs with uniform
    /// line heights, documents at 30+ with headings 2x the body height.
    static func layout(of container: DocumentObservation.Container) -> Layout {
        if !container.tables.isEmpty { return .structured }

        let paragraphs = container.paragraphs.count
        if !container.lists.isEmpty, paragraphs >= 8 { return .structured }
        if paragraphs >= 8, LayoutInference.columnBands(in: textBlocks(in: container)) != nil { return .structured }

        let heights = container.paragraphs.map(height(of:)).sorted()
        guard let tallest = heights.last, let median = heights[safe: heights.count / 2], median > 0 else {
            return .simple
        }
        return paragraphs >= 12 && tallest / median >= 1.6 ? .structured : .simple
    }

    private static func barcodes(from observations: [BarcodeObservation]) -> [Barcode] {
        var seenPayloads: Set<String> = []
        return observations.compactMap { observation in
            guard let payload = observation.payloadString, !payload.isEmpty,
                  seenPayloads.insert(payload).inserted else { return nil }
            return Barcode(id: observation.uuid, symbology: observation.symbology, payload: payload)
        }
    }

    private static func boundingBox(of text: DocumentObservation.Container.Text) -> CGRect {
        text.boundingRegion.normalizedPath.boundingBox
    }

    private static func midY(of text: DocumentObservation.Container.Text) -> CGFloat {
        boundingBox(of: text).midY
    }

    private static func height(of text: DocumentObservation.Container.Text) -> CGFloat {
        boundingBox(of: text).height
    }

    // MARK: - Warm up

    /// Runs the pipeline once on a small generated image so the system compiles
    /// and caches its models before the first real extraction.
    ///
    /// The compile is per request configuration, so this deliberately uses the
    /// same request the real extraction does — a bare request warms nothing.
    func warmUp() async {
        guard let image = Self.makeWarmUpImage() else { return }
        _ = try? await Self.documentRequest().perform(on: image)
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

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
