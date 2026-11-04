import Testing
import AppKit
import SwiftUI
@_private(sourceFile: "CanvasController.swift") @testable import Expanse
@_private(sourceFile: "CanvasView.swift") @testable import Expanse
@_private(sourceFile: "Minimap.swift") @testable import Expanse
@_private(sourceFile: "SpacesBar.swift") @testable import Expanse
@_private(sourceFile: "GlassPanel.swift") @testable import Expanse
@_private(sourceFile: "MenuPanel.swift") @testable import Expanse
@_private(sourceFile: "AppDelegate.swift") @testable import Expanse
@_private(sourceFile: "ManagedWindow.swift") @testable import Expanse
@_private(sourceFile: "LayoutStore.swift") @testable import Expanse
@_private(sourceFile: "HotCorner.swift") @testable import Expanse
@_private(sourceFile: "Wallpaper.swift") @testable import Expanse

/// docs/regression/panels-and-look.md
@MainActor @Suite("UI: Menu bar panel, minimap, Settings and the backdrop", .serialized) struct UITests {

    // MARK: Helpers

    /// Values of type `T` anywhere inside `value` (a SwiftUI view, say), found by reflection.
    static func reflected<T>(_ type: T.Type, in value: Any) -> [T] {
        var found: [T] = []
        var seen = Set<ObjectIdentifier>()
        func walk(_ v: Any, _ depth: Int) {
            guard depth < 80 else { return }
            if let t = v as? T { found.append(t) }
            let mirror = Mirror(reflecting: v)
            if mirror.displayStyle == .class, !seen.insert(ObjectIdentifier(v as AnyObject)).inserted { return }
            var m: Mirror? = mirror
            while let current = m {
                for child in current.children { walk(child.value, depth + 1) }
                m = current.superclassMirror
            }
        }
        walk(value, 0)
        return found
    }

    /// Every string inside `value`, with non-breaking spaces as plain ones.
    static func strings(in value: Any) -> [String] {
        reflected(String.self, in: value).map { $0.replacingOccurrences(of: "\u{00A0}", with: " ") }
    }

    /// The stored properties, by name, of the first value inside `value` that has one called `field`.
    static func record(with field: String, in value: Any) -> [String: Any]? {
        var result: [String: Any]?
        func walk(_ v: Any, _ depth: Int) {
            guard result == nil, depth < 80 else { return }
            let mirror = Mirror(reflecting: v)
            if mirror.children.contains(where: { $0.label == field }) {
                result = Dictionary(mirror.children.compactMap { c in c.label.map { ($0, c.value) } }, uniquingKeysWith: { a, _ in a })
                return
            }
            for child in mirror.children { walk(child.value, depth + 1) }
        }
        walk(value, 0)
        return result
    }

    /// In the colour space NSColor(white:alpha:) uses.
    static func gray(_ c: CGColor?) -> (white: CGFloat, alpha: CGFloat)? {
        guard let c, let n = NSColor(cgColor: c)?.usingColorSpace(.genericGamma22Gray) else { return nil }
        return (n.whiteComponent, n.alphaComponent)
    }

    static func luminance(_ c: CGColor?) -> CGFloat? {
        guard let c, let n = NSColor(cgColor: c)?.usingColorSpace(.sRGB) else { return nil }
        return 0.2126 * n.redComponent + 0.7152 * n.greenComponent + 0.0722 * n.blueComponent
    }

    static func resolved(_ color: NSColor, in appearance: NSAppearance) -> CGColor {
        var c: CGColor = color.cgColor
        appearance.performAsCurrentDrawingAppearance { c = color.cgColor }
        return c
    }

    static let light = NSAppearance(named: .aqua)!
    static let dark = NSAppearance(named: .darkAqua)!

    static func image() -> CGImage {
        let ctx = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        return ctx.makeImage()!
    }

    /// A canvas on the laptop display, laid out (the minimap and Spaces panel placed).
    static func canvas(windows: [ManagedWindow] = []) -> CanvasController {
        let c = TestCanvas.make(windows: windows)
        c.view.layoutSubtreeIfNeeded()
        return c
    }

    /// The same, drawn once into its window's backing store (the window stays off screen), so
    /// the glass panels have the layers they have in the app.
    static func drawnCanvas() -> CanvasController {
        let c = canvas()
        c.view.window?.displayIfNeeded()
        return c
    }

    /// The menu bar panel's SwiftUI content for this state.
    private static func panelView(_ state: MenuPanel.State, perform: @escaping (MenuPanel.Action) -> Void = { _ in }) -> PanelView {
        _ = NSApplication.shared
        let model = MenuPanel.Model()
        model.state = state
        model.perform = perform
        return PanelView(model: model)
    }

    static func spaces(_ n: Int) -> [Spaces.Space] {
        (0..<n).map { i in
            i == 0 ? Spaces.Space(id: 100, pid: nil, window: nil, name: "Expanse")
                : Spaces.Space(id: UInt64(100 + i), pid: getpid(), window: nil, name: "App \(i)")
        }
    }

    // MARK: Cases

