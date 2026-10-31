import Testing
import AppKit
@_private(sourceFile: "CanvasController.swift") @testable import Expanse

@MainActor @Suite(.serialized) struct SmokeTests {
    @Test func fakeWindowsOnATestCanvas() {
        let a = Fake.window(id: 1, canvas: CGRect(x: 0, y: 33, width: 600, height: 400))
        let c = TestCanvas.make(windows: [a])
        #expect(c.viewport == CGRect(x: 0, y: 33, width: 1512, height: 949))
        #expect(c.windows.count == 1)
        #expect(a.pid == Fake.firstPID && a.appPID == Fake.firstPID)
        let sc = Fake.scWindow(id: 2, frame: CGRect(x: 100, y: 100, width: 400, height: 300))
        #expect(c.isManageable(sc, tracked: false, regular: { _ in true }))
        #expect(!c.isManageable(sc, tracked: false, regular: { _ in false }))
    }
}
