import AppKit
import Carbon.HIToolbox
import Synchronization

private func leaderKeyTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let session = Unmanaged<LeaderKeyTap.Session>.fromOpaque(userInfo).takeUnretainedValue()
    return session.handle(type, event: event, secureInput: IsSecureEventInputEnabled())
        ? nil : Unmanaged.passUnretained(event)
}

@MainActor
final class LeaderKeyTap {
    struct Update: Sendable {
        let generation: Int
        let actionID: String?
    }

    let session: Session
    private var port: CFMachPort?
    private var source: CFRunLoopSource?

    init(onUpdate: @escaping @Sendable (Update) -> Void) {
        session = Session(onUpdate: onUpdate)
    }

    var isInstalled: Bool { port != nil }

    isolated deinit { stop() }

    func start() {
        guard port == nil else { return }
        let types: [CGEventType] = [
            .keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown
        ]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: leaderKeyTapCallback,
            userInfo: Unmanaged.passUnretained(session).toOpaque())
        else { return }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            CFMachPortInvalidate(port)
            return
        }
        self.port = port
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
    }

    func stop() {
        session.cancel()
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        source = nil
        port = nil
        session.clearKeys()
    }

    func checkHealth() {
        if let port, !CGEvent.tapIsEnabled(tap: port) {
            session.cancel()
            CGEvent.tapEnable(tap: port, enable: true)
        }
    }

    final class Session: Sendable {
        private struct State {
            var nodes: [LeaderNode] = []
            var trigger = ModifierKey.rightCommand
            var characters: [Int: String] = [:]
            var sequence = LeaderSequence()
            var generation = 0
        }

        private let state = Mutex(State())
        private let onUpdate: @Sendable (Update) -> Void

        init(onUpdate: @escaping @Sendable (Update) -> Void) { self.onUpdate = onUpdate }

        func configure(nodes: [LeaderNode], trigger: ModifierKey, characters: [Int: String]) {
            state.withLock {
                $0.nodes = nodes
                $0.trigger = trigger
                $0.characters = characters.mapValues { $0.lowercased() }
                $0.sequence.cancel()
                $0.generation &+= 1
            }
        }

        func cancel() {
            let update = state.withLock {
                $0.sequence.cancel()
                $0.generation &+= 1
                return Update(generation: $0.generation, actionID: nil)
            }
            onUpdate(update)
        }

        func clearKeys() { state.withLock { $0.sequence = LeaderSequence() } }

        func groupName(for update: Update) -> String? {
            state.withLock { $0.generation == update.generation ? $0.sequence.groupName : nil }
        }

        func isCurrent(_ update: Update) -> Bool {
            state.withLock { $0.generation == update.generation }
        }

        func handle(_ type: CGEventType, event: CGEvent, secureInput: Bool) -> Bool {
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                cancel()
                return false
            }
            let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
            guard event.getIntegerValueField(.eventSourceUserData) != 0x5459_4354 else { return false }
            if type == .keyUp { return state.withLock { $0.sequence.keyUp(code) } }
            if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown
                || secureInput
            {
                cancel()
                return false
            }
            let result: (Bool, Update?) = state.withLock { state in
                let held = ModifierKey.held(
                    in: event.flags.rawValue, globeDown: event.flags.contains(.maskSecondaryFn))
                let others = !held.subtracting([state.trigger]).isEmpty
                if type == .flagsChanged {
                    guard others else { return (false, nil) }
                    state.sequence.cancel()
                    state.generation &+= 1
                    return (false, Update(generation: state.generation, actionID: nil))
                }
                guard type == .keyDown else { return (false, nil) }
                let previousGroup = state.sequence.groupName
                let key: String
                switch code {
                case kVK_Escape: key = "escape"
                case kVK_Delete: key = "backspace"
                default: key = state.characters[code] ?? ""
                }
                let decision = state.sequence.keyDown(
                    code: code, key: key, triggerHeld: held.contains(state.trigger),
                    hasOtherModifiers: others,
                    isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                    nodes: state.nodes)
                guard decision.consumed || previousGroup != state.sequence.groupName else {
                    return (false, nil)
                }
                return (decision.consumed, Update(
                    generation: state.generation, actionID: decision.actionID))
            }
            if let update = result.1 { onUpdate(update) }
            return result.0
        }
    }
}