    @Test("UI-01 The minimap shows every window, the view and the zoom (logic)") func ui01() {
        let a = Fake.window(id: 1, canvas: CGRect(x: 0, y: 0, width: 800, height: 600))
        let b = Fake.window(id: 2, canvas: CGRect(x: 2000, y: 900, width: 600, height: 400))
        let c = Self.canvas(windows: [a, b])
        let v = c.view
        // 16pt in from the bottom-right corner.
        #expect(v.minimapGlass.frame == CGRect(x: v.bounds.maxX - Minimap.size.width - 16, y: 16,
                                               width: Minimap.size.width, height: Minimap.size.height))
        c.camera.scale = 0.42
        v.render()
        #expect(v.minimap.zoomText.string as? String == "42%")
        // Follows a pan: the viewport outline moves with the camera, and a point on the map
        // maps back to the canvas point it shows.
        let before = v.minimap.viewportShape.path?.boundingBox
        c.camera.origin.x += 400
        v.render()
        #expect(v.minimap.viewportShape.path?.boundingBox != before)
        let mid = v.minimap.viewportFill.path!.boundingBox
        let centre = v.minimap.canvasPoint(at: CGPoint(x: mid.midX, y: mid.midY))
        let shown = c.visibleCanvas
        #expect(abs(centre.x - shown.midX) < 2 && abs(centre.y - shown.midY) < 2)
    }

    @Test("UI-02 The hovered window is outlined (logic)", arguments: [CGFloat(1), 0.5, 0.2, 0.08])
    func ui02(scale: CGFloat) {
        let node = WindowNode()
        node.place(canvasFrame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let rect = CGRect(x: 0, y: 0, width: 800 * scale, height: 600 * scale)
        node.style(scale: scale, hovered: true, selected: false, showsClose: true, visible: true, screenRect: rect)
        #expect(abs(node.highlight.borderWidth * scale - 2) < 0.0001)
        node.style(scale: scale, hovered: true, selected: true, showsClose: true, visible: true, screenRect: rect)
        #expect(abs(node.highlight.borderWidth * scale - 3) < 0.0001)
        node.style(scale: scale, hovered: false, selected: false, showsClose: false, visible: true, screenRect: rect)
        #expect(node.highlight.borderWidth == 0)
    }

    @Test("UI-03 Plain canvas background follows light and dark mode (logic)") func ui03() throws {
        let c = Self.canvas()
        let v = c.view
        c.isActive = true
        defer { c.isActive = false }
        v.appearance = Self.light
        v.applyAppearance()
        let lightGrey = try #require(Self.gray(v.layer?.backgroundColor))
        #expect(abs(lightGrey.white - 0.85) < 0.01)
        v.appearance = Self.dark
        v.viewDidChangeEffectiveAppearance()
        let darkGrey = try #require(Self.gray(v.layer?.backgroundColor))
        #expect(abs(darkGrey.white - 0.13) < 0.01)
    }

    @Test("UI-05 Expanse lives in the menu bar, not the Dock") func ui05() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Resources/Info.plist"))
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(plist["LSUIElement"] as? Bool == true)
    }

    @Test("UI-06 Window names are hidden unless turned on") func ui06a() {
        Env.withDefaults(["showWindowNames": nil]) {
            let w = Fake.window(id: 1, appName: "Notes", title: "Groceries", canvas: CGRect(x: 0, y: 0, width: 600, height: 400))
            let c = Self.canvas(windows: [w])
            c.view.render()
            #expect(!CanvasView.showsNames)
            #expect(c.view.labels.isHidden)
            // The panel's switch, kept for the next start.
            CanvasView.showsNames = true
            #expect(UserDefaults.standard.bool(forKey: "showWindowNames"))
            c.view.render()
            #expect(!c.view.labels.isHidden)
            CanvasView.showsNames = false
            c.view.render()
            #expect(c.view.labels.isHidden)
        }
    }

    @Test("UI-06 Each window is named by its app; the hovered one shows its title") func ui06b() {
        let a = Fake.window(id: 1, appName: "Notes", title: "Groceries", canvas: CGRect(x: 0, y: 0, width: 600, height: 400))
        let b = Fake.window(id: 2, appName: "Safari", title: "", canvas: CGRect(x: 700, y: 0, width: 600, height: 400))
        let c = Self.canvas(windows: [a, b])
        #expect(a.node.label.string as? String == "Notes")
        c.view.highlight(a)
        #expect(a.node.label.string as? String == "Notes — Groceries")
        c.view.highlight(b)
        #expect(a.node.label.string as? String == "Notes")
        #expect(b.node.label.string as? String == "Safari")
    }

    @Test("UI-07 The canvas shows the real desktop picture (logic)") func ui07() {
        Env.withDefaults([Wallpaper.defaultsKey: nil]) {
            // On by default; off is a plain background.
            #expect(Wallpaper.enabled)
            Wallpaper.enabled = false
            #expect(!Wallpaper.enabled)
            Wallpaper.enabled = true
            #expect(Wallpaper.enabled)
        }
        let c = Self.canvas()
        c.view.setWallpaper(Self.image())
        c.isActive = true
        c.view.render()
        #expect(!c.view.wallpaper.isHidden)
        // Lined up with the real desktop: it runs up under the menu bar.
        #expect(c.view.wallpaper.frame.height == c.view.bounds.height + c.view.menuBarHeight)
        #expect(c.view.menuBarHeight == TestDisplay.laptop.menuBar)
        c.view.setWallpaper(nil)
        #expect(c.view.wallpaper.isHidden)
        c.isActive = false
    }

    @Test("UI-09 Window names over the desktop picture are white with a shadow") func ui09() throws {
        let w = Fake.window(id: 1, canvas: CGRect(x: 0, y: 0, width: 600, height: 400))
        let c = Self.canvas(windows: [w])
        let v = c.view
        let label = w.node.label

        v.setWallpaper(Self.image())
        let white = try #require(Self.gray(label.foregroundColor))
        #expect(white.white > 0.99 && white.alpha > 0.9)
        #expect(label.shadowOpacity > 0.5)
        #expect((Self.gray(label.shadowColor)?.white ?? 1) < 0.01)

        v.setWallpaper(nil)
        v.appearance = Self.light
        v.styleLabel(label)
        let onLight = try #require(Self.gray(label.foregroundColor))
        #expect(abs(onLight.white - 0.3) < 0.01)
        #expect(label.shadowOpacity == 0)

        v.appearance = Self.dark
        v.styleLabel(label)
        let onDark = try #require(Self.gray(label.foregroundColor))
        #expect(abs(onDark.white - 0.7) < 0.01)
        #expect(label.shadowOpacity == 0)
    }

    @Test("UI-10 Picking the hot corner in the panel (logic)") func ui10() {
        // The pick leaves the panel open, and is kept for the next start.
        #expect(!MenuPanel.Action.corner(.topRight).closesPanel)
        Env.withDefaults([HotCorner.defaultsKey: nil]) {
            #expect(HotCorner().corner == .all)
            let corner = HotCorner()
            corner.corner = .topRight
            #expect(HotCorner().corner == .topRight)
            corner.corner = .off
            #expect(HotCorner().corner == .off)
        }
    }

    @Test("UI-11 Welcome and Quit from the panel's footer (logic)") func ui11() {
        for action in [MenuPanel.Action.welcome, .quit] {
            #expect(action.closesPanel)
            #expect(!action.needsCanvas)
        }
    }

    @Test("UI-14 A banner in the panel when an update is ready (logic)") func ui14() throws {
        var state = MenuPanel.State(isOn: true)
        #expect(Self.reflected(Banner.self, in: Self.panelView(state).body).isEmpty)
        state.update = "0.2.0"
        var performed: [String] = []
        let banners = Self.reflected(Banner.self, in: Self.panelView(state) { performed.append("\($0)") }.body)
        let banner = try #require(banners.first)
        #expect(banner.title == "Expanse 0.2.0 is ready")
        #expect(banner.detail == "It relaunches, and your windows stay where they are.")
        #expect(banner.button == "Install and Relaunch")
        banner.action()
        #expect(performed == ["installUpdate"])
        #expect(MenuPanel.Action.installUpdate.closesPanel)
    }

    @Test("UI-15 A clicked Spaces tile doesn't stay lit", .enabled(if: Spaces.list().active != nil, "needs the window server's Spaces"))
    func ui15() throws {
        // The tile clicked is the Space you're on, so the switch itself has nothing to do.
        let active = try #require(Spaces.list().active)
        let spaces = [Spaces.Space(id: active, pid: nil, window: nil, name: "Expanse"),
                      Spaces.Space(id: active &+ 7_777, pid: getpid(), window: nil, name: "Safari")]
        let c = Self.drawnCanvas()
        let v = c.view
        v.updateSpaces(spaces, active: active)
        v.layoutSubtreeIfNeeded()
        let tile = v.spacesBar.tiles[0].frame
        let root = try #require(v.layer)
        let p = root.convert(CGPoint(x: tile.midX, y: tile.midY), from: v.spacesBar)
        let click = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: p, modifierFlags: [], timestamp: 0,
                                                     windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        #expect(v.spacesBarHit(click).tile == 0)

        // At 100%.
        v.spacesBar.hovered = 0
        v.mouseDown(with: click)
        #expect(v.spacesBar.hovered == nil)
        #expect(v.spacesBar.rings[0].isHidden == false)   // the current Space's own ring stays

        // Zoomed out: the click leaves the canvas (cut short here).
        c.isActive = true
        v.spacesBar.hovered = 0
        v.mouseDown(with: click)
        #expect(v.spacesBar.hovered == nil)
        c.cancelAnimation()
        c.isActive = false
    }

    @Test("UI-18 The minimap and Spaces panel stay under the windows during a glide") func ui18() throws {
        let c = Self.drawnCanvas()
        let v = c.view
        let minimap = try #require(v.minimapGlass.layer)
        let spaces = try #require(v.spacesGlass.layer)
        c.gliding = true
        v.render()
        #expect(minimap.zPosition == -1)
        #expect(spaces.zPosition == -1)
        // Still above the desktop picture's copy.
        #expect(v.wallpaper.zPosition < minimap.zPosition)
        c.gliding = false
        v.render()
        #expect(minimap.zPosition == 0)
        #expect(spaces.zPosition == 0)
    }

    @Test("UI-19 Minimap and Spaces panels are glass that follows light and dark") func ui19a() throws {
        let map = Minimap()
        map.applyAppearance(Self.light)
        map.update(windows: [CGRect(x: 0, y: 0, width: 800, height: 600)], viewport: CGRect(x: 0, y: 0, width: 400, height: 300), scale: 0.5)
        let lightTitle = try #require(Self.luminance(map.title.foregroundColor))
        let lightZoom = try #require(Self.luminance(map.zoomText.foregroundColor))
        let lightBlocks = try #require(Self.luminance(map.windowsShape.fillColor))
        #expect(lightTitle < 0.3 && lightZoom < 0.3 && lightBlocks < 0.3)

        // Straight away when the appearance changes.
        map.applyAppearance(Self.dark)
        let darkTitle = try #require(Self.luminance(map.title.foregroundColor))
        let darkZoom = try #require(Self.luminance(map.zoomText.foregroundColor))
        let darkBlocks = try #require(Self.luminance(map.windowsShape.fillColor))
        #expect(darkTitle > 0.7 && darkZoom > 0.7 && darkBlocks > 0.7)

        let bar = SpacesBar()
        bar.update(spaces: Self.spaces(2), active: 100, wallpaper: nil)
        bar.applyAppearance(Self.light)
        #expect(try #require(Self.luminance(bar.heading.foregroundColor)) < 0.3)
        #expect(bar.labels.allSatisfy { (Self.luminance($0.foregroundColor) ?? 1) < 0.3 })
        bar.applyAppearance(Self.dark)
        #expect(try #require(Self.luminance(bar.heading.foregroundColor)) > 0.7)
        #expect(bar.labels.allSatisfy { (Self.luminance($0.foregroundColor) ?? 0) > 0.7 })
    }

    @Test("UI-19 The panels' glass: 22pt corners, and clicks go through to the canvas (logic)") func ui19b() {
        #expect(GlassPanel.radius == 22)
        let glass = GlassPanel(content: CALayer()) { _ in }
        glass.frame = CGRect(x: 0, y: 0, width: 208, height: 136)
        #expect(glass.hitTest(CGPoint(x: 100, y: 60)) == nil)
    }

    @Test("UI-20 The Spaces panel marks the current Space with a ring") func ui20a() throws {
        let bar = SpacesBar()
        bar.applyAppearance(Self.light)
        bar.update(spaces: Self.spaces(3), active: 100, wallpaper: Self.image())
        #expect(!bar.isHidden)
        #expect(bar.labels.map { $0.string as? String } == ["Expanse", "App 1", "App 2"])

        // The current Space: an accent ring set outside the tile, its name bold.
        let ring = bar.rings[0], tile = bar.tiles[0]
        #expect(!ring.isHidden)
        #expect(ring.borderWidth == 2.5)
        #expect(ring.borderColor == Self.resolved(.controlAccentColor, in: Self.light))
        #expect(ring.frame.contains(tile.frame) && ring.frame != tile.frame)
        let semibold = NSFont.systemFont(ofSize: 11, weight: .semibold).fontName
        let regular = NSFont.systemFont(ofSize: 11, weight: .regular).fontName
        #expect((bar.labels[0].font as? NSFont)?.fontName == semibold)
        #expect(bar.labels[1...].allSatisfy { ($0.font as? NSFont)?.fontName == regular })
        // The others: no ring, and not dimmed.
        #expect(bar.rings[1].isHidden && bar.rings[2].isHidden)
        #expect(bar.tiles.allSatisfy { $0.opacity == 1 })

        // Hovered: a thin grey ring.
        bar.hovered = 2
        #expect(!bar.rings[2].isHidden)
        #expect(bar.rings[2].borderWidth == 1.5)
        #expect(bar.rings[2].borderColor != Self.resolved(.controlAccentColor, in: Self.light))
        #expect(bar.rings[1].isHidden)
        bar.hovered = nil
        #expect(bar.rings[2].isHidden)

        // A full-screen app's tile: its icon, lifted, on a quiet well; corners follow the panel's.
        let app = bar.tiles[1]
        #expect(Self.gray(app.backgroundColor).map { $0.alpha < 0.2 } == true)
        let icon = try #require(app.sublayers?.first)
        #expect(icon.frame.size == CGSize(width: 36, height: 36))
        #expect(icon.shadowOpacity > 0)
        #expect(bar.tiles.allSatisfy { $0.cornerRadius == GlassPanel.radius - 14 })
    }

    @Test("UI-20 With a single Space the Spaces panel is hidden") func ui20b() {
        let bar = SpacesBar()
        bar.update(spaces: Self.spaces(1), active: 100, wallpaper: nil)
        #expect(bar.isHidden)
        bar.update(spaces: Self.spaces(2), active: 100, wallpaper: nil)
        #expect(!bar.isHidden)
        // And on the canvas, its glass goes with it.
        let c = Self.canvas()
        c.view.updateSpaces(Self.spaces(1), active: 100)
        #expect(c.view.spacesGlass.isHidden)
        c.view.updateSpaces(Self.spaces(2), active: 100)
        #expect(!c.view.spacesGlass.isHidden)
    }

    @Test("UI-21 Minimap header shows the name and the zoom on one row") func ui21() throws {
        let map = Minimap()
        map.update(windows: [CGRect(x: 0, y: 0, width: 800, height: 600)], viewport: CGRect(x: 0, y: 0, width: 1512, height: 949), scale: 0.35)
        #expect(map.title.string as? String == "Expanse")
        #expect(map.title.fontSize == 11)
        #expect((map.title.font as? NSFont)?.fontName == NSFont.systemFont(ofSize: 11, weight: .semibold).fontName)
        #expect(map.zoomText.string as? String == "35%")
        map.update(windows: [CGRect(x: 0, y: 0, width: 800, height: 600)], viewport: CGRect(x: 0, y: 0, width: 1512, height: 949), scale: 0.5)
        #expect(map.zoomText.string as? String == "50%")
        // One row: name on the left, zoom on the right, level with the Spaces panel's heading.
        #expect(map.title.frame.minY == map.zoomText.frame.minY)
        #expect(map.title.frame.minX < map.zoomText.frame.minX)
        #expect(map.zoomText.alignmentMode == .right)
        let bar = SpacesBar()
        bar.update(spaces: Self.spaces(2), active: 100, wallpaper: nil)
        #expect(bar.heading.frame.minY == map.title.frame.minY)
        // The map below it, 14pt in from the edges.
        #expect(map.mapArea.minX == 14)
        #expect(Minimap.size.width - map.mapArea.maxX == 14)
        #expect(map.mapArea.maxY < map.title.frame.minY)
    }

    @Test("UI-22 Minimap viewport: an accent ring, or a quiet outline when it frames everything") func ui22() throws {
        let map = Minimap()
        map.applyAppearance(Self.light)
        let accent = Self.resolved(.controlAccentColor, in: Self.light)

        // Fit: the view frames everything.
        let windows = [CGRect(x: 100, y: 100, width: 600, height: 400), CGRect(x: 800, y: 300, width: 500, height: 400)]
        map.update(windows: windows, viewport: CGRect(x: 0, y: 0, width: 1500, height: 900), scale: 0.6)
        #expect(map.viewportFill.isHidden)
        #expect(map.viewportShape.lineWidth == 1)
        #expect(map.viewportShape.strokeColor != accent)

        // 100%, on one window among several spread out.
        let spread = (0..<10).map { CGRect(x: CGFloat($0 % 5) * 1700, y: CGFloat($0 / 5) * 1100, width: 1200, height: 800) }
        map.update(windows: spread, viewport: CGRect(x: 0, y: 0, width: 1512, height: 949), scale: 1)
        #expect(!map.viewportFill.isHidden)
        #expect(map.viewportShape.lineWidth == 2)
        #expect(map.viewportShape.strokeColor == accent)
        // The ring stands 3pt off the tint (and the blocks) inside it.
        let tint = try #require(map.viewportFill.path?.boundingBox)
        let ring = try #require(map.viewportShape.path?.boundingBox)
        #expect(abs(tint.minX - ring.minX - 3) < 0.01 && abs(ring.maxX - tint.maxX - 3) < 0.01)
        #expect(abs(tint.minY - ring.minY - 3) < 0.01 && abs(ring.maxY - tint.maxY - 3) < 0.01)
        // Under the blocks: the tint is the bottom layer, the ring the top.
        let order = map.sublayers ?? []
        let fillAt = try #require(order.firstIndex { $0 === map.viewportFill })
        let blocksAt = try #require(order.firstIndex { $0 === map.windowsShape })
        let ringAt = try #require(order.firstIndex { $0 === map.viewportShape })
        #expect(fillAt < blocksAt && blocksAt < ringAt)

        // Zoomed right in among many windows: never smaller than about 20×13.
        let many = (0..<200).map { CGRect(x: CGFloat($0 % 20) * 3000, y: CGFloat($0 / 20) * 2000, width: 1200, height: 800) }
        map.update(windows: many, viewport: CGRect(x: 0, y: 0, width: 300, height: 190), scale: 5)
        let tiny = try #require(map.viewportFill.path?.boundingBox)
        #expect(tiny.width >= 20 - 0.01 && tiny.height >= 13 - 0.01)

        // Window blocks: a thin seam keeps overlapping windows apart.
        #expect(map.windowsShape.lineWidth > 0 && map.windowsShape.lineWidth <= 1)
        #expect(map.windowsShape.strokeColor != nil)
    }

    @Test("UI-26 The canvas and a glide still draw their own copy of the desktop (logic)") func ui26() throws {
        let c = Self.canvas()
        let v = c.view
        v.setWallpaper(Self.image())
        // At 100%: see-through, the real desktop shows.
        v.render()
        #expect(v.wallpaper.isHidden)
        #expect(Self.gray(v.layer?.backgroundColor)?.alpha == 0)
        // Zoomed out (or gliding, which raises the canvas the same way): opaque, its own copy.
        c.isActive = true
        v.render()
        #expect(!v.wallpaper.isHidden)
        #expect(Self.gray(v.layer?.backgroundColor)?.alpha == 1)
        // With the desktop picture off: plain grey.
        v.setWallpaper(nil)
        #expect(v.wallpaper.isHidden)
        #expect(Self.gray(v.layer?.backgroundColor)?.alpha == 1)
        c.isActive = false
    }

    @Test("UI-30 The panel's status line (logic)") func ui30() {
        let r = CGRect(x: 0, y: 0, width: 10, height: 10)
        #expect(Self.panelView(MenuPanel.State(isOn: true, windows: [r, r, r])).status == "On · 3 windows on the canvas")
        #expect(Self.panelView(MenuPanel.State(isOn: true, windows: [r])).status == "On · 1 window on the canvas")
        #expect(Self.panelView(MenuPanel.State(isOn: false, windows: [r, r, r])).status == "Starts once the walkthrough is done")
    }

    @Test("UI-32 The panel's minimap opens the canvas and stays live (logic)") func ui32() {
        let r = CGRect(x: 0, y: 0, width: 10, height: 10)
        let open = Self.strings(in: Self.panelView(MenuPanel.State(isOn: true, windows: [r])).hero)
        #expect(open.contains("Open Expanse") && open.contains("⌥") && open.contains("`"))
        let back = Self.strings(in: Self.panelView(MenuPanel.State(isOn: true, isActive: true, windows: [r])).hero)
        #expect(back.contains("Back to 100%"))
        let paused = Self.strings(in: Self.panelView(MenuPanel.State(isOn: true, isPaused: true, windows: [r])).hero)
        #expect(paused.contains("Resume Expanse") && !paused.contains("⌥"))
        // Opening the canvas closes the panel; resuming leaves it open.
        #expect(MenuPanel.Action.toggleCanvas.closesPanel)
        #expect(!MenuPanel.Action.setPaused(false).closesPanel)
    }

    @Test("UI-33 The panel's switch pauses and resumes Expanse (logic)") func ui33() {
        #expect(Self.panelView(MenuPanel.State(isOn: true, isPaused: true)).status == "Paused · windows back in the macOS layout")
        #expect(!MenuPanel.Action.setPaused(true).closesPanel)
    }

    @Test("UI-34 Centre window and Tidy up from the panel (logic)") func ui34() {
        for action in [MenuPanel.Action.centreWindow, .tidy] {
            #expect(action.closesPanel)
            #expect(action.needsCanvas)
        }
    }

    @Test("UI-35 The panel's switches change settings and leave the panel open (logic)") func ui35() {
        for action in [MenuPanel.Action.autoCentre(true), .wallpaper(false), .names(true)] {
            #expect(!action.closesPanel)
            #expect(!action.needsCanvas)
        }
        let strings = Self.strings(in: Self.panelView(MenuPanel.State(isOn: true)).switches)
        for title in ["Auto-centre focused window", "Desktop picture background", "Window names when zoomed out", "⇧"] {
            #expect(strings.contains(title))
        }
    }

    @Test("UI-36 A thumbnail leaves out windows that were out of view: entries out of view are saved as away") func ui36a() throws {
        let onCanvas = Fake.window(id: 1, appName: "Safari", canvas: CGRect(x: 0, y: 33, width: 800, height: 600))
        let c = TestCanvas.make(windows: [onCanvas])
        let folder = try #require(LayoutStore.folderOverride)
        c.hasSynced = true
        // Notes, hidden: its spot is kept (its app is still running).
        c.recentlyRemoved[2] = CanvasController.Departed(
            pid: getpid(), bundleID: "com.apple.Notes", appName: "Notes", title: "",
            canvasFrame: CGRect(x: 3000, y: 33, width: 500, height: 400), originalFrame: CGRect(x: 100, y: 100, width: 500, height: 400),
            preferredSize: CGSize(width: 500, height: 400), home: nil, parked: true, at: Date())
        // A spot from a saved layout, for a window not back yet.
        c.savedPool = [.entry(bundleID: "com.example.kept", appName: "Kept", x: 5000, y: 33, w: 300, h: 200, id: 3)]
        c.save()

        let layout = try #require(LayoutStore.load())
        let byID = Dictionary(layout.windows.compactMap { w in w.id.map { ($0, w) } }, uniquingKeysWith: { a, _ in a })
        #expect(byID[1]?.away == nil)
        #expect(byID[2]?.away == true)
        #expect(byID[3]?.away == true)
        // In the file: no away key on the windows on the canvas.
        let json = try String(contentsOf: folder.appendingPathComponent("layout.json"), encoding: .utf8)
        #expect(json.components(separatedBy: "\"away\"").count - 1 == 2)

        // The thumbnail draws only what was on the canvas.
        let thumbs = MenuPanel.layouts()
        let newest = try #require(thumbs.first)
        #expect(newest.windows == [onCanvas.canvasFrame])
    }

    @Test("UI-36 A thumbnail of a layout from before 0.1.31 (no away key) draws every entry") func ui36b() throws {
        Env.isolate()
        LayoutStore.saveSnapshot(.with([
            .entry(x: 0, y: 0, w: 800, h: 600, id: 1),
            .entry(x: 900, y: 0, w: 400, h: 300, id: 2),
        ]))
        let newest = try #require(MenuPanel.layouts().first)
        #expect(newest.windows == [CGRect(x: 0, y: 0, width: 800, height: 600), CGRect(x: 900, y: 0, width: 400, height: 300)])
    }

    @Test("UI-37 A banner in the panel when a permission is missing (logic)") func ui37() throws {
        func banner(accessibility: Bool, screenRecording: Bool) throws -> (Banner, [String]) {
            var performed: [String] = []
            let state = MenuPanel.State(isOn: true, accessibility: accessibility, screenRecording: screenRecording)
            let view = Self.panelView(state) { performed.append("\($0)") }
            let b = try #require(Self.reflected(Banner.self, in: view.body).first)
            b.action()
            return (b, performed)
        }
        #expect(Self.reflected(Banner.self, in: Self.panelView(MenuPanel.State(isOn: true)).body).isEmpty)
        #expect(Self.strings(in: Self.panelView(MenuPanel.State(isOn: true)).footer).contains("Permissions OK"))

        let (sr, srAsked) = try banner(accessibility: true, screenRecording: false)
        #expect(sr.title == "Screen Recording is off")
        #expect(sr.detail == "Zoomed out, windows show as outlines without it. Once it's on, reopen Expanse.")
        #expect(sr.button == "Open System Settings")
        #expect(srAsked == ["grantScreenRecording"])

        let (ax, axAsked) = try banner(accessibility: false, screenRecording: true)
        #expect(ax.title == "Accessibility is off")
        #expect(ax.detail == "Expanse can't move windows without it.")
        #expect(axAsked == ["grantAccessibility"])

        let (both, _) = try banner(accessibility: false, screenRecording: false)
        #expect(both.title == "Accessibility and Screen Recording are off")

        let footer = Self.strings(in: Self.panelView(MenuPanel.State(isOn: true, screenRecording: false)).footer)
        #expect(footer.contains("Permission needed"))
    }

    @Test("UI-39 Before the walkthrough is done the panel says so: which actions wait") func ui39a() {
        let waiting: [MenuPanel.Action] = [.toggleCanvas, .setPaused(true), .setPaused(false), .centreWindow, .tidy, .restoreAll,
                                           .restoreLayout(URL(fileURLWithPath: "/tmp/1.json")), .takeSnapshot]
        let working: [MenuPanel.Action] = [.autoCentre(true), .wallpaper(true), .names(true), .corner(.all), .corner(.off),
                                           .grantAccessibility, .grantScreenRecording, .installUpdate,
                                           .detailedLogging(true), .copyLogs, .showLogFile, .reportIssue, .welcome, .quit,
                                           .openAtLogin(true), .gap(10), .motion("jump"), .automaticUpdates(true), .checkForUpdates]
        for action in waiting { #expect(action.needsCanvas, "\(action)") }
        for action in working { #expect(!action.needsCanvas, "\(action)") }
        #expect(Self.panelView(MenuPanel.State(isOn: false)).status == "Starts once the walkthrough is done")
    }

    @Test("UI-39 Before the walkthrough is done the panel's canvas actions do nothing") func ui39b() {
        Env.isolate()
        var state = MenuPanel.State(isOn: false)
        var performed: [String] = []
        let panel = MenuPanel(button: NSStatusBarButton(frame: .zero), state: { state }, perform: { performed.append("\($0)") })
        panel.refresh()
        #expect(!panel.model.state.isOn)
        for action in [MenuPanel.Action.toggleCanvas, .setPaused(true), .centreWindow, .tidy, .restoreAll, .takeSnapshot] {
            panel.run(action)
        }
        #expect(performed.isEmpty)
        panel.run(.names(true))
        panel.run(.corner(.bottomLeft))
        panel.run(.gap(10))
        #expect(performed == [MenuPanel.Action.names(true), .corner(.bottomLeft), .gap(10)].map { "\($0)" })

        // Started: they go through.
        state.isOn = true
        panel.refresh()
        performed = []
        panel.run(.tidy)
        #expect(performed == ["tidy"])
    }

    @Test("UI-42 Settings is a page of the panel: its picks leave it open, Esc goes back, then closes") func ui42a() {
        Env.isolate()
        let panel = MenuPanel(button: NSStatusBarButton(frame: .zero), state: { MenuPanel.State(isOn: true) }, perform: { _ in })
        for action in [MenuPanel.Action.openAtLogin(true), .gap(10), .motion("jump"), .automaticUpdates(false)] {
            #expect(!action.closesPanel, "\(action)")
        }
        // Its answer is an alert.
        #expect(MenuPanel.Action.checkForUpdates.closesPanel)
        panel.isShown = true
        panel.model.settings()
        #expect(panel.model.page == .settings)
        panel.escape()
        #expect(panel.model.page == .main)
        #expect(panel.isShown)
        panel.escape()
        #expect(!panel.isShown)
    }

    @Test("UI-42 Settings has what the window had, and says it's a development build") func ui42b() {
        _ = NSApplication.shared
        let model = MenuPanel.Model()
        let page = Self.strings(in: SettingsPage(model: model).body)
        for part in ["Open Expanse at login", "Gaps between windows", "20pt", "10pt", "None", "Glides and zooms", "Match macOS",
                     "Animate", "Jump", "Updates", "Check for updates automatically", "Check Now",
                     "This is a development build: it has no updates, and opening at login opens this copy."] {
            #expect(page.contains { $0.contains(part) }, "\(part)")
        }
    }

    @Test("UI-42 Settings' picks change the settings, and the panel's state shows them") func ui42c() {
        let app = URLTests.makeApp()
        let defaults = UserDefaults.standard
        let saved = [CanvasController.gapKey, CanvasController.motionKey].map { ($0, defaults.object(forKey: $0)) }
        let automatic = Updater.shared.automatic
        defer {
            for (key, value) in saved { defaults.set(value, forKey: key) }
            Updater.shared.automatic = automatic
        }
        for gap in [10, 0, 20] as [CGFloat] {
            app.perform(.gap(gap))
            #expect(CanvasController.gap == gap)
            #expect(app.menuState().gap == gap)
        }
        for motion in ["jump", "glide", "follow"] {
            app.perform(.motion(motion))
            #expect(CanvasController.motion == motion)
            #expect(app.menuState().motion == motion)
        }
        // What low motion goes by is what was picked.
        app.perform(.motion("jump"))
        #expect(CanvasController.lowMotion)
        for on in [false, true] {
            app.perform(.automaticUpdates(on))
            #expect(app.menuState().automaticUpdates == on)
        }
        // Anything unknown shows as Match macOS.
        defaults.set("something else", forKey: CanvasController.motionKey)
        #expect(CanvasController.motion == "follow")
    }

    @Test("UI-40 A sliver at the screen's edge doesn't cover the minimap or Spaces panel") func ui40() {
        let c = Self.canvas()
        let vp = c.viewport
        // Where the minimap is, in global coordinates (top-left origin).
        let panels = c.view.panelsFrame.offsetBy(dx: vp.minX, dy: vp.minY)
        #expect(panels == CGRect(x: vp.maxX - 16 - Minimap.size.width, y: vp.maxY - 16 - Minimap.size.height,
                                 width: Minimap.size.width, height: Minimap.size.height))
        let size = CGSize(width: 900, height: 500)
        // 120pt showing at the right edge, level with the minimap: stays parked.
        let low = CGRect(origin: CGPoint(x: vp.maxX - 120, y: vp.maxY - 450), size: size)
        #expect(!CanvasController.goesOnScreen(low, in: vp, panels: panels))
        #expect(!c.goesOnScreen(low, in: vp))
        // 300pt showing: on screen.
        let wide = CGRect(origin: CGPoint(x: vp.maxX - 300, y: vp.maxY - 450), size: size)
        #expect(CanvasController.goesOnScreen(wide, in: vp, panels: panels))
        #expect(c.goesOnScreen(wide, in: vp))
        // 120pt near the top, clear of the panels: on screen.
        let high = CGRect(origin: CGPoint(x: vp.maxX - 120, y: vp.minY + 10), size: size)
        #expect(CanvasController.goesOnScreen(high, in: vp, panels: panels))
        #expect(c.goesOnScreen(high, in: vp))
        // With the Spaces panel showing, a sliver over it stays parked too.
        c.view.updateSpaces(Self.spaces(3), active: 100)
        c.view.layoutSubtreeIfNeeded()
        let both = c.view.panelsFrame.offsetBy(dx: vp.minX, dy: vp.minY)
        #expect(both.width > panels.width)
        // 100pt of its top showing at the bottom, over the Spaces panel but clear of the minimap.
        let bottom = CGRect(x: both.minX + 20, y: vp.maxY - 100, width: 300, height: 500)
        #expect(!bottom.intersection(vp).intersects(panels))
        #expect(!CanvasController.goesOnScreen(bottom, in: vp, panels: both))
        #expect(!c.goesOnScreen(bottom, in: vp))
        #expect(CanvasController.goesOnScreen(bottom, in: vp, panels: panels))
    }

    // MARK: UI-41

    @Test("UI-41 An invisible window over the whole screen isn't taken for a dialog (logic)") func ui41() {
        func w(_ pid: pid_t, layer: Int, _ r: CGRect, alpha: Double = 1) -> [String: Any] {
            [kCGWindowLayer as String: layer, kCGWindowOwnerPID as String: pid, kCGWindowAlpha as String: alpha,
             kCGWindowBounds as String: ["X": r.minX, "Y": r.minY, "Width": r.width, "Height": r.height] as [String: CGFloat]]
        }
        let screen = CGSize(width: 1600, height: 1000)
        let notificationCenter = w(400, layer: 21, CGRect(origin: .zero, size: screen))
        let alert = w(401, layer: 8, CGRect(x: 600, y: 300, width: 400, height: 200))
        let dock = w(402, layer: 20, CGRect(x: 0, y: 900, width: 1600, height: 100))
        func level(_ ws: [[String: Any]]) -> Int? {
            CanvasController.lowestDialogLevel(in: ws, screen: screen, ownPID: 1) { $0 == 402 }
        }
        #expect(level([notificationCenter]) == nil, "Notification Center's overlay over the whole screen")
        #expect(level([notificationCenter, alert]) == 8, "a real dialog still counts")
        #expect(level([dock]) == nil)
        #expect(level([w(403, layer: 8, CGRect(x: 0, y: 0, width: 1600, height: 600))]) == 8, "a wide dialog that doesn't cover the screen")
        #expect(level([w(404, layer: 8, CGRect(x: 600, y: 300, width: 400, height: 200), alpha: 0)]) == nil, "an invisible one")
    }
}
