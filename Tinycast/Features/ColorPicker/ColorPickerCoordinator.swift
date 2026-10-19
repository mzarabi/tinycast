import AppKit

@MainActor
final class ColorPickerCoordinator {
    private let hidePalette: () -> Void
    private let sample: (@escaping @MainActor (NSColor?) -> Void) -> Void
    private let pasteboard: NSPasteboard
    private let showCopied: (String) -> Void
    private let showFailure: () -> Void
    private var isSampling = false

    init(
        hidePalette: @escaping () -> Void,
        sample: @escaping (@escaping @MainActor (NSColor?) -> Void) -> Void = { completion in
            Task { @MainActor in
                let color = await NSColorSampler().sample()
                completion(color)
            }
        },
        pasteboard: NSPasteboard = .general,
        showCopied: @escaping (String) -> Void,
        showFailure: @escaping () -> Void
    ) {
        self.hidePalette = hidePalette
        self.sample = sample
        self.pasteboard = pasteboard
        self.showCopied = showCopied
        self.showFailure = showFailure
    }

    func pickColor() {
        guard !isSampling else { return }
        isSampling = true
        hidePalette()
        sample { [weak self] color in
            guard let self else { return }
            isSampling = false
            guard let color else { return }
            guard let hex = Self.hexString(for: color) else {
                showFailure()
                return
            }
            pasteboard.clearContents()
            guard pasteboard.setString(hex, forType: .string) else {
                showFailure()
                return
            }
            showCopied(hex)
        }
    }

    static func hexString(for color: NSColor) -> String? {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        return ColorFormat.hex.string(
            for: ColorValue(
                red: Double(rgb.redComponent), green: Double(rgb.greenComponent),
                blue: Double(rgb.blueComponent)))
    }
}
