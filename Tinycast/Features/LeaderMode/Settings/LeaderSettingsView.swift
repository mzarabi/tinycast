import SwiftUI

struct LeaderSettingsView: View {
    @Environment(LeaderCoordinator.self) private var coordinator
    @Environment(AppSettings.self) private var settings
    @State private var editing: LeaderBindingTree.Edit?

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Toggle("Enable Leader Mode", isOn: Binding(
                    get: { settings.leaderEnabled }, set: coordinator.setEnabled))
                Picker("Trigger", selection: $settings.leaderTrigger) {
                    ForEach(LeaderCoordinator.triggers, id: \.rawValue) { key in
                        Text(HyperKeyPhysicalKey(rawValue: key.rawValue)?.title ?? key.rawValue)
                            .tag(key.rawValue)
                    }
                }
                Text("Hold the trigger and press a key. After entering a group, release it and continue typing.")
                    .foregroundStyle(.secondary)
                if let problem = coordinator.problem {
                    Text(problem).foregroundStyle(Theme.Colors.destructive)
                }
                if coordinator.needsAccessibility {
                    Button("Open Accessibility Settings", action: Permissions.openAccessibilitySettings)
                }
            }
            Section {
                LeaderBindingTree(nodes: coordinator.nodes, editing: $editing)
            } header: {
                Text("Leader Bindings")
            } footer: {
                Text("""
                    Escape cancels. Backspace goes up one group. An unknown key cancels without typing \
                    into the foreground app.
                    """)
            }
        }
        .formStyle(.grouped)
        .settingsEditorPanel(item: $editing) { edit in
            LeaderBindingEditor(node: edit.node, actions: coordinator.actions) { node in
                guard coordinator.save(node, replacing: edit.originalKey, in: edit.path) else { return false }
                editing = nil
                return true
            } onCancel: {
                editing = nil
            }
        }
        .onChange(of: settings.leaderBindings) {
            editing = nil
        }
    }
}
