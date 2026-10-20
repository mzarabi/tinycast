import Foundation

@main
struct LeaderTests {
    @MainActor
    static func main() throws {
        let teams = LeaderNode(key: "t", name: "Teams", actionID: "hotkey.app.com.microsoft.teams2")
        let nested = LeaderNode(key: "w", name: "Work", children: [teams])
        let messages = LeaderNode(key: "m", name: "Messages", children: [teams, nested])
        let safari = LeaderNode(key: "s", name: "Safari", actionID: "hotkey.app.com.apple.Safari")
        let nodes = [messages, safari]
        let groupPaths = LeaderTree.groupPaths(in: nodes)
        assert(groupPaths == Set([["m"], ["m", "w"]]))
        let treeRows = LeaderTree.rows(in: nodes, expanded: groupPaths)
        assert(treeRows.map(\.id) == [["m"], ["m", "t"], ["m", "w"], ["m", "w", "t"], ["s"]])
        assert(treeRows.map(\.depth) == [0, 1, 1, 2, 0])
        assert(treeRows[3].parentPath == ["m", "w"])
        assert(treeRows[1].node == teams && treeRows[3].node == teams)
        assert(Set(treeRows.map(\.id)).count == treeRows.count)
        assert(LeaderTree.rows(in: nodes, expanded: []).map(\.id) == [["m"], ["s"]])
        assert(LeaderTree.rows(in: nodes, expanded: [["m", "w"]]).map(\.id) == [["m"], ["s"]])
        assert(LeaderTree.rows(in: nodes, expanded: [["m"]]).map(\.id) == [
            ["m"], ["m", "t"], ["m", "w"], ["s"]
        ])
        assert(LeaderTree.rows(in: [], expanded: groupPaths).isEmpty)
        let emptyGroup = LeaderNode(key: "e", name: "Empty", children: [])
        assert(LeaderTree.groupPaths(in: [emptyGroup]) == Set([["e"]]))
        assert(LeaderTree.rows(in: [emptyGroup], expanded: [["e"]]).map(\.id) == [["e"]])
        assert(LeaderNode.validate(nodes))
        let encoded = try LeaderNode.encode(nodes)
        assert(LeaderNode.decode(encoded) == nodes)
        assert(LeaderNode.decode("bad json") == nil)
        assert(!LeaderNode.validate([messages, messages]))
        assert(!LeaderNode.validate([LeaderNode(key: "M", name: "Messages", children: [])]))
        assert(!LeaderNode.validate([LeaderNode(key: "mm", name: "Messages", children: [])]))
        assert(!LeaderNode.validate([LeaderNode(key: "m", name: " ", children: [])]))
        assert(!LeaderNode.validate([LeaderNode(key: "m", name: "Messages", actionID: "x", children: [])]))
        assert(!LeaderNode.validate([LeaderNode(key: "m", name: "Messages")]))
        assert(!LeaderNode.validate([LeaderNode(key: "m", name: "Messages", actionID: "")]))
        assert(LeaderNode.normalizedKey(" M ") == "m")
        assert(!LeaderNode.isValidKey("é"))
        assert(!LeaderNode.isValidKey(" "))
        assert(LeaderNode.isValidKey("1"))
        assert(LeaderNode.nodes(in: ["m", "w"], root: nodes) == [teams])
        assert(LeaderNode.nodes(in: ["s"], root: nodes) == nil)
        let movedSafari = LeaderTree.moving(["s"], to: .inside(["m"]), in: nodes)!
        assert(movedSafari.count == 1)
        assert(movedSafari[0].children == [teams, nested, safari])
        assert(LeaderTree.moving(["m", "s"], to: .inside([]), in: movedSafari) == nodes)
        assert(LeaderTree.moving(["s"], to: .before(["m"]), in: nodes) == [safari, messages])
        assert(LeaderTree.moving(["m"], to: .after(["s"]), in: nodes) == [safari, messages])
        let reordered = LeaderTree.moving(["m", "t"], to: .after(["m", "w"]), in: nodes)!
        assert(reordered[0].children == [nested, teams])
        assert(LeaderTree.moving(["m", "w"], to: .inside([]), in: nodes) == [
            LeaderNode(key: "m", name: "Messages", children: [teams]), safari, nested
        ])
        assert(LeaderTree.moving(["m", "t"], to: .inside(["m", "w"]), in: nodes) == nil)
        assert(LeaderTree.moving(["m"], to: .inside(["m"]), in: nodes) == nil)
        assert(LeaderTree.moving(["m"], to: .inside(["m", "w"]), in: nodes) == nil)
        assert(LeaderTree.moving(["m"], to: .before(["m", "w", "t"]), in: nodes) == nil)
        assert(LeaderTree.moving(["s"], to: .inside(["s"]), in: nodes) == nil)
        assert(LeaderTree.moving(["x"], to: .inside([]), in: nodes) == nil)
        assert(LeaderTree.moving([], to: .inside([]), in: nodes) == nil)
        assert(LeaderTree.moving(["s"], to: .inside(["x"]), in: nodes) == nil)
        assert(LeaderTree.moving(["s"], to: .before(["x"]), in: nodes) == nil)
        assert(LeaderTree.moving(["s"], to: .before(["s"]), in: nodes) == nil)
        assert(LeaderTree.moving(["s"], to: .inside([]), in: nodes) == nil)
        assert(LeaderTree.moving(["s"], to: .after(["m"]), in: nodes) == nil)
        var deepGroup = emptyGroup
        for _ in 0..<14 { deepGroup = LeaderNode(key: "d", name: "Deep", children: [deepGroup]) }
        let deepNodes = [deepGroup, nested]
        assert(LeaderNode.validate(deepNodes))
        assert(LeaderTree.moving(["w"], to: .inside(Array(repeating: "d", count: 14) + ["e"]), in: deepNodes) == nil)
        let movedEncoded = try LeaderNode.encode(movedSafari)
        assert(LeaderNode.decode(movedEncoded) == movedSafari)

        var sequence = LeaderSequence()
        func press(_ key: String, code: Int = 1, held: Bool = false, other: Bool = false,
                   repeatKey: Bool = false) -> LeaderSequence.Decision {
            sequence.keyDown(code: code, key: key, triggerHeld: held, hasOtherModifiers: other,
                             isRepeat: repeatKey, nodes: nodes)
        }
        assert(!press("m").consumed)
        assert(!sequence.keyUp(1))
        assert(!press("m", held: true, other: true).consumed)
        assert(press("m", held: true).consumed)
        assert(sequence.groupName == "Messages")
        assert(press("m", held: true, repeatKey: true).consumed)
        assert(sequence.path == ["m"])
        assert(sequence.keyUp(1))
        assert(!sequence.keyUp(1))
        assert(sequence.groupName == "Messages")
        assert(press("t").actionID == teams.actionID)
        assert(sequence.groupName == nil && sequence.path.isEmpty)
        assert(press("t", repeatKey: true).consumed)
        assert(sequence.keyUp(1))
        assert(!press("t").consumed)

        assert(press("m", held: true).consumed)
        assert(sequence.keyUp(1))
        assert(press("w").consumed)
        assert(sequence.keyUp(1))
        assert(sequence.groupName == "Work")
        assert(press("backspace").consumed)
        assert(sequence.keyUp(1))
        assert(sequence.groupName == "Messages")
        assert(press("w").consumed)
        assert(sequence.keyUp(1))
        assert(press("t").actionID == teams.actionID)
        assert(sequence.keyUp(1))

        assert(press("m", held: true).consumed)
        assert(sequence.keyUp(1))
        assert(press("escape").consumed)
        assert(sequence.keyUp(1))
        assert(sequence.path.isEmpty)
        assert(press("s", held: true).actionID == safari.actionID)
        assert(sequence.keyUp(1))
        assert(press("q", held: true).consumed)
        assert(sequence.keyUp(1))
        assert(sequence.path.isEmpty)
        assert(press("m", held: true).consumed)
        assert(sequence.keyUp(1))
        assert(press("unknown").consumed)
        assert(sequence.keyUp(1))
        assert(!press("s").consumed)

        assert(press("m", held: true).consumed)
        assert(sequence.keyUp(1))
        assert(!press("t", other: true).consumed)
        assert(sequence.groupName == nil)
        assert(press("m", held: true).consumed)
        sequence.cancel()
        assert(sequence.groupName == nil)
        assert(sequence.keyUp(1))
        assert(!press("t").consumed)
        assert(press("s", held: true, repeatKey: true).consumed)
        assert(sequence.keyUp(1))
        assert(press("m", held: true).consumed)
        assert(sequence.keyUp(1))
        assert(press("t", repeatKey: true).actionID == nil)
        assert(sequence.groupName == "Messages")
        assert(sequence.keyUp(1))
        assert(press("backspace").consumed)
        assert(sequence.groupName == nil)
        assert(sequence.keyUp(1))
        assert(!press("t").consumed)

        var edited = nodes
        assert(LeaderNode.replace(in: ["m", "w"][...], root: &edited, with: [safari]))
        assert(LeaderNode.nodes(in: ["m", "w"], root: edited) == [safari])
        assert(!LeaderNode.replace(in: ["missing"][...], root: &edited, with: []))
        assert(LeaderNode.nodes(in: ["m"], root: nodes) == [teams, nested])
        var scoped = [messages, LeaderNode(key: "b", name: "Business", children: [teams])]
        assert(LeaderNode.validate(scoped))
        assert(LeaderNode.replace(in: ["b"][...], root: &scoped, with: [safari]))
        assert(LeaderNode.nodes(in: ["b"], root: scoped) == [safari])
        assert(LeaderNode.nodes(in: ["m"], root: scoped) == [teams, nested])
        assert(LeaderNode.replace(in: ["m", "w"][...], root: &scoped, with: []))
        assert(LeaderNode.nodes(in: ["m", "w"], root: scoped) == [])
        assert(LeaderNode.nodes(in: ["b"], root: scoped) == [safari])
        assert(LeaderNode.nodes(in: ["m"], root: nodes) == [teams, nested])
        var deep = [teams]
        for _ in 0..<16 { deep = [LeaderNode(key: "a", name: "Deep", children: deep)] }
        assert(!LeaderNode.validate(deep))
        let settings = AppSettings()
        settings.leaderBindings = encoded
        let binding = LeaderSettingsFile.binding(settings: settings)
        assert(binding.key.rawValue == "leaderMode.bindings")
        assert(SettingsFileKey.leaderTrigger.rawValue == "leaderMode.trigger")
        let json = binding.read()
        assert(json.items?.first?["children"]?.items?.count == 2)
        assert(json.items?.last?["action"]?.string == safari.actionID)
        assert(binding.write(json).isEmpty)
        assert(LeaderNode.decode(settings.leaderBindings) == nodes)
        let previous = settings.leaderBindings
        let duplicate: SettingsFileJSON = .array([json.items![0], json.items![0]])
        assert(!binding.write(duplicate).isEmpty)
        assert(settings.leaderBindings == previous)
        assert(!binding.write(.string("[]")).isEmpty)
        let both: SettingsFileJSON = .array([.object([
            "key": .string("m"), "name": .string("Messages"),
            "children": .array([]), "action": .string("teams")
        ])])
        assert(!binding.write(both).isEmpty)
        let unknown: SettingsFileJSON = .array([.object([
            "key": .string("t"), "name": .string("Teams"),
            "action": .string("teams"), "typo": .bool(true)
        ])])
        assert(!binding.write(unknown).isEmpty)
        assert(settings.leaderBindings == previous)
        assert(binding.write(.array([])).isEmpty)
        assert(settings.leaderBindings == "[]")
        print("Leader sequence and configuration tests passed")
    }
}

@MainActor
final class AppSettings {
    var leaderBindings = "[]"
}
