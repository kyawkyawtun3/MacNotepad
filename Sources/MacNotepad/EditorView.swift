import AppKit
import SwiftUI
import WebKit

struct EditorView: View {
    @EnvironmentObject private var workspace: WorkspaceController
    @State private var isShowingFontSheet = false
    @State private var isShowingGoToLineSheet = false
    @State private var isShowingFindSheet = false
    @State private var isShowingReplaceSheet = false

    var body: some View {
        VStack(spacing: 0) {
            TabStripView()

            TextEditorContainer(
                text: Binding(
                    get: { workspace.selectedDocument.text },
                    set: { workspace.updateText($0) }
                ),
                isWordWrapEnabled: workspace.wordWrap,
                font: workspace.editorFont,
                onAttach: workspace.attach,
                onSelectionChange: workspace.updateSelection
            )
            .background(Color.white)

            if workspace.showsStatusBar {
                Divider()

                HStack {
                    Spacer()
                    Text("Ln \(workspace.currentLine), Col \(workspace.currentColumn)")
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor))
            }
        }
        .navigationTitle(workspace.windowTitle)
        .sheet(isPresented: $isShowingFontSheet) {
            FontSheet(isPresented: $isShowingFontSheet)
                .environmentObject(workspace)
        }
        .sheet(isPresented: $isShowingGoToLineSheet) {
            GoToLineSheet(isPresented: $isShowingGoToLineSheet)
                .environmentObject(workspace)
        }
        .sheet(isPresented: $isShowingFindSheet) {
            FindSheet(isPresented: $isShowingFindSheet)
                .environmentObject(workspace)
        }
        .sheet(isPresented: $isShowingReplaceSheet) {
            ReplaceSheet(isPresented: $isShowingReplaceSheet)
                .environmentObject(workspace)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showFontPanel)) { _ in
            isShowingFontSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showGoToLinePanel)) { _ in
            isShowingGoToLineSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showFindPanel)) { _ in
            isShowingFindSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showReplacePanel)) { _ in
            isShowingReplaceSheet = true
        }
    }
}

struct TabStripView: View {
    @EnvironmentObject private var workspace: WorkspaceController

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(workspace.documents) { document in
                    TabItemView(document: document)
                }

