//
//  ContentView.swift
//  PluckIt
//
//  Created by Dulanga Jayawardena on 05/05/2026.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var extractedText: String = ""
    @State private var pastedImage: NSImage?
    @State private var isDropTargeted: Bool = false
    /// The most recent extraction, kept so the output mode can be switched
    /// without re-running recognition.
    @State private var extraction: DocumentPipeline.Extraction?
    @State private var outputMode: DocumentPipeline.OutputMode = .automatic
    @State private var isRecognizing: Bool = false
    /// Set once recognition has run long enough that it deserves an explanation
    /// (the system may be compiling recognition models, e.g. after an OS update).
    @State private var isRecognitionTakingLong: Bool = false
    @State private var recognitionTask: Task<Void, Never>?
    /// The unmodified text from the most recent successful extraction, kept so
    /// the user can restore it after applying transformations or edits.
    @State private var originalExtractedText: String?
    @State private var didJustCopy: Bool = false
    @State private var copyFeedbackTask: Task<Void, Never>?
    @Environment(\.undoManager) private var undoManager

    private let pipeline = DocumentPipeline()

    var body: some View {
        VStack {
            Text("Text Extractor")
                .font(.largeTitle)

            Button("Extract Text from Clipboard Image") {
                extractTextFromClipboardImage()
            }
            .disabled(isRecognizing)
            .padding(.bottom, 8)

            HStack(spacing: 12) {
                imagePreview
                textEditor
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            statusBar
        }
        .padding()
        .frame(minWidth: 720, minHeight: 400)
        .contentShape(Rectangle())
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.accentColor, lineWidth: 3)
                .padding(4)
                .opacity(isDropTargeted ? 1 : 0)
                .allowsHitTesting(false)
        )
        .onDrop(of: [.image, .fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
        .task {
            await pipeline.warmUp()
        }
    }

    private var textEditor: some View {
        TextEditor(text: $extractedText)
            .font(.body)
            .border(Color.gray, width: 0.5)
            .disabled(isRecognizing)
            .accessibilityLabel("Extracted text, editable")
            .overlay(alignment: .topLeading) {
                if extractedText.isEmpty, !isRecognizing {
                    Text("Extracted text will appear here")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                if isRecognizing {
                    recognitionProgress
                }
            }
    }

    private var recognitionProgress: some View {
        VStack(spacing: 10) {
            ProgressView("Extracting text…")
            if isRecognitionTakingLong {
                Text("Preparing the text recognition model — the first extraction after a macOS update can take a while.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .task {
            try? await Task.sleep(for: .seconds(4))
            isRecognitionTakingLong = true
        }
        .onDisappear {
            isRecognitionTakingLong = false
        }
    }

    // MARK: - Text actions

    private var cleanUpMenu: some View {
        Menu("Clean Up") {
            ForEach(TextTransformation.allCases) { transformation in
                Button(transformation.label) {
                    apply(transformation)
                }
                .help(transformation.help)
            }
            Divider()
            Button("Restore Original Text") {
                restoreOriginalText()
            }
            .disabled(originalExtractedText == nil || originalExtractedText == extractedText)
        }
        .fixedSize()
        .help("Apply a cleanup to the extracted text")
        .accessibilityLabel("Clean up extracted text")
    }

    private var outputModePicker: some View {
        Picker("Output", selection: $outputMode) {
            ForEach(DocumentPipeline.OutputMode.allCases) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .fixedSize()
        .help("Choose how the extracted document is rendered")
        .accessibilityLabel("Output format")
        .onChange(of: outputMode) { _, newMode in
            guard let extraction else { return }
            replaceExtractedText(with: extraction.text(for: newMode), actionName: "Change Output Format")
        }
    }

    private var copyButton: some View {
        Button {
            copyExtractedTextToClipboard()
        } label: {
            Label(
                didJustCopy ? "Copied" : "Copy",
                systemImage: didJustCopy ? "checkmark" : "doc.on.doc"
            )
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut("c", modifiers: [.command, .shift])
        .help("Copy the extracted text to the clipboard (⇧⌘C)")
        .accessibilityLabel("Copy extracted text")
    }

    private func apply(_ transformation: TextTransformation) {
        replaceExtractedText(with: transformation.apply(to: extractedText), actionName: transformation.label)
    }

    private func restoreOriginalText() {
        guard let originalExtractedText else { return }
        replaceExtractedText(with: originalExtractedText, actionName: "Restore Original Text")
    }

    private func replaceExtractedText(with newText: String, actionName: String) {
        let oldText = extractedText
        guard newText != oldText else { return }
        extractedText = newText
        // registerUndo needs a class target and all view state lives in @State,
        // so the manager stands in as its own target; re-registering inside the
        // closure is what makes the action redoable.
        if let undoManager {
            undoManager.registerUndo(withTarget: undoManager) { _ in
                replaceExtractedText(with: oldText, actionName: actionName)
            }
            undoManager.setActionName(actionName)
        }
    }

    private func copyExtractedTextToClipboard() {
        copyToClipboard(extractedText, announcement: "Copied extracted text")

        didJustCopy = true
        copyFeedbackTask?.cancel()
        copyFeedbackTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            didJustCopy = false
        }
    }

    private func copyToClipboard(_ string: String, announcement: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        AccessibilityNotification.Announcement(announcement).post()
    }

    // MARK: - Status bar

    private var statusBar: some View {
        let stats = TextStats(extractedText)
        return HStack(spacing: 6) {
            HStack(spacing: 6) {
                Text(stats.summary)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .accessibilityElement(children: .combine)
            .accessibilityLabel(stats.accessibleSummary)

            Spacer()

            Group {
                outputModePicker
                cleanUpMenu
                copyButton
            }
            .disabled(extractedText.isEmpty || isRecognizing)
        }
    }

    @ViewBuilder
    private var imagePreview: some View {
        Group {
            if let pastedImage {
                ZoomableImageView(image: pastedImage)
                    .accessibilityLabel("Source image, zoomable and pannable")
            } else {
                Text("Paste from clipboard or drag an image onto the window")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .border(Color.gray, width: 0.5)
    }

    // MARK: - Input sources

    private func extractTextFromClipboardImage() {
        guard let image = NSPasteboard.general.readObjects(forClasses: [NSImage.self], options: [:])?.first as? NSImage else {
            extractedText = "No image found on the clipboard."
            pastedImage = nil
            extraction = nil
            originalExtractedText = nil
            return
        }
        process(image: image)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        if provider.canLoadObject(ofClass: NSImage.self) {
            _ = provider.loadObject(ofClass: NSImage.self) { item, _ in
                guard let image = item as? NSImage else { return }
                Task { @MainActor in
                    self.process(image: image)
                }
            }
            return true
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                guard let data,
                      let url = URL(dataRepresentation: data, relativeTo: nil),
                      let image = NSImage(contentsOf: url) else { return }
                Task { @MainActor in
                    self.process(image: image)
                }
            }
            return true
        }

        return false
    }

    // MARK: - OCR

    private func process(image: NSImage) {
        pastedImage = image
        extraction = nil
        recognitionTask?.cancel()

        guard let cgImage = image.fullResolutionCGImage else {
            extractedText = "Failed to convert the image for text extraction."
            originalExtractedText = nil
            return
        }

        isRecognizing = true
        recognitionTask = Task { @MainActor in
            do {
                let result = try await pipeline.extract(from: cgImage)
                guard !Task.isCancelled else { return }
                extraction = result
                extractedText = result.text(for: outputMode)
                originalExtractedText = extractedText
            } catch {
                guard !Task.isCancelled else { return }
                extractedText = "Failed to perform text recognition: \(error.localizedDescription)"
                originalExtractedText = nil
            }
            isRecognizing = false
        }
    }
}

/// Live counts for a block of extracted text, shown in the status bar.
private struct TextStats {
    let characters: Int
    let words: Int
    let lines: Int

    init(_ text: String) {
        characters = text.count
        words = text.split { $0.isWhitespace || $0.isNewline }.count
        lines = text.isEmpty ? 0 : text.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    /// Compact, glanceable form, e.g. "128 characters · 24 words · 6 lines".
    var summary: String {
        "\(characters.formatted()) \(noun(characters, "character"))"
        + " · \(words.formatted()) \(noun(words, "word"))"
        + " · \(lines.formatted()) \(noun(lines, "line"))"
    }

    /// Spelled-out form for VoiceOver.
    var accessibleSummary: String {
        "\(characters) \(noun(characters, "character")), "
        + "\(words) \(noun(words, "word")), "
        + "\(lines) \(noun(lines, "line"))"
    }

    private func noun(_ count: Int, _ singular: String) -> String {
        count == 1 ? singular : singular + "s"
    }
}

#Preview {
    ContentView()
}
