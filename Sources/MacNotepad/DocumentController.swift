import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers
import WebKit

struct EditorDocumentState: Identifiable, Equatable {
    let id: UUID
    var fileURL: URL?
    var text: String
    var savedText: String
    var selectedRange: NSRange

    init(
        id: UUID = UUID(),
        fileURL: URL? = nil,
        text: String = "",
        savedText: String? = nil,
        selectedRange: NSRange = NSRange(location: 0, length: 0)
    ) {
        self.id = id
        self.fileURL = fileURL
        self.text = text
        self.savedText = savedText ?? text
        self.selectedRange = selectedRange
    }

    var isDirty: Bool {
        text != savedText
    }

    var displayTitle: String {
        fileURL?.lastPathComponent ?? "Untitled"
    }
}

struct PersistedRange: Codable, Equatable {
    var location: Int
    var length: Int

    init(_ range: NSRange) {
        location = range.location
        length = range.length
    }

    var nsRange: NSRange {
        NSRange(location: location, length: length)
    }
}

struct PersistedDocumentState: Codable, Equatable {
    var id: UUID
    var fileURL: URL?
    var text: String
    var savedText: String
    var selectedRange: PersistedRange
}

struct PersistedWorkspaceState: Codable, Equatable, Identifiable {
    var id: UUID
    var documents: [PersistedDocumentState]
    var selectedDocumentID: UUID
    var wordWrap: Bool
    var fontName: String
    var fontSize: Double
    var showsStatusBar: Bool
}

struct PersistedSessionState: Codable, Equatable {
    var workspaces: [PersistedWorkspaceState]
}

@MainActor
final class WorkspaceController: ObservableObject {
    let workspaceID: UUID
    @Published private(set) var documents: [EditorDocumentState]
    @Published private(set) var selectedDocumentID: UUID
    @Published var wordWrap = false
    @Published var fontName = "Menlo"
    @Published var fontSize: CGFloat = 14
    @Published var showsStatusBar = true
    @Published var searchText = ""
    @Published var replaceText = ""
    @Published private(set) var currentLine = 1
    @Published private(set) var currentColumn = 1
    @Published private(set) var windowTitle = "Untitled - Notepad"

    weak var webView: WKWebView?
    weak var window: NSWindow?
    private var windowDelegate: WindowDelegate?

    init(snapshot: PersistedWorkspaceState? = nil) {
        workspaceID = snapshot?.id ?? UUID()

        if let snapshot, !snapshot.documents.isEmpty {
            documents = snapshot.documents.map {
                EditorDocumentState(
                    id: $0.id,
                    fileURL: $0.fileURL,
                    text: $0.text,
                    savedText: $0.savedText,
                    selectedRange: $0.selectedRange.nsRange
                )
            }
            selectedDocumentID = snapshot.selectedDocumentID
            wordWrap = snapshot.wordWrap
            fontName = snapshot.fontName
            fontSize = snapshot.fontSize
            showsStatusBar = snapshot.showsStatusBar
        } else {
            let initialDocument = EditorDocumentState()
            documents = [initialDocument]
            selectedDocumentID = initialDocument.id
        }

        WorkspaceRegistry.shared.register(self)
        updateCursorStatus(for: currentDocument.selectedRange, in: currentDocument.text)
        updateWindowAppearance()
    }

    var canSave: Bool {
        currentDocument.fileURL != nil || currentDocument.isDirty || !currentDocument.text.isEmpty
    }

    var canCloseTab: Bool {
        documents.count > 1
    }

