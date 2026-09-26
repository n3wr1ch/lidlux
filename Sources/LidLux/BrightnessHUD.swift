import AppKit
import SwiftUI

final class BrightnessHUD {
    private let panel: NSPanel
    private var hideTimer: Timer?
    private var presentation = 0

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 240, height: 132),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
    }

    func show(level: Double, on screen: NSScreen) {
        presentation += 1
        let currentPresentation = presentation
        hideTimer?.invalidate()
        panel.contentView = NSHostingView(rootView: BrightnessHUDView(level: max(0, min(1, level))))
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.midX - 120, y: frame.minY + 54))
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        let timer = Timer(timeInterval: 1.2, repeats: false) { [weak self] _ in
            guard let self, self.presentation == currentPresentation else { return }
            let started = ProcessInfo.processInfo.systemUptime
            let fade = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
                guard let self, self.presentation == currentPresentation else { timer.invalidate(); return }
                let progress = (ProcessInfo.processInfo.systemUptime - started) / 0.2
                self.panel.alphaValue = max(0, 1 - progress)
                if progress >= 1 { timer.invalidate(); self.panel.orderOut(nil) }
            }
            self.hideTimer = fade
            RunLoop.main.add(fade, forMode: .common)
        }
        hideTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
}

private struct BrightnessHUDView: View {
    let level: Double
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "sun.max.fill").font(.system(size: 30))
            HStack(spacing: 3) {
                ForEach(0..<16) { index in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.primary.opacity(level * 16 > Double(index) ? 0.9 : 0.16))
                        .frame(width: 10, height: 9)
                }
            }
            Text("\(Int((level * 100).rounded()))%")
                .font(.system(size: 13, weight: .medium)).monospacedDigit()
        }
        .foregroundStyle(.primary)
        .frame(width: 240, height: 132)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("외부 모니터 밝기 \(Int((level * 100).rounded()))퍼센트")
    }
}
