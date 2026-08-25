# PluckIt

A macOS app that pulls text out of images. Paste from the clipboard or drop an
image on the window; Vision reads the document and the result lands in an
editable text view next to a zoomable preview of the source.

Extraction understands layout, not just lines: headings, paragraphs, lists,
tables, and detected barcodes/QR codes are reconstructed as **Markdown**. The
**Output** picker switches between Markdown, plain text, and *Automatic*, which
picks Markdown only when the page actually has structure.

**Clean Up** applies the usual post-OCR fixes — join wrapped lines, mend
hyphenated line breaks, collapse or strip spaces, drop empty lines — each one
undoable, with the untouched extraction one click away. **Copy** (⇧⌘C) puts the
result on the clipboard.

## Build it yourself

```bash
scripts/build.sh --install
```

That compiles the app, signs it **ad hoc** (`codesign -s -`), and copies it to
`/Applications`. Drop `--install` to leave the app in `./build`.

Requirements: macOS 26 or later (Vision's document recognition) and Xcode (the full app — `xcodebuild` needs it
to compile the asset catalog).

There is no Developer ID and no notarization here, and none is needed: macOS
only gatekeeps apps that arrive quarantined from the internet. An app you built
on your own machine launches normally and keeps working indefinitely, with no
seven-day expiry — that limit applies to free-provisioning *device* profiles on
iOS, not to ad-hoc-signed Mac apps.

Rebuilding produces a new signature, so the app is treated as a fresh binary;
if you have granted it any privacy permissions, macOS may ask again.

## App icon

```bash
scripts/update-app-icon.sh path/to/image.png
```

Regenerates every size in `PluckIt/Assets.xcassets/AppIcon.appiconset` from a
single source image (at least 1024×1024).

## Sandbox

The app runs in the App Sandbox with hardened runtime enabled and read-only
access to user-selected files. It has no network entitlement — OCR happens
on-device.
