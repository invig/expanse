import AppKit

/// Questions for the person running the tests, in a small panel at the top of the screen that
/// stays above the canvas and doesn't take focus from the app you're testing.
@MainActor final class Human {
    /// Unattended runs (--auto) never ask: cases that would are skipped before they start.
    var present = true
    /// The case being asked about, shown in the panel.
    var caseLabel = ""

    func ask(_ text: String, buttons: [String]) async -> Int {
        guard present else { return buttons.count - 1 }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 10),
                            styleMask: [.titled, .nonactivatingPanel, .utilityWindow, .hudWindow], backing: .buffered, defer: false)
        panel.title = "Expanse Tests — \(caseLabel)"
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false

        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 14)
        label.preferredMaxLayoutWidth = 520
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        let stack = NSStackView(views: [label, row])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)

        return await withCheckedContinuation { (done: CheckedContinuation<Int, Never>) in
            var answered = false
            for (i, title) in buttons.enumerated() {
                let b = ClosureButton(title: title) {
                    guard !answered else { return }
                    answered = true
                    panel.orderOut(nil)
                    done.resume(returning: i)
                }
                if i == 0 { b.keyEquivalent = "\r" }
                row.addArrangedSubview(b)
            }
            panel.contentView = stack
            panel.setContentSize(stack.fittingSize)
            if let screen = NSScreen.screens.first {
                let f = screen.visibleFrame
                panel.setFrameTopLeftPoint(NSPoint(x: f.midX - panel.frame.width / 2, y: f.maxY - 8))
            }
            panel.orderFrontRegardless()
            NSSound.beep()
        }
    }
}

private final class ClosureButton: NSButton {
    private var action_: () -> Void = {}

    convenience init(title: String, _ action: @escaping () -> Void) {
        self.init(frame: .zero)
        self.title = title
        bezelStyle = .rounded
        action_ = action
        target = self
        self.action = #selector(fire)
    }

    @objc private func fire() { action_() }
}
