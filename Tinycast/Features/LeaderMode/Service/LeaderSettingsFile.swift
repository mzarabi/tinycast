import Foundation

@MainActor
enum LeaderSettingsFile {
    static func binding(settings: AppSettings) -> SettingsFileBinding {
        SettingsFileBinding(
            .leaderBindings,
            read: { .array((LeaderNode.decode(settings.leaderBindings) ?? []).map(json)) },
            write: { value in
                guard let nodes = decode(value), LeaderNode.validate(nodes) else {
                    return [.invalidValue(.leaderBindings)]
                }
                do {
                    let encoded = try LeaderNode.encode(nodes)
                    if settings.leaderBindings != encoded { settings.leaderBindings = encoded }
                    return []
                } catch {
                    return [.invalidValue(.leaderBindings)]
                }
            })
    }

    private static func json(_ node: LeaderNode) -> SettingsFileJSON {
        var members: [SettingsFileJSON.Member] = [
            .init(key: "key", value: .string(node.key)),
            .init(key: "name", value: .string(node.name))
        ]
        if let children = node.children {
            members.append(.init(key: "children", value: .array(children.map(json))))
        } else if let action = node.actionID {
            members.append(.init(key: "action", value: .string(action)))
        }
        return .object(members)
    }

    private static func decode(_ json: SettingsFileJSON, depth: Int = 0) -> [LeaderNode]? {
        guard depth < 16, let items = json.items else { return nil }
        var nodes: [LeaderNode] = []
        for item in items {
            guard let members = item.members,
                Set(members.map(\.key)).isSubset(of: ["key", "name", "action", "children"]),
                let key = item["key"]?.string, let name = item["name"]?.string
            else { return nil }
            if let children = item["children"] {
                guard item["action"] == nil, let children = decode(children, depth: depth + 1) else {
                    return nil
                }
                nodes.append(LeaderNode(key: key, name: name, children: children))
            } else {
                guard let action = item["action"]?.string else { return nil }
                nodes.append(LeaderNode(key: key, name: name, actionID: action))
            }
        }
        return nodes
    }
}
