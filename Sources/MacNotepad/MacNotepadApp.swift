import SwiftUI

private let mainWindowID = "main-window"

@main
struct MacNotepadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup(id: mainWindowID) {
            WorkspaceRootView()
                .frame(minWidth: 760, minHeight: 520)
        }
        .commands {
            DocumentCommands(mainWindowID: mainWindowID)
        }
    }
}

struct WorkspaceRootView: View {
    @StateObject private var workspace: WorkspaceController

    init() {
        _workspace = StateObject(
            wrappedValue: WorkspaceController(snapshot: AppSessionController.shared.consumeLaunchWorkspace())
        )
    }

    var body: some View {
        EditorView()
            .environmentObject(workspace)
            .background(WindowAccessor(workspace: workspace))
            .focusedSceneObject(workspace)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        for workspace in WorkspaceRegistry.shared.workspaces {
            _ = workspace.confirmAppTermination()
        }
        return .terminateNow
    }
}

struct DocumentCommands: Commands {
    @FocusedObject private var workspace: WorkspaceController?
    @Environment(\.openWindow) private var openWindow

    let mainWindowID: String

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Tab") {
                workspace?.newTab()
            }
            .keyboardShortcut("n")
            .disabled(workspace == nil)

            Button("New Window") {
                openWindow(id: mainWindowID)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("Open...") {
                workspace?.openDocument()
            }
            .keyboardShortcut("o")
            .disabled(workspace == nil)

            Divider()

            Button("Close Tab") {
                workspace?.closeCurrentTab()
            }
            .keyboardShortcut("w")
            .disabled(workspace == nil)

            Divider()

            Button("Save") {
                workspace?.save()
            }
            .keyboardShortcut("s")
            .disabled(workspace?.canSave != true)

            Button("Save As...") {
                workspace?.saveAs()
            }
            .keyboardShortcut("S", modifiers: [.command, .shift])
            .disabled(workspace == nil)

            Divider()

            Button("Revert to Saved") {
                workspace?.revertToSaved()
            }
            .disabled(workspace?.selectedDocument.fileURL == nil || workspace?.selectedDocument.isDirty != true)
        }

        CommandMenu("Edit") {
            Button("Undo") {
                workspace?.undo()
            }
            .keyboardShortcut("z")

            Button("Redo") {
                workspace?.redo()
            }
            .keyboardShortcut("Z", modifiers: [.command, .shift])

            Divider()

            Button("Cut") {
                workspace?.cut()
            }
            .keyboardShortcut("x")

            Button("Copy") {
                workspace?.copy()
            }
            .keyboardShortcut("c")

            Button("Paste") {
                workspace?.paste()
            }
            .keyboardShortcut("v")

            Button("Delete") {
                workspace?.deleteSelection()
            }

            Divider()

            Button("Find...") {
                workspace?.showFind()
            }
            .keyboardShortcut("f")

            Button("Find Next") {
                workspace?.findNext()
            }
            .keyboardShortcut("g")

            Button("Find Previous") {
                workspace?.findPrevious()
            }
            .keyboardShortcut("G", modifiers: [.command, .shift])

            Button("Replace...") {
                workspace?.showReplace()
            }
            .keyboardShortcut("h")

            Divider()

            Button("Go To...") {
                NotificationCenter.default.post(name: .showGoToLinePanel, object: nil)
            }
            .keyboardShortcut("l", modifiers: .command)
            .disabled(workspace?.wordWrap != false)

            Divider()

            Button("Select All") {
                workspace?.selectAll()
            }
            .keyboardShortcut("a")

            Button("Time/Date") {
                workspace?.insertCurrentDateTime()
            }
        }

        CommandMenu("Format") {
            Toggle(
                "Word Wrap",
                isOn: Binding(
                    get: { workspace?.wordWrap ?? false },
                    set: { workspace?.setWordWrap($0) }
                )
            )
            .disabled(workspace == nil)

            Divider()

            Button("Font...") {
                NotificationCenter.default.post(name: .showFontPanel, object: nil)
            }
            .disabled(workspace == nil)

            Button("Increase Font Size") {
                workspace?.increaseFontSize()
            }
            .keyboardShortcut("+", modifiers: .command)

            Button("Decrease Font Size") {
                workspace?.decreaseFontSize()
            }
            .keyboardShortcut("-", modifiers: .command)

            Button("Reset Font") {
                workspace?.resetFont()
            }
        }

        CommandMenu("View") {
            Toggle("Status Bar", isOn: Binding(
                get: { workspace?.showsStatusBar ?? false },
                set: { workspace?.showsStatusBar = $0 }
            ))
            .disabled(workspace?.wordWrap != false)
        }

        CommandMenu("Help") {
            Button("About Notepad") {
                workspace?.showAbout()
            }
            .disabled(workspace == nil)
        }
    }
}
