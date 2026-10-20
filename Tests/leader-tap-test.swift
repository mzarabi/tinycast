import AppKit
import Synchronization

@main
struct LeaderTapTests {
    static func main() {
        let updates = Mutex<[LeaderKeyTap.Update]>([])
        let session = LeaderKeyTap.Session { update in updates.withLock { $0.append(update) } }
        let teams = LeaderNode(key: "t", name: "Teams", actionID: "teams")
        let nodes = [LeaderNode(key: "m", name: "Messages", children: [teams])]
        session.configure(nodes: nodes, trigger: .rightCommand, characters: [46: "m", 17: "t"])
        func event(_ type: CGEventType, code: Int = 46, flags: UInt64 = 0,
                   repeatKey: Bool = false, secureInput: Bool = false, synthetic: Bool = false) -> Bool {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: type == .keyDown)!
            event.type = type
            event.flags = CGEventFlags(rawValue: flags)
            event.setIntegerValueField(.keyboardEventAutorepeat, value: repeatKey ? 1 : 0)
            event.setIntegerValueField(.eventSourceUserData, value: synthetic ? 0x5459_4354 : 0)
            return session.handle(type, event: event, secureInput: secureInput)
        }
        let rightCommand: UInt64 = CGEventFlags.maskCommand.rawValue | 0x10
        let leftCommand: UInt64 = CGEventFlags.maskCommand.rawValue | 0x08
        assert(!event(.keyDown))
        assert(!event(.keyDown, flags: leftCommand))
        assert(!event(.flagsChanged, code: 54, flags: rightCommand))
        assert(event(.keyDown, flags: rightCommand))
        let entered = updates.withLock { $0.last! }
        assert(session.groupName(for: entered) == "Messages")
        assert(event(.keyUp, flags: rightCommand))
        assert(!event(.flagsChanged, code: 54))
        assert(session.groupName(for: entered) == "Messages")
        assert(event(.keyDown, code: 17))
        let action = updates.withLock { $0.last! }
        assert(action.actionID == "teams")
        assert(session.groupName(for: action) == nil)
        assert(event(.keyDown, code: 17, repeatKey: true))
        assert(updates.withLock { $0.filter { $0.actionID == "teams" }.count } == 1)
        assert(event(.keyUp, code: 17))
        assert(!event(.keyUp, code: 17))

        assert(event(.keyDown, flags: rightCommand))
        assert(event(.keyUp))
        assert(!event(.leftMouseDown))
        assert(!session.isCurrent(entered))
        assert(!event(.keyDown, code: 17))
        assert(event(.keyDown, flags: rightCommand))
        assert(event(.keyUp))
        assert(!event(.flagsChanged, code: 56, flags: CGEventFlags.maskShift.rawValue | 0x02))
        assert(!event(.keyDown, code: 17))

        assert(event(.keyDown, flags: rightCommand))
        assert(event(.keyUp))
        assert(!event(.keyDown, code: 17, secureInput: true))
        assert(!event(.keyDown, code: 17))
        assert(!event(.keyDown, flags: rightCommand, synthetic: true))
        assert(!event(.keyDown, code: 17))
        assert(event(.keyDown, flags: rightCommand))
        session.cancel()
        assert(!session.isCurrent(action))
        assert(event(.keyUp))
        assert(!event(.keyDown, code: 17))

        assert(event(.keyDown, flags: rightCommand))
        assert(event(.keyUp))
        assert(!event(.tapDisabledByTimeout))
        assert(!event(.keyDown, code: 17))
        assert(event(.keyDown, flags: rightCommand))
        session.configure(nodes: [], trigger: .rightCommand, characters: [:])
        assert(event(.keyUp))
        assert(!event(.keyDown, code: 17))
        session.clearKeys()
        assert(!event(.keyUp))
        print("Leader event routing tests passed; no events posted")
    }
}
