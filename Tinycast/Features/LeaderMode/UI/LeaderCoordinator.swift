import AppKit
import Carbon.HIToolbox

@MainActor
@Observable
final class LeaderCoordinator: HealthCheckable {
    struct Action: Identifiable {
        let action: HotKeyAction
        let name: String
        var id: String { action.defaultsKey }
    }

    private let settings: AppSettings
    private let hotKeys: HotKeyManager
    private let appIndex: AppIndex
    private let ticker: HealthTicker
    @ObservationIgnored private lazy var tap = LeaderKeyTap { [weak self] update in
        Task { @MainActor in self?.receive(update) }
    }
    private let group: LeaderGroupController
    private(set) var nodes: [LeaderNode] = []
    private(set) var needsAccessibility = false
    private(set) var problem: String?
    var onProblem: ((String) -> Void)?
    var canCapture: () -> Bool = { true }
    private var observers: [NotificationToken] = []
    private var pauseReasons: Set<String> = []
    private var sessionActive: Bool { pauseReasons.isEmpty }
    private var displayedGroup: String?
    private var configurationValid = true

    init(settings: AppSettings, hotKeys: HotKeyManager, appIndex: AppIndex, ticker: HealthTicker) {
        self.settings = settings
        self.hotKeys = hotKeys
        self.appIndex = appIndex
        self.ticker = ticker
        group = LeaderGroupController(settings: settings)
    }

    var trigger: ModifierKey { ModifierKey(rawValue: settings.leaderTrigger) ?? .rightCommand }
    static var triggers: [ModifierKey] { ModifierKey.allCases.filter { $0 != .globe } }

