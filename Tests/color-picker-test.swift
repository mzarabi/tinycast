import AppKit

@main
@MainActor
struct ColorPickerTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() {
        expect(ColorPickerCoordinator.hexString(for: .black) == "#000000", "black")
        expect(ColorPickerCoordinator.hexString(for: .white) == "#FFFFFF", "white")
        expect(
            ColorPickerCoordinator.hexString(
                for: NSColor(srgbRed: 163 / 255, green: 184 / 255, blue: 204 / 255, alpha: 1))
                == "#A3B8CC", "uppercase six-digit HEX")
        expect(
            ColorPickerCoordinator.hexString(
                for: NSColor(srgbRed: 0.5, green: 0, blue: 1, alpha: 0.2)) == "#8000FF",
            "channels round and alpha is omitted")
        let wide = NSColor(displayP3Red: 1, green: 0, blue: 0, alpha: 1)
        expect(ColorPickerCoordinator.hexString(for: wide) == "#FF0000", "P3 clips to sRGB")
        expect(
            ColorPickerCoordinator.hexString(
                for: NSColor(displayP3Red: 0.6, green: 0.4, blue: 0.2, alpha: 1)) != "#996633",
            "P3 components are converted, not relabeled as sRGB")
        expect(
            ColorPickerCoordinator.hexString(for: NSColor(white: 0.5, alpha: 1)) != nil,
            "grayscale converts to RGB")

        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("unchanged", forType: .string)
        var events: [String] = []
        var selection: (@MainActor (NSColor?) -> Void)?
        var copied: [String] = []
        var errors = 0
        let coordinator = ColorPickerCoordinator(
            hidePalette: { events.append("hide") },
            sample: { completion in
                events.append("sample")
                selection = completion
            },
            pasteboard: pasteboard,
            showCopied: { copied.append($0) },
            showFailure: { errors += 1 })

        coordinator.pickColor()
        expect(events == ["hide", "sample"], "palette hides before sampling")
        coordinator.pickColor()
        expect(events.count == 2, "repeated command cannot overlap sampling")
        selection?(nil)
        expect(pasteboard.string(forType: .string) == "unchanged", "cancel preserves clipboard")
        expect(copied.isEmpty && errors == 0, "cancel is silent")

        coordinator.pickColor()
        expect(events.count == 4, "can sample again after cancellation")
        selection?(NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        expect(pasteboard.string(forType: .string) == "#FF0000", "selection copies HEX")
        expect(copied == ["#FF0000"], "success reports copied color")
        expect(errors == 0, "valid selection reports no failure")
        coordinator.pickColor()
        expect(events.count == 6, "can sample again after success")
        selection?(nil)

        coordinator.pickColor()
        let beforeFailure = pasteboard.changeCount
        selection?(NSColor(patternImage: NSImage(size: NSSize(width: 1, height: 1))))
        expect(errors == 1, "unsupported color reports failure")
        expect(pasteboard.changeCount == beforeFailure, "conversion failure preserves clipboard")
        expect(copied == ["#FF0000"], "conversion failure never reports success")

        print("Color picker: \(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
