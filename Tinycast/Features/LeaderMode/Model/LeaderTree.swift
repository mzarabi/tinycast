import Foundation

enum LeaderTree {
    enum Destination: Hashable {
        case inside([String])
        case before([String])
        case after([String])

        var parentPath: [String] {
            switch self {
            case let .inside(path): path
            case let .before(path), let .after(path): Array(path.dropLast())
            }
        }
    }

    static func moving(_ source: [String], to destination: Destination, in nodes: [LeaderNode]) -> [LeaderNode]? {
        let parent = destination.parentPath
        guard let key = source.last, !parent.starts(with: source),
            var siblings = LeaderNode.nodes(in: Array(source.dropLast()), root: nodes),
            let index = siblings.firstIndex(where: { $0.key == key })
        else { return nil }
        let node = siblings.remove(at: index)
        var root = nodes
        guard LeaderNode.replace(in: source.dropLast(), root: &root, with: siblings),
            var children = LeaderNode.nodes(in: parent, root: root),
            !children.contains(where: { $0.key == key })
        else { return nil }
        let insertion: Int
        switch destination {
        case .inside:
            insertion = children.count
        case let .before(path), let .after(path):
            guard let target = children.firstIndex(where: { $0.key == path.last }) else { return nil }
            insertion = target + (destination == .after(path) ? 1 : 0)
        }
        children.insert(node, at: insertion)
        guard LeaderNode.replace(in: parent[...], root: &root, with: children), LeaderNode.validate(root), root != nodes
        else { return nil }
        return root
    }

    struct Row: Identifiable, Equatable, Sendable {
        let node: LeaderNode
        let path: [String]

        var id: [String] { path }
        var parentPath: [String] { Array(path.dropLast()) }
        var depth: Int { path.count - 1 }
    }

    static func rows(
        in nodes: [LeaderNode], expanded: Set<[String]>, path: [String] = []
    ) -> [Row] {
        nodes.flatMap { node -> [Row] in
            let nodePath = path + [node.key]
            let row = Row(node: node, path: nodePath)
            guard let children = node.children, expanded.contains(nodePath) else { return [row] }
            return [row] + rows(in: children, expanded: expanded, path: nodePath)
        }
    }

    static func groupPaths(in nodes: [LeaderNode], path: [String] = []) -> Set<[String]> {
        nodes.reduce(into: []) { paths, node in
            guard let children = node.children else { return }
            let nodePath = path + [node.key]
            paths.insert(nodePath)
            paths.formUnion(groupPaths(in: children, path: nodePath))
        }
    }
}