    var actions: [Action] {
        var result: [String: Action] = [:]
        for entry in appIndex.apps {
            let action = entry.kind == .extensionCommand
                ? HotKeyAction.extensionCommand(entryID: entry.id) : entry.hotKeyAction
            guard let action, action != .dictation else { continue }
            result[action.defaultsKey] = Action(action: action, name: entry.name)
        }
        for id in CommandID.allCases {
            guard let action = id.hotKeyAction, action != .dictation else { continue }
            result[action.defaultsKey] = Action(action: action, name: id.name)
        }
        return result.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        for (name, reason, paused) in [
            (NSWorkspace.willSleepNotification, "sleep", true),
            (NSWorkspace.didWakeNotification, "sleep", false),
            (NSWorkspace.sessionDidResignActiveNotification, "session", true),
            (NSWorkspace.sessionDidBecomeActiveNotification, "session", false)
        ] {
            observers.append(NotificationToken(center.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.setPaused(paused, reason: reason) }
            }, center: center))
        }
        let distributed = DistributedNotificationCenter.default()
        for name in ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked"] {
            observers.append(NotificationToken(distributed.addObserver(
                forName: Notification.Name(name), object: nil, queue: .main
            ) { [weak self] notification in
                let paused = notification.name.rawValue == "com.apple.screenIsLocked"
                Task { @MainActor in self?.setPaused(paused, reason: "lock") }
            }, center: distributed))
        }
        observers.append(NotificationToken(distributed.addObserver(
            forName: Notification.Name("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged"),
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.apply() }
        }, center: distributed))
        observers.append(NotificationToken(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.cancel() }
        }, center: center))
        apply()
    }

    func apply() {
        cancel()
        configurationValid = false
        guard let decoded = LeaderNode.decode(settings.leaderBindings) else {
            problem = String(localized: "Invalid leader configuration")
            needsAccessibility = false
            tap.stop()
            ticker.unsubscribe(self)
            return
        }
        configurationValid = true
        nodes = decoded
        tap.session.configure(
            nodes: nodes, trigger: trigger,
            characters: settings.leaderEnabled ? ASCIIKeyboardLayout.baseCharacters(for: 0..<128) : [:])
        healthCheck()
        if settings.leaderEnabled { ticker.subscribe(self) } else { ticker.unsubscribe(self) }
    }

    func setEnabled(_ enabled: Bool) {
        settings.leaderEnabled = enabled
        if enabled { Permissions.ensureAccessibility() }
        apply()
    }

    func cancel() {
        tap.session.cancel()
        displayedGroup = nil
        group.show(nil)
    }

    func stop() {
        cancel()
        tap.stop()
        observers = []
        ticker.unsubscribe(self)
    }

    func healthCheck() {
        guard configurationValid else { return }
        problem = conflict()
        let enabled = settings.leaderEnabled && sessionActive && problem == nil && canCapture()
        needsAccessibility = enabled && !Permissions.isAccessibilityTrusted()
        guard enabled, !needsAccessibility, !IsSecureEventInputEnabled() else {
            cancel()
            tap.stop()
            return
        }
        tap.start()
        needsAccessibility = !tap.isInstalled
        tap.checkHealth()
    }

    private func conflict() -> String? {
        guard settings.leaderEnabled else { return nil }
        guard Self.triggers.contains(where: { $0.rawValue == settings.leaderTrigger }) else {
            return String(localized: "Invalid leader configuration")
        }
        if settings.hyperKey.rawValue == trigger.rawValue
            || (settings.hyperKey == .capsLock && settings.hyperKeySecureInputCompatibility
                && trigger == .rightControl)
        {
            return String(localized: "This modifier is already used by another shortcut.")
        }
        if hotKeys.modifierConflict(for: trigger) != nil {
            return String(localized: "This modifier is already used by another shortcut.")
        }
        return nil
    }

    private func setPaused(_ paused: Bool, reason: String) {
        if paused { pauseReasons.insert(reason) } else { pauseReasons.remove(reason) }
        apply()
    }

    private func receive(_ update: LeaderKeyTap.Update) {
        guard tap.session.isCurrent(update) else { return }
        let name = tap.session.groupName(for: update)
        if displayedGroup != name {
            displayedGroup = name
            group.show(name)
        }
        guard settings.leaderEnabled, sessionActive, canCapture(), conflict() == nil,
            !IsSecureEventInputEnabled()
        else { return }
        if let id = update.actionID { run(id) }
    }

    private func run(_ id: String) {
        if let action = actions.first(where: { $0.id == id })?.action {
            hotKeys.perform(action)
        } else if id.hasPrefix("hotkey.app.") {
            let bundleID = String(id.dropFirst("hotkey.app.".count))
            guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil else {
                onProblem?(String(localized: "Leader action is unavailable"))
                return
            }
            hotKeys.perform(.app(bundleID: bundleID))
        } else {
            onProblem?(String(localized: "Leader action is unavailable"))
        }
    }

    func save(_ node: LeaderNode, replacing key: String?, in path: [String]) -> Bool {
        var root = nodes
        guard var siblings = LeaderNode.nodes(in: path, root: root),
            !siblings.contains(where: { $0.key == node.key && $0.key != key })
        else { return false }
        if let key, let index = siblings.firstIndex(where: { $0.key == key }) {
            siblings[index] = node
        } else {
            siblings.append(node)
        }
        guard LeaderNode.replace(in: path[...], root: &root, with: siblings), LeaderNode.validate(root)
        else { return false }
        return persist(root)
    }

    func move(_ source: [String], to destination: LeaderTree.Destination) -> Bool {
        guard let root = LeaderTree.moving(source, to: destination, in: nodes) else { return false }
        return persist(root)
    }

    func remove(_ key: String, in path: [String]) {
        var root = nodes
        guard let siblings = LeaderNode.nodes(in: path, root: root),
            LeaderNode.replace(in: path[...], root: &root, with: siblings.filter { $0.key != key })
        else { return }
        _ = persist(root)
    }

    private func persist(_ root: [LeaderNode]) -> Bool {
        do {
            settings.leaderBindings = try LeaderNode.encode(root)
            apply()
            return true
        } catch {
            onProblem?(String(localized: "Couldn’t save leader bindings"))
            return false
        }
    }
}
