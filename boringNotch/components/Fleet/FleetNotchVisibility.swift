//
//  FleetNotchVisibility.swift
//  boringNotch
//
//  Mirrors the notch window's real visibility into SwiftUI.
//

import AppKit
import SwiftUI

/// Mirrors the hosting window's real on-screen state into SwiftUI: false while the window is
/// occluded, hidden or faded out.
struct FleetNotchVisibility: NSViewRepresentable {
    @Binding var isVisible: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(binding: $isVisible)
    }

    func makeNSView(context: Context) -> NSView {
        let view = FleetNotchVisibilityView()
        context.coordinator.view = view
        view.onChange = { [weak coordinator = context.coordinator] visible in
            coordinator?.report(visible)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.binding = $isVisible
        (nsView as? FleetNotchVisibilityView)?.refresh()
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.view?.teardown()
        coordinator.view = nil
    }

    @MainActor
    final class Coordinator {
        var binding: Binding<Bool>
        fileprivate var view: FleetNotchVisibilityView?

        init(binding: Binding<Bool>) {
            self.binding = binding
        }

        /// Writes on the next run loop turn: the first report arrives while SwiftUI is still
        /// building the view, and writing state mid-update makes SwiftUI warn.
        func report(_ visible: Bool) {
            Task { @MainActor in
                if self.binding.wrappedValue != visible {
                    self.binding.wrappedValue = visible
                }
            }
        }
    }
}

private final class FleetNotchVisibilityView: NSView {
    var onChange: ((Bool) -> Void)?
    private var last: Bool?
    private var timer: Timer?

    private var windowIsVisible: Bool {
        guard let window, window.isVisible, !window.isMiniaturized else { return false }
        return window.alphaValue > 0.01 && window.occlusionState.contains(.visible)
    }

    private func report() {
        let visible = windowIsVisible
        guard visible != last else { return }
        last = visible
        onChange?(visible)
    }

    /// Re-reads the window and reports it. The coordinator skips writes that match the binding,
    /// so a binding reset elsewhere gets corrected without a write on every SwiftUI update.
    func refresh() {
        let visible = windowIsVisible
        last = visible
        onChange?(visible)
    }

    func teardown() {
        NotificationCenter.default.removeObserver(self)
        timer?.invalidate()
        timer = nil
        onChange = nil
    }

    override func viewDidMoveToWindow() {
        NotificationCenter.default.removeObserver(self)
        timer?.invalidate()
        timer = nil

        guard let window else { return }

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(recheck), name: NSWindow.didChangeOcclusionStateNotification, object: window)
        center.addObserver(self, selector: #selector(recheck), name: NSWindow.didMiniaturizeNotification, object: window)
        center.addObserver(self, selector: #selector(recheck), name: NSWindow.didDeminiaturizeNotification, object: window)
        center.addObserver(self, selector: #selector(recheck), name: NSApplication.didHideNotification, object: nil)
        center.addObserver(self, selector: #selector(recheck), name: NSApplication.didUnhideNotification, object: nil)

        // The app hides a display's notch window with `window.alphaValue = 0`, which posts no
        // notification, so the probe re-reads the window twice a second. The timer only exists
        // while the hole is drawn (the hole is built only while the fleet works), so an idle
        // notch ticks nothing. The block holds self weakly: a strong target would retain the
        // view through the run loop and nothing could ever stop the timer.
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.recheck() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        report()
    }

    @objc private func recheck() {
        report()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        timer?.invalidate()
    }
}
