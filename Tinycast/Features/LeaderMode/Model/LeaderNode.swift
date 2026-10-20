import Foundation

struct LeaderNode: Codable, Equatable, Sendable, Identifiable {
    var key: String
    var name: String
    var actionID: String?
    var children: [LeaderNode]?

    var id: String { key }
    var isGroup: Bool { children != nil }

    static func normalizedKey(_ key: String) -> String {
        key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func isValidKey(_ key: String) -> Bool {
        key.count == 1 && key.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) && $0.isASCII
        }
    }

    static func validate(_ nodes: [Self], depth: Int = 0) -> Bool {
        guard depth < 16, Set(nodes.map(\.key)).count == nodes.count else { return false }
        return nodes.allSatisfy { node in
            guard isValidKey(node.key), node.key == normalizedKey(node.key),
                !node.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return false }
            if let children = node.children {
                return node.actionID == nil && validate(children, depth: depth + 1)
            }
            return node.actionID?.isEmpty == false
        }
    }

    static func decode(_ string: String) -> [Self]? {
        guard let nodes = try? JSONDecoder().decode([Self].self, from: Data(string.utf8)),
            validate(nodes)
        else { return nil }
        return nodes
    }

    static func encode(_ nodes: [Self]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(bytes: try encoder.encode(nodes), encoding: .utf8)!
    }

    static func nodes(in path: [String], root: [Self]) -> [Self]? {
        var nodes = root
        for key in path {
            guard let children = nodes.first(where: { $0.key == key })?.children else { return nil }
            nodes = children
        }
        return nodes
    }

    static func replace(in path: ArraySlice<String>, root: inout [Self], with nodes: [Self]) -> Bool {
        guard let key = path.first else { root = nodes; return true }
        guard let index = root.firstIndex(where: { $0.key == key }),
            var children = root[index].children,
            replace(in: path.dropFirst(), root: &children, with: nodes)
        else { return false }
        root[index].children = children
        return true
    }
}
