import AppKit
import SwiftUI

@MainActor
final class LeaderGroupController {
    private let settings: AppSettings
    private let presenter: HUDPresenter

    init(settings: AppSettings) {
        self.settings = settings
        presenter = HUDPresenter(
            anchor: .edgeInset(Theme.Size.hudEdgeOffset), dwell: 0,
            screen: { settings.openOnCursorScreen ? .underCursor : .primary })
    }

    func show(_ name: String?) {
        guard let name else { presenter.dismiss(); return }
        presenter.show(
            LeaderGroupPill(name: name).environment(\.metrics, settings.interfaceSize.metrics),
            dwells: false)
    }
}

private struct LeaderGroupPill: View {
    let name: String
    @Environment(\.metrics) private var metrics

    var body: some View {
        Text(verbatim: name)
            .font(metrics.typography.bar)
            .foregroundStyle(Theme.Colors.textPrimary)
            .lineLimit(1)
            .padding(.horizontal, metrics.spacing.xxl)
            .padding(.vertical, metrics.spacing.xl)
            .frame(maxWidth: metrics.size.hudMaxWidth)
            .fixedSize()
            .background(Theme.Colors.panelScrim)
            .background(GlassEffectView())
            .clipShape(Capsule())
            .overlay { Capsule().strokeBorder(Theme.Colors.border, lineWidth: Theme.Size.hairline) }
            .accessibilityLabel(Text(verbatim: name))
    }
}
