import AppKit
import SwiftUI

final class BiasMenuView: NSView {
    private let settings: Settings
    private let slider: NSSlider
    private let label = NSTextField(labelWithString: "밝기 성향")

    init(settings: Settings) {
        self.settings = settings
        slider = NSSlider(value: settings.brightnessBias, minValue: -0.3, maxValue: 0.3, target: nil, action: nil)
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 86))
        label.frame = NSRect(x: 18, y: 59, width: 244, height: 20)
        slider.frame = NSRect(x: 18, y: 28, width: 244, height: 26)
        slider.target = self
        slider.action = #selector(changed)
        slider.isContinuous = true
        slider.setAccessibilityLabel("밝기 성향")
        addSubview(label)
        addSubview(slider)
        for (title, x) in [("어둡게", 18.0), ("밝게", 226.0)] {
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
        label.stringValue = String(format: "밝기 성향  %+.0f%%", settings.brightnessBias * 100)
    }
}

final class SettingsWindow: NSWindowController {
    init(controller: BrightnessController, external: ExternalBrightnessController) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 700),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "LidLux 설정"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: SettingsView(settings: controller.settings, controller: controller, external: external))
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("밝기 성향").frame(width: 72, alignment: .leading)
                    Text("어둡게")
                    Slider(value: $settings.brightnessBias, in: -0.3...0.3).accessibilityLabel("밝기 성향")
                    Text("밝게")
                    Text(String(format: "%+.0f%%", settings.brightnessBias * 100))
                        .monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                HStack {
                    Text("최소 밝기").frame(width: 72, alignment: .leading)
                    Slider(value: $settings.minimumBrightness, in: 0...0.3).accessibilityLabel("최소 밝기")
                    Text(String(format: "%.0f%%", settings.minimumBrightness * 100))
                        .monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                Picker("반응 속도", selection: $settings.responseSpeed) {
                    ForEach(Settings.ResponseSpeed.allCases) { speed in Text(speed.title).tag(speed) }
                }.pickerStyle(.segmented)
                Divider()
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            metric("현재 조도", controller.lastLux.map { String(format: "%.0f lux", $0) } ?? "측정 없음")
                            Spacer()
                            metric("현재 밝기", controller.currentBrightness.map { String(format: "%.0f%%", $0 * 100) } ?? "디스플레이 꺼짐")
                            Spacer()
                            metric("학습된 보정값", String(format: "%+.0f%%", settings.offset * 100))
                        }
                        CurvePreview(settings: settings, lux: controller.lastLux)
                    }
                }
                Text("실선: 적용 곡선 · 회색 점선: 기본 곡선 (같으면 겹침)\n점: 현재 조도의 목표 밝기\n실제 화면 밝기는 반응 속도에 따라 부드럽게 이동합니다.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Text("외부 모니터").font(.headline)
                    Toggle("외부 모니터도 조절", isOn: $settings.externalEnabled)
                    HStack {
                        Text("밝기 성향")
                        Slider(value: $settings.externalBias, in: -0.3...0.3)
                            .accessibilityLabel("외부 모니터 밝기 성향")
                        Text(String(format: "%+.0f%%", settings.externalBias * 100)).monospacedDigit()
                    }
                    HStack {
                        Text(String(format: "학습된 보정값 %+.0f%%", settings.externalOffset * 100))
                        Spacer()
                        Button("외부 보정값 초기화") { external.resetOffset() }
                    }
                    if external.displays.isEmpty { Text("감지된 외부 모니터 없음").foregroundStyle(.secondary) }
                    ForEach(external.displays) { display in Text(display.title).monospacedDigit() }
                    ForEach(external.conflictWarnings, id: \.self) { warning in
                        Text(warning).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("모니터 OSD에서 DDC/CI를 켜세요. 보정값은 외부 모니터들이 공유합니다. 밝기는 마지막 읽기 또는 쓰기 기준입니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                HStack {
                    Button("보정값 초기화") { controller.resetOffset() }
                    Spacer()
                    Button("기본값으로 되돌리기") {
                        settings.restoreDefaults()
                        external.resetOffset()
                        controller.resetOffset()
                    }
                }
                Text("기본값 복원 시 자동 조절을 켜고 보정값과 밝기 설정을 초기화합니다.")
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
    let lux: Double?
    private let maxLog = log10(5001.0)

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width - 48
            let height = geometry.size.height - 32
            ZStack(alignment: .topLeading) {
                ForEach([0, 50, 100], id: \.self) { value in
                    let y = height * (1 - Double(value) / 100)
                    Text("\(value)%").font(.caption2).position(x: 18, y: y)
                    Path { path in
                        path.move(to: CGPoint(x: 40, y: y))
                        path.addLine(to: CGPoint(x: 40 + width, y: y))
                    }.stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                }
                ForEach([0, 10, 100, 1000, 5000], id: \.self) { value in
                    Text("\(value)").font(.caption2)
                        .position(x: 40 + log10(Double(value) + 1) / maxLog * width, y: height + 12)
                }
                curve(width: width, height: height, applied: false)
                    .stroke(Color.gray, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                curve(width: width, height: height, applied: true)
                    .stroke(Color.accentColor, lineWidth: 2.5)
                if let lux {
                    let x = min(maxLog, log10(max(0, lux) + 1))
                    Circle().fill(Color.accentColor).frame(width: 9, height: 9)
                        .position(x: 40 + x / maxLog * width,
                                  y: height * (1 - Double(settings.appliedBrightness(forLogLux: x))))
                }
                Text("조도 (lux, 로그 스케일)").font(.caption2)
                    .position(x: 40 + width / 2, y: height + 28)
            }
        }
        .frame(height: 205)
        .padding(.top, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("밝기 곡선 미리보기. 가로축 조도 0에서 5000 lux, 로그 스케일. 세로축 밝기 0에서 100퍼센트.")
    }

    private func curve(width: CGFloat, height: CGFloat, applied: Bool) -> Path {
        Path { path in
            for index in 0...240 {
                let x = Double(index) / 240 * maxLog
                let brightness = applied ? settings.appliedBrightness(forLogLux: x) : BrightnessController.baseBrightness(forLogLux: x)
                let point = CGPoint(x: 40 + x / maxLog * width, y: height * (1 - Double(brightness)))
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
    }
}
