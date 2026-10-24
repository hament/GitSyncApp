import AppKit

@MainActor
final class ProjectWindows {
    static let shared = ProjectWindows()

    private final class WindowReference {
        weak var window: NSWindow?

        init(_ window: NSWindow) {
            self.window = window
        }
    }

    private var projects: [String: UUID] = [:]
    private var windows: [UUID: WindowReference] = [:]
    private var pendingActivation: UUID?

    func claim(_ path: String, owner: UUID) -> UUID? {
        let key = URL(fileURLWithPath: path, isDirectory: true)
            .resolvingSymlinksInPath().standardizedFileURL.path
        if let existing = projects[key], existing != owner {
            return existing
        }
        projects = projects.filter { $0.value != owner }
        projects[key] = owner
        return nil
    }

    func register(_ window: NSWindow, owner: UUID) {
        windows[owner] = WindowReference(window)
        if pendingActivation == owner {
            activate(owner)
        }
    }

    func activate(_ owner: UUID) {
        guard let window = windows[owner]?.window else {
            pendingActivation = owner
            return
        }
        pendingActivation = nil
        NSApplication.shared.activate(ignoringOtherApps: true)
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
    }

    func release(_ owner: UUID) {
        projects = projects.filter { $0.value != owner }
        windows.removeValue(forKey: owner)
        if pendingActivation == owner { pendingActivation = nil }
    }
}