    var editorFont: NSFont {
        NSFont(name: fontName, size: fontSize) ?? .monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    var availableFonts: [String] {
        [
            "Menlo",
            "SF Mono",
            "Helvetica",
            "Avenir Next",
            "Courier",
            "Times New Roman"
        ]
    }

    var selectedDocument: EditorDocumentState {
        currentDocument
    }

    var sessionSnapshot: PersistedWorkspaceState {
        snapshotForPersistence()
    }

    var currentFilePath: String {
        currentDocument.fileURL?.path ?? "Unsaved document"
    }

    private var selectedIndex: Int {
        documents.firstIndex(where: { $0.id == selectedDocumentID }) ?? 0
    }

    private var currentDocument: EditorDocumentState {
        get { documents[selectedIndex] }
        set { documents[selectedIndex] = newValue }
    }

    func attachWindow(_ window: NSWindow) {
        self.window = window

        if windowDelegate == nil || window.delegate !== windowDelegate {
            let delegate = WindowDelegate(workspace: self)
            windowDelegate = delegate
            window.delegate = delegate
        }

        updateWindowAppearance()
    }

    func attach(webView: WKWebView) {
        self.webView = webView
    }

    func newTab() {
        let document = EditorDocumentState()
        documents.append(document)
        selectedDocumentID = document.id
        updateCursorStatus(for: document.selectedRange, in: document.text)
        updateWindowAppearance()
        persistSessionState()
    }

    func selectDocument(_ id: UUID) {
        guard documents.contains(where: { $0.id == id }) else { return }
        selectedDocumentID = id
        updateCursorStatus(for: currentDocument.selectedRange, in: currentDocument.text)
        updateWindowAppearance()
    }

    func closeCurrentTab() {
        closeDocument(id: selectedDocumentID)
    }

    func closeDocument(id: UUID) {
        guard let index = documents.firstIndex(where: { $0.id == id }) else { return }
        guard confirmTabClose(at: index) else { return }

        if documents.count == 1 {
            documents[index] = EditorDocumentState()
            selectedDocumentID = documents[index].id
            updateCursorStatus(for: currentDocument.selectedRange, in: currentDocument.text)
            updateWindowAppearance()
            persistSessionState()
            return
        }

        documents.remove(at: index)

        let nextIndex = min(index, documents.count - 1)
        selectedDocumentID = documents[nextIndex].id
        updateCursorStatus(for: currentDocument.selectedRange, in: currentDocument.text)
        updateWindowAppearance()
        persistSessionState()
    }

    func updateText(_ newText: String) {
        var document = currentDocument
        document.text = newText
        currentDocument = document
        updateCursorStatus(for: document.selectedRange, in: document.text)
        updateWindowAppearance()
        persistSessionState()
    }

    func openDocument() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .utf8PlainText]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK else { return }

