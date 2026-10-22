import SwiftUI
import AppKit

/// Resizes the window when the layout mode changes. Everything else about the window is system default.
struct WindowSizer: NSViewRepresentable {
    let mode: AppLayoutMode

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        let mode = mode
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            context.coordinator.apply(mode: mode, to: window)
        }
    }

    @MainActor
    final class Coordinator {
        private var appliedMode: AppLayoutMode?

        func apply(mode: AppLayoutMode, to window: NSWindow) {
            guard appliedMode != mode else { return }
            let isFirst = appliedMode == nil
            appliedMode = mode

            window.minSize = mode.minSize

            let screen = window.screen?.visibleFrame
                ?? NSScreen.main?.visibleFrame
                ?? NSRect(x: 0, y: 0, width: 1512, height: 982)
            let width = min(mode.targetSize.width, screen.width - 20)
            let height = min(mode.targetSize.height, screen.height - 20)

            let current = window.frame
            var x = current.midX - width / 2
            var y = current.midY - height / 2
            x = max(screen.minX + 10, min(x, screen.maxX - width - 10))
            y = max(screen.minY + 10, min(y, screen.maxY - height - 10))

            window.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true, animate: !isFirst)
            if isFirst { window.center() }
        }
    }
}
