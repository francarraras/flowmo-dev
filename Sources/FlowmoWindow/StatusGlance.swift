import AppKit
import Combine
import FlowmoCore
import FlowmoLook
import SwiftUI

/// Menu-bar clock. The window stays the product; this is a glance when it is hidden.
@MainActor
final class StatusGlance {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var cancellable: AnyCancellable?
    private var timer: Timer?
    private weak var controller: FlowmoSessionController?
    private var showWindow: () -> Void = {}

    func attach(controller: FlowmoSessionController, showWindow: @escaping () -> Void) {
        self.controller = controller
        self.showWindow = showWindow
        item.button?.target = self
        item.button?.action = #selector(clicked)
        item.button?.toolTip = "Flowmo"
        cancellable = controller.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        timer?.invalidate()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh()
    }

    func refresh() {
        guard let controller else { return }
        let status = controller.status
        let atmo = Atmosphere.canvas
        let ink: Color = status.isPaused ? atmo.faint : (status.isIdle ? atmo.mute : atmo.ink)
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        item.button?.attributedTitle = NSAttributedString(
            string: Format.glance(status),
            attributes: [
                .font: font,
                .foregroundColor: NSColor(ink),
            ]
        )
    }

    @objc private func clicked() {
        showWindow()
    }
}
