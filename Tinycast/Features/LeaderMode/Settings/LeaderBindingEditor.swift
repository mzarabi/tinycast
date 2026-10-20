import SwiftUI

struct LeaderBindingEditor: View {
    private enum ActionKind {
        case application, command
    }

    @State var node: LeaderNode
    let actions: [LeaderCoordinator.Action]
    let onSave: (LeaderNode) -> Bool
    let onCancel: () -> Void
    @State private var query = ""
    @State private var failed = false
    @State private var actionKind: ActionKind
    @State private var choosingApp = false
    @Environment(AppIndex.self) private var appIndex

    init(
        node: LeaderNode, actions: [LeaderCoordinator.Action],
        onSave: @escaping (LeaderNode) -> Bool, onCancel: @escaping () -> Void
    ) {
        _node = State(initialValue: node)
        self.actions = actions
        self.onSave = onSave
        self.onCancel = onCancel
        let isApp = node.actionID?.hasPrefix(Self.appActionPrefix) == true
        _actionKind = State(initialValue: node.actionID?.isEmpty != false || isApp ? .application : .command)
    }

    private static var appActionPrefix: String { HotKeyAction.app(bundleID: "").defaultsKey }

    private var applicationBundleID: String? {
        guard let id = node.actionID, id.hasPrefix(Self.appActionPrefix) else { return nil }
        return String(id.dropFirst(Self.appActionPrefix.count))
    }

    private var matchingActions: [LeaderCoordinator.Action] {
        actions.filter {
            if case .app = $0.action { return false }
            return query.isEmpty || $0.name.localizedStandardContains(query) || $0.id == node.actionID
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            SettingsEditorHeader(title: node.isGroup ? "Group" : "Binding")
            SettingsEditorField("Key") {
                TextField("Key", text: $node.key)
                    .settingsEditorTextField()
                    .onChange(of: node.key) { node.key = LeaderNode.normalizedKey(node.key) }
            }
            if node.isGroup {
                SettingsEditorField("Name") {
                    TextField("Name", text: $node.name).settingsEditorTextField()
                }
            }
            if !node.isGroup {
                Picker("Action", selection: $actionKind) {
                    Text("Open App").tag(ActionKind.application)
                    Text("Run Command").tag(ActionKind.command)
                }
                .onChange(of: actionKind) {
                    node.actionID = ""
                    query = ""
                }
                if actionKind == .application {
                    applicationRow
                } else {
                    commandPicker
                }
            }
            if failed {
                Text("Use a unique letter or digit and a name.")
                    .foregroundStyle(Theme.Colors.destructive)
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.modalAction(.cancel))
                    .keyboardShortcut(.cancelAction)
                Button("Save") { failed = !onSave(node) }
                    .buttonStyle(.modalAction(.primary))
                    .keyboardShortcut(.defaultAction)
                    .settingsEnabled(LeaderNode.validate([node]))
            }
        }
        .padding(Theme.Spacing.dialogInset)
        .frame(width: Theme.Size.editorSheetWidth)
        .settingsEditorPanelSurface(controlsOnGlass: false)
        .onAppear {
            if !node.isGroup, let action = actions.first(where: { $0.id == node.actionID }) {
                node.name = action.name
            }
        }
        .settingsEditorPanel(isPresented: $choosingApp) {
            LeaderAppPicker(selectedBundleID: applicationBundleID) { bundleID in
                node.actionID = HotKeyAction.app(bundleID: bundleID).defaultsKey
                node.name = AppPresentation.resolve(bundleID: bundleID, in: appIndex).name
                choosingApp = false
            }
        }
    }

    private var applicationRow: some View {
        LabeledContent {
            Button(applicationBundleID == nil ? "Choose App…" : "Change…") { choosingApp = true }
        } label: {
            if let bundleID = applicationBundleID {
                let app = AppPresentation.resolve(bundleID: bundleID, in: appIndex)
                Label {
                    Text(verbatim: app.name).lineLimit(1)
                } icon: {
                    Image(nsImage: app.icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: Theme.Size.settingsRowIcon, height: Theme.Size.settingsRowIcon)
                }
            } else {
                Text("Application")
            }
        }
    }

    private var commandPicker: some View {
        Group {
            TextField("Filter actions", text: $query)
                .settingsEditorTextField()
            Picker("Command", selection: Binding(
                get: { node.actionID ?? "" }, set: { id in
                    node.actionID = id
                    if let action = actions.first(where: { $0.id == id }) { node.name = action.name }
                })
            ) {
                Text("Choose an action").tag("")
                if let id = node.actionID, !id.isEmpty, !actions.contains(where: { $0.id == id }) {
                    Text(verbatim: node.name).tag(id)
                }
                ForEach(matchingActions) { action in
                    Text(verbatim: action.name).tag(action.id)
                }
            }
        }
    }
}
