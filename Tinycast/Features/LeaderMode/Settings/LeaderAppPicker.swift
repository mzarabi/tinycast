import SwiftUI

struct LeaderAppPicker: View {
    let selectedBundleID: String?
    let onSelect: (String) -> Void
    @Environment(AppIndex.self) private var appIndex
    @Environment(\.settingsEditorDismiss) private var dismiss
    @State private var query = ""
    @State private var selection: String?
    @FocusState private var searchFocused: Bool

    private var applications: [AppEntry] {
        appIndex.apps.filter {
            $0.kind == .application && $0.bundleID != nil
                && (query.isEmpty || $0.name.localizedStandardContains(query))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            SettingsEditorHeader(title: "Choose App…")
            TextField("Search apps…", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .onSubmit(chooseSelection)
                .onKeyPress(.downArrow) { moveSelection(by: 1); return .handled }
                .onKeyPress(.upArrow) { moveSelection(by: -1); return .handled }
            ScrollViewReader { scroll in
                applicationList
                    .onChange(of: selection) {
                        guard let app = applications.first(where: { $0.bundleID == selection }) else { return }
                        scroll.scrollTo(app.id)
                    }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Choose", action: chooseSelection)
                    .keyboardShortcut(.defaultAction)
                    .settingsEnabled(applications.contains { $0.bundleID == selection })
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: Theme.Size.dialogWidth, height: Theme.Size.panelHeight)
        .settingsEditorPanelSurface(controlsOnGlass: false)
        .defaultFocus($searchFocused, true)
        .onAppear {
            selection = applications.first(where: { $0.bundleID == selectedBundleID })?.bundleID
                ?? applications.first?.bundleID
        }
        .onChange(of: query) { selection = applications.first?.bundleID }
    }

    private var applicationList: some View {
        List(selection: $selection) {
            ForEach(applications) { app in
                if let bundleID = app.bundleID {
                    Label {
                        Text(verbatim: app.name).lineLimit(1)
                    } icon: {
                        Image(nsImage: app.icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: Theme.Size.settingsRowIcon, height: Theme.Size.settingsRowIcon)
                    }
                    .tag(bundleID)
                    .onTapGesture(count: 2) { onSelect(bundleID) }
                }
            }
        }
        .listStyle(.inset)
        .overlay {
            if applications.isEmpty {
                Text("No apps found").foregroundStyle(.secondary)
            }
        }
    }

    private func moveSelection(by offset: Int) {
        let apps = applications
        guard !apps.isEmpty else { return }
        let current = apps.firstIndex(where: { $0.bundleID == selection }) ?? 0
        selection = apps[min(max(current + offset, 0), apps.count - 1)].bundleID
    }

    private func chooseSelection() {
        guard let selection, applications.contains(where: { $0.bundleID == selection }) else { return }
        onSelect(selection)
    }
}
