import SwiftUI

struct LeaderBindingTree: View {
    struct Edit: Identifiable {
        let id = UUID()
        let node: LeaderNode
        let path: [String]
        let originalKey: String?
    }

    let nodes: [LeaderNode]
    @Binding var editing: Edit?
    @State private var expanded: Set<[String]>
    @State private var revision = UUID().uuidString
    @Environment(LeaderCoordinator.self) private var coordinator

    init(nodes: [LeaderNode], editing: Binding<Edit?>) {
        self.nodes = nodes
        _editing = editing
        _expanded = State(initialValue: LeaderTree.groupPaths(in: nodes))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            ForEach(LeaderTree.rows(in: nodes, expanded: expanded)) { row in
                DropTarget(nodes: nodes, revision: revision, row: row, onExpand: { expanded.insert(row.path) }, onMove: move) {
                    Row(entry: row, expanded: expanded.contains(row.path), editing: $editing) {
                        if expanded.contains(row.path) { expanded.remove(row.path) } else { expanded.insert(row.path) }
                    }
                    .draggable(String.self, id: \.self, item: revision + "/" + row.path.joined(separator: "/"))
                    .dragConfiguration(DragConfiguration(
                        operationsWithinApp: .init(allowCopy: false, allowMove: true),
                        operationsOutsideApp: .init(allowCopy: false)))
                }
            }
            DropTarget(nodes: nodes, revision: revision, row: nil, onExpand: {}, onMove: move) {
                AddMenu(path: [], compact: false, editing: $editing)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, Theme.Spacing.md)
            }
        }
        .onChange(of: nodes) { previous, current in
            revision = UUID().uuidString
            let groups = LeaderTree.groupPaths(in: current)
            expanded.formIntersection(groups)
            expanded.formUnion(groups.subtracting(LeaderTree.groupPaths(in: previous)))
        }
    }

    private func move(_ source: [String], _ destination: LeaderTree.Destination) {
        guard let key = source.last else { return }
        let movedExpansion = expanded.filter { $0.starts(with: source) }.map {
            destination.parentPath + [key] + $0.dropFirst(source.count)
        }
        guard coordinator.move(source, to: destination) else { return }
        expanded.formUnion(movedExpansion)
        if case let .inside(path) = destination { expanded.insert(path) }
    }

    private struct DropTarget<Content: View>: View {
        let nodes: [LeaderNode]
        let revision: String
        let row: LeaderTree.Row?
        let onExpand: () -> Void
        let onMove: ([String], LeaderTree.Destination) -> Void
        @ViewBuilder let content: () -> Content
        @State private var target: LeaderTree.Destination?

        var body: some View {
            content()
                .contentShape(Rectangle())
                .background(targetIsInside ? Theme.Colors.rowHover : .clear,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
                .overlay(alignment: targetIsBefore ? .top : .bottom) {
                    if target != nil && !targetIsInside {
                        Rectangle().fill(Theme.Colors.textSecondary).frame(height: Theme.Spacing.xxs)
                            .padding(.leading, CGFloat(row?.depth ?? 0) * Theme.Size.settingsControlHeight)
                    }
                }
                .dropDestination(for: String.self) { items, session in
                    guard let source = source(in: session), items == [revision + "/" + source.joined(separator: "/")],
                        let destination = destination(in: session),
                        LeaderTree.moving(source, to: destination, in: nodes) != nil
                    else { return }
                    onMove(source, destination)
                    target = nil
                }
                .dropConfiguration { session in
                    DropConfiguration(operation: destination(in: session) == nil ? .cancel : .move)
                }
                .onDropSessionUpdated { session in
                    switch session.phase {
                    case .entering, .active: target = destination(in: session)
                    default: target = nil
                    }
                }
                .task(id: target) {
                    guard targetIsInside, row != nil else { return }
                    do { try await Task.sleep(for: .milliseconds(600)) } catch { return }
                    onExpand()
                }
        }

        private var targetIsInside: Bool {
            if case .inside = target { return true }
            return false
        }

        private var targetIsBefore: Bool {
            if case .before = target { return true }
            return false
        }

        private func source(in session: DropSession) -> [String]? {
            guard let items = session.localSession?.draggedItemIDs(for: String.self), items.count == 1,
                let item = items.first, item.hasPrefix(revision + "/")
            else { return nil }
            return item.split(separator: "/").dropFirst().map(String.init)
        }

        private func destination(in session: DropSession) -> LeaderTree.Destination? {
            guard let source = source(in: session) else { return nil }
            let destination: LeaderTree.Destination
            if let row {
                let fraction = session.location.y / max(session.size.height, 1)
                if row.node.isGroup && fraction >= 0.25 && fraction <= 0.75 {
                    destination = .inside(row.path)
                } else {
                    destination = fraction < 0.5 ? .before(row.path) : .after(row.path)
                }
            } else {
                destination = .inside([])
            }
            return LeaderTree.moving(source, to: destination, in: nodes) == nil ? nil : destination
        }
    }

    private struct Row: View {
        let entry: LeaderTree.Row
        let expanded: Bool
        @Binding var editing: Edit?
        let onToggle: () -> Void
        @Environment(LeaderCoordinator.self) private var coordinator
        @Environment(AppIndex.self) private var appIndex
        @State private var hovered = false

        var body: some View {
            HStack(spacing: Theme.Spacing.md) {
                disclosure
                Button(action: edit) {
                    HStack(spacing: Theme.Spacing.lg) {
                        KeyCapChip(text: entry.node.key.uppercased())
                            .frame(width: Theme.Size.settingsControlHeight)
                        icon.accessibilityHidden(true)
                        Text(verbatim: entry.node.name)
                            .font(Theme.Typography.rowTitle)
                            .lineLimit(1)
                        Spacer(minLength: Theme.Spacing.md)
                    }
                    .frame(maxWidth: .infinity, minHeight: Theme.Size.settingsControlHeight, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Edit")
                if entry.node.isGroup {
                    AddMenu(path: entry.path, compact: true, editing: $editing) {
                        if !expanded { onToggle() }
                    }
                }
                Menu {
                    Button("Edit", action: edit)
                    Button("Delete", role: .destructive) {
                        coordinator.remove(entry.node.key, in: entry.parentPath)
                    }
                } label: {
                    SymbolImage(name: "ellipsis", size: Theme.Size.keyCap)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .frame(width: Theme.Size.settingsControlHeight, height: Theme.Size.settingsControlHeight)
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityLabel("Actions")
                .help("Actions")
            }
            .padding(.vertical, Theme.Spacing.xs)
            .padding(.trailing, Theme.Spacing.xs)
            .padding(.leading, CGFloat(entry.depth) * Theme.Size.settingsControlHeight)
            .background(
                hovered ? Theme.Colors.rowHover : .clear,
                in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
            .onHover { hovered = $0 }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(verbatim: entry.node.name))
        }

        @ViewBuilder private var disclosure: some View {
            if entry.node.isGroup {
                Button(action: onToggle) {
                    SymbolImage(
                        name: expanded ? "chevron.down" : "chevron.right",
                        size: Theme.Size.settingsRowIcon / 2)
                        .frame(width: Theme.Size.settingsRowIcon, height: Theme.Size.settingsControlHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Colors.textSecondary)
                .accessibilityLabel(Text(verbatim: entry.node.name))
                .accessibilityValue(expanded ? Text("Expanded") : Text("Collapsed"))
            } else {
                Color.clear.frame(width: Theme.Size.settingsRowIcon, height: Theme.Size.settingsControlHeight)
                    .accessibilityHidden(true)
            }
        }

        @ViewBuilder private var icon: some View {
            let prefix = HotKeyAction.app(bundleID: "").defaultsKey
            if let actionID = entry.node.actionID, actionID.hasPrefix(prefix) {
                let bundleID = String(actionID.dropFirst(prefix.count))
                let app = AppPresentation.resolve(bundleID: bundleID, in: appIndex)
                Image(nsImage: app.icon).resizable().scaledToFit()
                    .frame(width: Theme.Size.settingsRowIcon, height: Theme.Size.settingsRowIcon)
            } else {
                SymbolImage(name: entry.node.isGroup ? "square.stack" : "bolt", size: Theme.Size.settingsSidebarGlyph)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(width: Theme.Size.settingsRowIcon, height: Theme.Size.settingsRowIcon)
            }
        }

        private func edit() {
            editing = Edit(node: entry.node, path: entry.parentPath, originalKey: entry.node.key)
        }
    }

    private struct AddMenu: View {
        let path: [String]
        let compact: Bool
        @Binding var editing: Edit?
        var onAdd: () -> Void = {}

        var body: some View {
            Menu {
                Button("Add Binding") {
                    onAdd()
                    editing = Edit(node: LeaderNode(key: "", name: "", actionID: ""), path: path, originalKey: nil)
                }
                Button("Add Group") {
                    onAdd()
                    editing = Edit(node: LeaderNode(key: "", name: "", children: []), path: path, originalKey: nil)
                }
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    SymbolImage(name: "plus", size: Theme.Size.keyCap)
                        .frame(width: compact ? nil : Theme.Size.settingsRowIcon)
                    if !compact { Text("Add…") }
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: compact ? Theme.Size.settingsControlHeight : nil, height: Theme.Size.settingsControlHeight)
            .foregroundStyle(Theme.Colors.textSecondary)
            .accessibilityLabel("Add")
            .help("Add")
        }
    }
}
