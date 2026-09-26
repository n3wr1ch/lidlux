import AppKit
import SwiftUI

final class BiasMenuView: NSView {
    private let settings: Settings
    private let slider: NSSlider
    private let label = NSTextField(labelWithString: L10n.brightnessBias)

    init(settings: Settings) {
        self.settings = settings
        slider = NSSlider(value: settings.brightnessBias, minValue: -0.3, maxValue: 0.3, target: nil, action: nil)
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 86))
        label.frame = NSRect(x: 18, y: 59, width: 244, height: 20)
        slider.frame = NSRect(x: 18, y: 28, width: 244, height: 26)
        slider.target = self
        slider.action = #selector(changed)
        slider.isContinuous = true
        slider.setAccessibilityLabel(L10n.brightnessBias)
        addSubview(label)
        addSubview(slider)
        for (title, x) in [(L10n.darker, 18.0), (L10n.brighter, 226.0)] {
            let caption = NSTextField(labelWithString: title)
            caption.font = .systemFont(ofSize: 11)
            caption.textColor = .secondaryLabelColor
            caption.frame = NSRect(x: x, y: 8, width: 40, height: 16)
            addSubview(caption)
        }
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func changed() { settings.brightnessBias = slider.doubleValue }
    func refresh() {
        slider.doubleValue = settings.brightnessBias
        label.stringValue = L10n.brightnessBiasValue(settings.brightnessBias * 100)
    }
}

final class SettingsWindow: NSWindowController {
    init(controller: BrightnessController, external: ExternalBrightnessController, keys: BrightnessKeyTap) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 700),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = L10n.settingsTitle
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: SettingsView(settings: controller.settings, controller: controller, external: external, keys: keys))
        super.init(window: window)
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func present() {
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct SettingsView: View {
    @ObservedObject var settings: Settings
    let controller: BrightnessController
    @ObservedObject var external: ExternalBrightnessController
    @ObservedObject var keys: BrightnessKeyTap

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(L10n.brightnessBias).frame(width: 150, alignment: .leading)
                    Text(L10n.darker)
                    Slider(value: $settings.brightnessBias, in: -0.3...0.3).accessibilityLabel(L10n.brightnessBias)
                    Text(L10n.brighter)
                    Text(L10n.signedPercent(settings.brightnessBias * 100))
                        .monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                HStack {
                    Text(L10n.minimumBrightness).frame(width: 150, alignment: .leading)
                    Slider(value: $settings.minimumBrightness, in: 0...0.3).accessibilityLabel(L10n.minimumBrightness)
                    Text(L10n.percent(settings.minimumBrightness * 100))
                        .monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                Picker(L10n.responseSpeed, selection: $settings.responseSpeed) {
                    ForEach(Settings.ResponseSpeed.allCases) { speed in Text(speed.title).tag(speed) }
                }.pickerStyle(.segmented)
                Divider()
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            metric(L10n.currentLux, controller.lastLux.map { L10n.lux($0) } ?? L10n.noMeasurement)
                            Spacer()
                            metric(L10n.currentBrightness, controller.currentBrightness.map { L10n.percent(Double($0 * 100)) } ?? L10n.displayOff)
                        }
                        Text(settings.adjustmentDescription(at: controller.currentLogLux)).monospacedDigit()
                        CurvePreview(settings: settings, logLux: controller.currentLogLux)
                    }
                }
                Text(L10n.curveLegend)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.externalMonitor).font(.headline)
                    Toggle(L10n.adjustExternal, isOn: $settings.externalEnabled)
                    Toggle(L10n.brightnessKeys, isOn: $settings.brightnessKeysControlExternal)
                    HStack {
                        Text(keys.status).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button(L10n.openAccessibility) { keys.openAccessibilitySettings() }
                    }
                    HStack {
                        Text(L10n.brightnessBias)
                        Slider(value: $settings.externalBias, in: -0.3...0.3)
                            .accessibilityLabel(L10n.externalBrightnessBias)
                        Text(L10n.signedPercent(settings.externalBias * 100)).monospacedDigit()
                    }
                    HStack {
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            Text(settings.adjustmentDescription(at: controller.currentLogLux, external: true))
                                .font(.caption).monospacedDigit()
                        }
                        Spacer()
                        Button(L10n.resetExternalAdjustments) { external.resetOffset() }
                    }
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        CurvePreview(settings: settings, logLux: controller.currentLogLux, external: true)
                    }
                    if external.displays.isEmpty { Text(L10n.noDetectedExternalMonitors).foregroundStyle(.secondary) }
                    ForEach(external.displays) { display in Text(display.title).monospacedDigit() }
                    ForEach(external.conflictWarnings, id: \.self) { warning in
                        Text(warning).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(L10n.ddcHelp)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                HStack {
                    Button(L10n.resetAdjustments) { controller.resetOffset() }
                    Spacer()
                    Button(L10n.restoreDefaults) {
                        settings.restoreDefaults()
                        external.resetOffset()
                        controller.resetOffset()
                    }
                }
                Text(L10n.restoreHelp)
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(width: 560)
        }
        .frame(width: 560, height: 700)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }
    }
}

private struct CurvePreview: View {
    @ObservedObject var settings: Settings
    let logLux: Double?
    var external = false
    private var learned: LearnedCurve { external ? settings.externalLearnedPoints : settings.learnedPoints }
    private var maxLog: Double { max(log10(5001.0), learned.points.last?.x ?? 0, logLux ?? 0) }
    private func applied(_ x: Double) -> Double {
        external ? settings.externalAppliedBrightness(forLogLux: x) : Double(settings.appliedBrightness(forLogLux: x))
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width - 48
            let height = geometry.size.height - 32
            ZStack(alignment: .topLeading) {
                ForEach([0, 50, 100], id: \.self) { value in
                    let y = height * (1 - Double(value) / 100)
                    Text(L10n.percent(Double(value))).font(.caption2).position(x: 18, y: y)
                    Path { path in
                        path.move(to: CGPoint(x: 40, y: y))
                        path.addLine(to: CGPoint(x: 40 + width, y: y))
                    }.stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                }
                ForEach([0, 10, 100, 1000, 5000], id: \.self) { value in
                    Text(L10n.number(value)).font(.caption2)
                        .position(x: 40 + log10(Double(value) + 1) / maxLog * width, y: height + 12)
                }
                curve(width: width, height: height, applied: false)
                    .stroke(Color.gray, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                curve(width: width, height: height, applied: true)
                    .stroke(Color.accentColor, lineWidth: 2.5)
                ForEach(learned.points, id: \.x) { point in
                    Circle().stroke(Color.orange, lineWidth: 2).frame(width: 6, height: 6)
                        .position(x: 40 + point.x / maxLog * width, y: height * (1 - applied(point.x)))
                }
                if let logLux {
                    let x = min(maxLog, max(0, logLux))
                    Circle().fill(Color.accentColor).frame(width: 9, height: 9)
                        .position(x: 40 + x / maxLog * width,
                                  y: height * (1 - applied(x)))
                }
                Text(L10n.luxAxis).font(.caption2)
                    .position(x: 40 + width / 2, y: height + 28)
            }
        }
        .frame(height: 205)
        .padding(.top, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.curveAccessibility)
    }

    private func curve(width: CGFloat, height: CGFloat, applied: Bool) -> Path {
        Path { path in
            for index in 0...240 {
                let x = Double(index) / 240 * maxLog
                let brightness = applied ? self.applied(x) : Double(BrightnessController.baseBrightness(forLogLux: x))
                let point = CGPoint(x: 40 + x / maxLog * width, y: height * (1 - Double(brightness)))
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
    }
}
