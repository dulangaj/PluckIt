//
//  ZoomableImageView.swift
//  PluckIt
//
//  Created by Dulanga Jayawardena on 05/05/2026.
//

import SwiftUI

struct ZoomableImageView: NSViewRepresentable {
    let image: NSImage

    func makeNSView(context: Context) -> FittingScrollView {
        let scrollView = FittingScrollView()
        scrollView.contentView = CenteringClipView()
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.1
        scrollView.maxMagnification = 20.0
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.image = image
        imageView.setFrameSize(image.size)

        scrollView.documentView = imageView
        scrollView.needsInitialFit = true
        return scrollView
    }

    func updateNSView(_ scrollView: FittingScrollView, context: Context) {
        guard let imageView = scrollView.documentView as? NSImageView else { return }
        if imageView.image !== image {
            imageView.image = image
            imageView.setFrameSize(image.size)
            scrollView.needsInitialFit = true
            scrollView.needsLayout = true
        }
    }
}

/// Scroll view that fits its document inside the visible area the first time
/// it gets a non-zero size after a new image is set. NSScrollView's
/// `magnify(toFit:)` requires real bounds, which aren't available until
/// after SwiftUI's layout pass — hence deferring to `layout()`.
final class FittingScrollView: NSScrollView {
    var needsInitialFit = false

    override func layout() {
        super.layout()
        guard needsInitialFit,
              bounds.width > 0,
              bounds.height > 0,
              let documentView,
              documentView.bounds.width > 0,
              documentView.bounds.height > 0 else { return }
        magnify(toFit: documentView.bounds)
        needsInitialFit = false
    }
}

/// Keeps the document centered inside the clip view whenever the visible
/// area is larger than the document — i.e. after a fit-to-window or any
/// time the magnified content is smaller than the scroll view.
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return rect }
        let docFrame = documentView.frame
        if rect.width > docFrame.width {
            rect.origin.x = (docFrame.width - rect.width) / 2
        }
        if rect.height > docFrame.height {
            rect.origin.y = (docFrame.height - rect.height) / 2
        }
        return rect
    }
}
