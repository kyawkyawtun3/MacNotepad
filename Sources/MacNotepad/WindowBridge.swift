import AppKit
import SwiftUI

@MainActor
final class AppSessionController: ObservableObject {
    static let shared = AppSessionController()

    private let sessionStore = SessionStore()
    private(set) var pendingWorkspaces: [PersistedWorkspaceState]
    private var archivedWorkspaces: [PersistedWorkspaceState]
    private var bootstrapped = false

    private init() {
        let restored = sessionStore.load().workspaces
        pendingWorkspaces = restored
        archivedWorkspaces = []
    }

    func consumeNextWorkspace() -> PersistedWorkspaceState? {
        guard !pendingWorkspaces.isEmpty else { return nil }
        return pendingWorkspaces.removeFirst()
    }

    func bootstrapRemainingWindows(openWindow: (String) -> Void, windowID: String) {
        guard !bootstrapped else { return }
        bootstrapped = true

        let extraCount = pendingWorkspaces.count
        guard extraCount > 0 else { return }

        for _ in 0..<extraCount {
            openWindow(windowID)
        }
    }

    func archiveWorkspace(_ snapshot: PersistedWorkspaceState) {
        archivedWorkspaces.removeAll { $0.id == snapshot.id }
        archivedWorkspaces.append(snapshot)
        saveSession()
    }

    func saveSession() {
        let live = WorkspaceRegistry.shared.workspaces.map { $0.sessionSnapshot }
        let archived = archivedWorkspaces.filter { archived in
            !live.contains(where: { $0.id == archived.id })
        }
        sessionStore.save(PersistedSessionState(workspaces: live + archived))
    }
}

struct SessionStore {
    private let url: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let directory = appSupport.appendingPathComponent("MacNotepad", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("session.json")
    }

    func load() -> PersistedSessionState {
        guard
            let data = try? Data(contentsOf: url),
            let session = try? JSONDecoder().decode(PersistedSessionState.self, from: data)
        else {
            return PersistedSessionState(workspaces: [])
        }
        return session
    }

    func save(_ session: PersistedSessionState) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

@MainActor
final class WorkspaceRegistry {
    static let shared = WorkspaceRegistry()

    private struct Entry {
        weak var workspace: WorkspaceController?
    }

    private var entries: [Entry] = []

    func register(_ workspace: WorkspaceController) {
        cleanup()
        entries.append(Entry(workspace: workspace))
    }

    func unregister(_ workspace: WorkspaceController) {
        entries.removeAll { $0.workspace == nil || $0.workspace === workspace }
    }

    var workspaces: [WorkspaceController] {
        cleanup()
        return entries.compactMap(\.workspace)
    }

    private func cleanup() {
        entries.removeAll { $0.workspace == nil }
    }
}

@MainActor
struct WindowAccessor: NSViewRepresentable {
    @ObservedObject var workspace: WorkspaceController

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            if let window = view.window {
                workspace.attachWindow(window)
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                workspace.attachWindow(window)
            }
        }
    }
}

@MainActor
final class WindowDelegate: NSObject, NSWindowDelegate {
    weak var workspace: WorkspaceController?

    init(workspace: WorkspaceController) {
        self.workspace = workspace
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        workspace?.confirmWindowClose(sender) ?? true
    }
}