        for url in panel.urls {
            openDocument(at: url)
        }
    }

    func openDocument(at url: URL) {
        do {
            let contents = try String(contentsOf: url, encoding: .utf8)
            let document = EditorDocumentState(fileURL: url, text: contents, savedText: contents)

            if shouldReuseInitialEmptyDocument {
                documents[0] = document
                selectedDocumentID = document.id
            } else {
                documents.append(document)
                selectedDocumentID = document.id
            }

            updateCursorStatus(for: document.selectedRange, in: document.text)
            updateWindowAppearance()
        } catch {
            showError("Couldn't open the file.")
        }
        persistSessionState()
    }

    func save() {
        if let url = currentDocument.fileURL {
            writeCurrentDocument(to: url)
        } else {
            saveAs()
        }
    }

    func saveAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText, .utf8PlainText]
        panel.nameFieldStringValue = currentDocument.fileURL?.lastPathComponent ?? "Untitled.txt"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        writeCurrentDocument(to: url)
    }

    func revertToSaved() {
        guard let fileURL = currentDocument.fileURL else { return }

        do {
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            var document = currentDocument
            document.text = contents
            document.savedText = contents
            document.selectedRange = NSRange(location: 0, length: 0)
            currentDocument = document
            runEditorScript("window.notepad.setSelection(0, 0);")
            updateCursorStatus(for: document.selectedRange, in: document.text)
            updateWindowAppearance()
            persistSessionState()
        } catch {
            showError("Couldn't reload the saved file.")
        }
    }

    func updateSelection(range: NSRange) {
        var document = currentDocument
        let textLength = (document.text as NSString).length
        let clampedLocation = max(0, min(range.location, textLength))
        document.selectedRange = NSRange(
            location: clampedLocation,
            length: min(range.length, textLength - clampedLocation)
        )
        currentDocument = document
        updateCursorStatus(for: document.selectedRange, in: document.text)
        persistSessionState()
    }

    func increaseFontSize() {
        fontSize = min(fontSize + 1, 72)
    }

    func decreaseFontSize() {
        fontSize = max(fontSize - 1, 8)
    }

    func resetFont() {
        fontName = "Menlo"
        fontSize = 14
    }

    func setWordWrap(_ enabled: Bool) {
        wordWrap = enabled
        if enabled {
            showsStatusBar = false
        }
        persistSessionState()
    }

    func undo() {
        runEditorScript("document.execCommand('undo');")
    }

    func redo() {
        runEditorScript("document.execCommand('redo');")
    }

    func cut() {
        runEditorScript("document.execCommand('cut');")
    }

    func copy() {
        runEditorScript("document.execCommand('copy');")
    }

    func paste() {
        runEditorScript("document.execCommand('paste');")
    }

    func deleteSelection() {
        guard currentDocument.selectedRange.length > 0 else { return }
        runEditorScript("window.notepad.deleteSelection();")
    }

    func selectAll() {
        runEditorScript("window.notepad.selectAll();")
    }

    func insertCurrentDateTime() {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        let stamp = Self.escapeForJavaScript(formatter.string(from: Date()))
        runEditorScript("window.notepad.insertText('\(stamp)');")
    }

    func showFind() {
        NotificationCenter.default.post(name: .showFindPanel, object: nil)
    }

    func showReplace() {
        NotificationCenter.default.post(name: .showReplacePanel, object: nil)
    }

    func findNext() {
        guard !searchText.isEmpty else {
            showFind()
            return
        }

        let source = currentDocument.text as NSString
        let start = min(currentDocument.selectedRange.location + currentDocument.selectedRange.length, source.length)
        let forwardRange = NSRange(location: start, length: max(0, source.length - start))
        var match = source.range(of: searchText, options: [], range: forwardRange)

        if match.location == NSNotFound {
            match = source.range(of: searchText, options: [], range: NSRange(location: 0, length: start))
        }

        if match.location != NSNotFound {
            select(range: match)
        } else {
            showError("Cannot find \"\(searchText)\".")
        }
    }

    func findPrevious() {
        guard !searchText.isEmpty else {
            showFind()
            return
        }

        let source = currentDocument.text as NSString
        let start = max(0, currentDocument.selectedRange.location - 1)
        let leadingRange = NSRange(location: 0, length: start + 1)
        var match = source.range(of: searchText, options: .backwards, range: leadingRange)

        if match.location == NSNotFound {
            match = source.range(
                of: searchText,
                options: .backwards,
                range: NSRange(location: currentDocument.selectedRange.location, length: max(0, source.length - currentDocument.selectedRange.location))
            )
        }

        if match.location != NSNotFound {
            select(range: match)
        } else {
            showError("Cannot find \"\(searchText)\".")
        }
    }

    func replaceCurrent() {
        guard !searchText.isEmpty else {
            showReplace()
            return
        }

        let source = currentDocument.text as NSString
        let currentSelection = source.substring(with: currentDocument.selectedRange)

        if currentSelection == searchText {
            var document = currentDocument
            document.text = source.replacingCharacters(in: document.selectedRange, with: replaceText)
            let nextLocation = document.selectedRange.location + (replaceText as NSString).length
            document.selectedRange = NSRange(location: nextLocation, length: 0)
            currentDocument = document
            runEditorScript("window.notepad.setSelection(\(nextLocation), 0);")
            updateCursorStatus(for: document.selectedRange, in: document.text)
            updateWindowAppearance()
            persistSessionState()
        } else {
            findNext()
        }
    }

    func replaceAll() {
        guard !searchText.isEmpty else {
            showReplace()
            return
        }

        var document = currentDocument
        let updatedText = document.text.replacingOccurrences(of: searchText, with: replaceText)
        guard updatedText != document.text else { return }
        document.text = updatedText
        document.selectedRange = NSRange(location: 0, length: 0)
        currentDocument = document
        updateCursorStatus(for: document.selectedRange, in: document.text)
        updateWindowAppearance()
        persistSessionState()
    }

    func canGoToLine(_ lineNumber: Int) -> Bool {
        lineNumber >= 1 && lineNumber <= lineCount
    }

    func goToLine(_ lineNumber: Int) {
        guard canGoToLine(lineNumber) else {
            showError("Line number must be between 1 and \(lineCount).")
            return
        }

        let source = currentDocument.text as NSString
        var location = 0
        var current = 1

        while current < lineNumber && location < source.length {
            let range = source.lineRange(for: NSRange(location: location, length: 0))
            location = NSMaxRange(range)
            current += 1
        }

        select(range: NSRange(location: location, length: 0))
    }

    var lineCount: Int {
        max(currentDocument.text.components(separatedBy: "\n").count, 1)
    }

    func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Notepad"
        alert.informativeText = "A simple plain-text editor for macOS inspired by Microsoft Windows Notepad."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func confirmWindowClose(_ sender: NSWindow) -> Bool {
        attachWindow(sender)
        AppSessionController.shared.archiveWorkspace(snapshotForPersistence())
        persistSessionState()
        return true
    }

    func confirmAppTermination() -> NSApplication.TerminateReply {
        AppSessionController.shared.saveSession()
        return .terminateNow
    }

    private var shouldReuseInitialEmptyDocument: Bool {
        documents.count == 1 &&
        currentDocument.fileURL == nil &&
        currentDocument.text.isEmpty &&
        !currentDocument.isDirty
    }

    private func updateCursorStatus(for range: NSRange, in text: String) {
        let textLength = (text as NSString).length
        let clampedLocation = max(0, min(range.location, textLength))
        let prefix = (text as NSString).substring(to: clampedLocation)
        let parts = prefix.components(separatedBy: "\n")
        currentLine = max(parts.count, 1)
        currentColumn = ((parts.last ?? "") as NSString).length + 1
    }

    private func select(range: NSRange) {
        runEditorScript("window.notepad.setSelection(\(range.location), \(range.length));")
        updateSelection(range: range)
    }

    private func writeCurrentDocument(to url: URL) {
        do {
            var document = currentDocument
            try document.text.write(to: url, atomically: true, encoding: .utf8)
            document.fileURL = url
            document.savedText = document.text
            currentDocument = document
            updateWindowAppearance()
            persistSessionState()
        } catch {
            showError("Couldn't save the file.")
        }
    }

    private func confirmTabClose(at index: Int) -> Bool {
        let document = documents[index]
        guard document.isDirty else { return true }

        selectedDocumentID = document.id
        updateCursorStatus(for: document.selectedRange, in: document.text)
        updateWindowAppearance()

        let alert = NSAlert()
        alert.messageText = "Do you want to save changes to \(document.displayTitle)?"
        alert.informativeText = "Your changes will be lost if you close this tab without saving."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Don't Save")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            save()
            return !currentDocument.isDirty
        case .alertThirdButtonReturn:
            return true
        default:
            return false
        }
    }

    private func runEditorScript(_ script: String) {
        webView?.evaluateJavaScript(script)
    }

    private func updateWindowAppearance() {
        let title = "\(currentDocument.displayTitle) - Notepad"
        windowTitle = currentDocument.isDirty ? "\(title) *" : title
        window?.title = title
        window?.representedURL = currentDocument.fileURL
        window?.isDocumentEdited = currentDocument.isDirty
        window?.titleVisibility = .visible
        window?.titlebarAppearsTransparent = false
    }

    private func persistSessionState() {
        AppSessionController.shared.saveSession()
    }

    private func snapshotForPersistence() -> PersistedWorkspaceState {
        PersistedWorkspaceState(
            id: workspaceID,
            documents: documents.map(persistedDocument),
            selectedDocumentID: selectedDocumentID,
            wordWrap: wordWrap,
            fontName: fontName,
            fontSize: fontSize,
            showsStatusBar: showsStatusBar
        )
    }

    private func persistedDocument(from document: EditorDocumentState) -> PersistedDocumentState {
        PersistedDocumentState(
            id: document.id,
            fileURL: document.fileURL,
            text: document.text,
            savedText: document.savedText,
            selectedRange: PersistedRange(document.selectedRange)
        )
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = "Please try again."
        alert.alertStyle = .warning
        alert.runModal()
    }

    private static func escapeForJavaScript(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }
}
