import Foundation

struct LeaderSequence: Sendable {
    struct Decision: Equatable, Sendable {
        var consumed = false
        var actionID: String?
    }

    private(set) var path: [String] = []
    private(set) var groupName: String?
    private var suppressedKeys: Set<Int> = []

    mutating func cancel() {
        path = []
        groupName = nil
    }

    mutating func keyUp(_ code: Int) -> Bool {
        suppressedKeys.remove(code) != nil
    }

    mutating func keyDown(
        code: Int, key: String, triggerHeld: Bool, hasOtherModifiers: Bool,
        isRepeat: Bool, nodes: [LeaderNode]
    ) -> Decision {
        if suppressedKeys.contains(code) { return Decision(consumed: true) }
        guard !hasOtherModifiers, triggerHeld || !path.isEmpty else {
            cancel()
            return Decision()
        }
        suppressedKeys.insert(code)
        guard !isRepeat else { return Decision(consumed: true) }
        if key == "escape" {
            cancel()
            return Decision(consumed: true)
        }
        if key == "backspace" {
            if !path.isEmpty { path.removeLast() }
            updateGroupName(nodes)
            return Decision(consumed: true)
        }
        guard let current = LeaderNode.nodes(in: path, root: nodes),
            let node = current.first(where: { $0.key == key })
        else {
            cancel()
            return Decision(consumed: true)
        }
        if node.isGroup {
            path.append(node.key)
            groupName = node.name
            return Decision(consumed: true)
        }
        cancel()
        return Decision(consumed: true, actionID: node.actionID)
    }

    private mutating func updateGroupName(_ nodes: [LeaderNode]) {
        guard let key = path.last,
            let parent = LeaderNode.nodes(in: Array(path.dropLast()), root: nodes)
        else { groupName = nil; return }
        groupName = parent.first(where: { $0.key == key })?.name
    }
}
