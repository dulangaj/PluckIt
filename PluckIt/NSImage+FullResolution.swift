//
//  NSImage+FullResolution.swift
//  PluckIt
//

import AppKit

extension NSImage {
    /// A `CGImage` at the source's true pixel dimensions.
    ///
    /// `NSImage.cgImage(forProposedRect:context:hints:)` renders at the image's
    /// *point* size, so a Retina (2×) screenshot or photo would be handed to
    /// Vision at half its real resolution — directly hurting recognition of
    /// small text. This instead uses the highest-resolution representation,
    /// rendering into a full-pixel bitmap when no representation matches.
    var fullResolutionCGImage: CGImage? {
        let pixelWidth = representations.map(\.pixelsWide).max() ?? 0
        let pixelHeight = representations.map(\.pixelsHigh).max() ?? 0

        guard pixelWidth > 0, pixelHeight > 0 else {
            // No representation reports pixel dimensions (e.g. a pure vector);
            // fall back to the point-size render.
            return cgImage(forProposedRect: nil, context: nil, hints: nil)
        }

        // Prefer a bitmap representation that already holds the full pixels.
        for case let bitmap as NSBitmapImageRep in representations
        where bitmap.pixelsWide == pixelWidth && bitmap.pixelsHigh == pixelHeight {
            if let cgImage = bitmap.cgImage { return cgImage }
        }

        // Otherwise render the image into a bitmap at full pixel resolution.
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            return cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        bitmap.size = NSSize(width: pixelWidth, height: pixelHeight)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        draw(
            in: NSRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight),
            from: .zero,
            operation: .copy,
            fraction: 1.0
        )
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        return bitmap.cgImage
    }
}