                Button {
                    workspace.newTab()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

struct TabItemView: View {
    @EnvironmentObject private var workspace: WorkspaceController

    let document: EditorDocumentState

    var body: some View {
        let isActive = document.id == workspace.selectedDocumentID

        HStack(spacing: 8) {
            Text(document.displayTitle)
                .lineLimit(1)

            if document.isDirty {
                Circle()
                    .fill(isActive ? Color.accentColor : Color.secondary)
                    .frame(width: 7, height: 7)
            }

            Button {
                workspace.closeDocument(id: document.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isActive ? Color(nsColor: .controlBackgroundColor) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? Color.secondary.opacity(0.15) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            workspace.selectDocument(document.id)
        }
    }
}

struct TextEditorContainer: NSViewRepresentable {
    @Binding var text: String
    let isWordWrapEnabled: Bool
    let font: NSFont
    let onAttach: (WKWebView) -> Void
    let onSelectionChange: (NSRange) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSelectionChange: onSelectionChange)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.userContentController.add(context.coordinator, name: Coordinator.textChangedHandler)
        configuration.userContentController.add(context.coordinator, name: Coordinator.selectionChangedHandler)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        onAttach(webView)
        webView.loadHTMLString(Self.html, baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.applyStateIfNeeded(
            to: webView,
            text: text,
            font: font,
            isWordWrapEnabled: isWordWrapEnabled
        )
    }

    static let html = """
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <style>
        html, body {
          margin: 0;
          width: 100%;
          height: 100%;
          background: transparent;
          overflow: hidden;
        }
        textarea {
          box-sizing: border-box;
          width: 100%;
          height: 100%;
          margin: 0;
          padding: 12px;
          border: 0;
          outline: none;
          resize: none;
          background: #ffffff;
          color: #111111;
          white-space: pre-wrap;
          overflow-wrap: break-word;
          overflow: auto;
          tab-size: 4;
        }
      </style>
    </head>
    <body>
      <textarea id="editor" spellcheck="false"></textarea>
      <script>
        const editor = document.getElementById("editor");
        let suppressSend = false;

        function sendText() {
          if (suppressSend) return;
          window.webkit.messageHandlers.notepadTextChanged.postMessage(editor.value);
        }

        function sendSelection() {
          window.webkit.messageHandlers.notepadSelectionChanged.postMessage({
            location: editor.selectionStart,
            length: editor.selectionEnd - editor.selectionStart
          });
        }

        function applyConfig(config) {
          editor.style.fontFamily = config.fontFamily;
          editor.style.fontSize = `${config.fontSize}px`;
          editor.style.whiteSpace = config.wordWrap ? "pre-wrap" : "pre";
          editor.style.overflowWrap = config.wordWrap ? "break-word" : "normal";
          editor.wrap = config.wordWrap ? "soft" : "off";
        }

        editor.addEventListener("input", () => {
          sendText();
          sendSelection();
        });
        editor.addEventListener("click", sendSelection);
        editor.addEventListener("keyup", sendSelection);
        editor.addEventListener("select", sendSelection);

        window.notepad = {
          applyState(state) {
            applyConfig(state.preferences);
            if (editor.value !== state.text) {
              const start = editor.selectionStart;
              const end = editor.selectionEnd;
              suppressSend = true;
              editor.value = state.text;
              editor.setSelectionRange(Math.min(start, editor.value.length), Math.min(end, editor.value.length));
              suppressSend = false;
            }
            sendSelection();
          },
          insertText(value) {
            const start = editor.selectionStart;
            const end = editor.selectionEnd;
            editor.setRangeText(value, start, end, "end");
            sendText();
            sendSelection();
            editor.focus();
          },
          deleteSelection() {
            const start = editor.selectionStart;
            const end = editor.selectionEnd;
            editor.setRangeText("", start, end, "start");
            sendText();
            sendSelection();
            editor.focus();
          },
          selectAll() {
            editor.focus();
            editor.select();
            sendSelection();
          },
          setSelection(location, length) {
            editor.focus();
            editor.setSelectionRange(location, location + length);
            sendSelection();
          }
        };

        requestAnimationFrame(() => {
          editor.focus();
          sendSelection();
        });
      </script>
    </body>
    </html>
    """

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let textChangedHandler = "notepadTextChanged"
        static let selectionChangedHandler = "notepadSelectionChanged"

        @Binding private var text: String
        private let onSelectionChange: (NSRange) -> Void
        private var pageLoaded = false
        private var lastRenderedState: RenderState?

        init(text: Binding<String>, onSelectionChange: @escaping (NSRange) -> Void) {
            _text = text
            self.onSelectionChange = onSelectionChange
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            pageLoaded = true
            applyStateIfNeeded(
                to: webView,
                text: text,
                font: .monospacedSystemFont(ofSize: 14, weight: .regular),
                isWordWrapEnabled: false,
                force: true
            )
            webView.evaluateJavaScript("document.getElementById('editor').focus();")
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == Self.textChangedHandler, let value = message.body as? String {
                text = value
                if var state = lastRenderedState {
                    state.text = value
                    lastRenderedState = state
                }
                return
            }

            if message.name == Self.selectionChangedHandler,
               let selection = message.body as? [String: Any],
               let location = selection["location"] as? Int,
               let length = selection["length"] as? Int {
                onSelectionChange(NSRange(location: location, length: length))
            }
        }

        func applyStateIfNeeded(to webView: WKWebView, text: String, font: NSFont, isWordWrapEnabled: Bool, force: Bool = false) {
            guard pageLoaded else { return }

            let state = RenderState(
                text: text,
                preferences: RenderPreferences(
                    fontFamily: font.fontName,
                    fontSize: Double(font.pointSize),
                    wordWrap: isWordWrapEnabled
                )
            )

            guard force || lastRenderedState != state else { return }
            lastRenderedState = state

            guard
                let jsonData = try? JSONEncoder().encode(state),
                let jsonString = String(data: jsonData, encoding: .utf8)
            else { return }

            let escapedJSON = jsonString
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
                .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
                .replacingOccurrences(of: "\u{2029}", with: "\\u2029")

            webView.evaluateJavaScript("window.notepad.applyState(JSON.parse('\(escapedJSON)'));")
        }
    }

    private struct RenderState: Codable, Equatable {
        var text: String
        var preferences: RenderPreferences
    }

    private struct RenderPreferences: Codable, Equatable {
        var fontFamily: String
        var fontSize: Double
        var wordWrap: Bool
    }
}

struct FontSheet: View {
    @EnvironmentObject private var workspace: WorkspaceController
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Font")
                .font(.headline)

            Picker("Typeface", selection: $workspace.fontName) {
                ForEach(workspace.availableFonts, id: \.self) { fontName in
                    Text(fontName).tag(fontName)
                }
            }

            HStack {
                Text("Size")
                Spacer()
                Stepper(value: $workspace.fontSize, in: 8...72, step: 1) {
                    Text("\(Int(workspace.fontSize)) pt")
                        .frame(width: 60, alignment: .trailing)
                }
            }

            HStack {
                Button("Reset") {
                    workspace.resetFont()
                }

                Spacer()

                Button("Done") {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}

struct GoToLineSheet: View {
    @EnvironmentObject private var workspace: WorkspaceController
    @Binding var isPresented: Bool
    @State private var lineNumberText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Go To Line")
                .font(.headline)

            Text("Enter a line number between 1 and \(workspace.lineCount).")
                .foregroundStyle(.secondary)

            TextField("Line number", text: $lineNumberText)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") {
                    isPresented = false
                }

                Spacer()

                Button("Go To") {
                    submit()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    private func submit() {
        guard let lineNumber = Int(lineNumberText) else { return }
        workspace.goToLine(lineNumber)
        if workspace.canGoToLine(lineNumber) {
            isPresented = false
        }
    }
}

struct FindSheet: View {
    @EnvironmentObject private var workspace: WorkspaceController
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Find")
                .font(.headline)

            TextField("Find what", text: $workspace.searchText)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") {
                    isPresented = false
                }

                Spacer()

                Button("Find Next") {
                    workspace.findNext()
                }
                .disabled(workspace.searchText.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}

struct ReplaceSheet: View {
    @EnvironmentObject private var workspace: WorkspaceController
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Replace")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Find what")
                    .foregroundStyle(.secondary)
                TextField("Find what", text: $workspace.searchText)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Replace with")
                    .foregroundStyle(.secondary)
                TextField("Replace with", text: $workspace.replaceText)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Cancel") {
                    isPresented = false
                }

                Spacer()

                Button("Replace") {
                    workspace.replaceCurrent()
                }
                .disabled(workspace.searchText.isEmpty)

                Button("Replace All") {
                    workspace.replaceAll()
                }
                .disabled(workspace.searchText.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}

extension Notification.Name {
    static let showFontPanel = Notification.Name("showFontPanel")
    static let showGoToLinePanel = Notification.Name("showGoToLinePanel")
    static let showFindPanel = Notification.Name("showFindPanel")
    static let showReplacePanel = Notification.Name("showReplacePanel")
}
