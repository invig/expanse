import AppKit

/// Instant Space switching: a synthetic trackpad swipe so fast that the Dock skips its slide
/// (the trick behind InstantSpaceSwitcher, MIT, which this follows; Space Rabbit does the same).
/// One swipe moves one Space, on the display under the pointer. Posting it needs Accessibility.
///
/// macOS 27 checks a swipe against a copy of the trackpad's own data attached to the event
/// (field 4205), which can't be set like other fields: the event is flattened, the record
/// appended, and the event rebuilt. Its sense of left and right also follows Natural scrolling.
enum SpaceSwipe {
    /// Steps to `target` on the main display, instantly. False if it can't from here (the pointer
    /// on another display, or `target` not on the main display); then nothing is posted.
    static func go(to target: UInt64) -> Bool {
        let (ids, current) = Spaces.order()
        // The pointer's on the main display, edges included (it rests on the top edge in a top hot corner).
        let p = NSEvent.mouseLocation
        guard let from = ids.firstIndex(where: { $0 == current }), let to = ids.firstIndex(of: target),
              let f = NSScreen.screens.first?.frame, p.x >= f.minX, p.x <= f.maxX, p.y >= f.minY, p.y <= f.maxY
        else { return false }
        guard from != to else { return true }
        let right = to > from
        for _ in 0..<abs(to - from) {
            guard swipe(right: right) else { return false }
        }
        return true
    }

    // Fields the Dock reads off a swipe (undocumented; as InstantSpaceSwitcher sets them).
    private static let typeField = CGEventField(rawValue: 55)!
    private static let hidType = CGEventField(rawValue: 110)!
    private static let motionField = CGEventField(rawValue: 123)!
    private static let progressField = CGEventField(rawValue: 124)!
    private static let positionX = CGEventField(rawValue: 125)!
    private static let positionY = CGEventField(rawValue: 126)!
    private static let velocityX = CGEventField(rawValue: 129)!
    private static let velocityY = CGEventField(rawValue: 130)!
    private static let phaseField = CGEventField(rawValue: 132)!
    private static let phaseMirror = CGEventField(rawValue: 134)!
    private static let flavorField = CGEventField(rawValue: 138)!
    private static let timestampField = CGEventField(rawValue: 169)!
    private static let swipeMaskField = CGEventField(rawValue: 115)!
    private static let gestureEvent: Int64 = 29, dockControl: Int64 = 30, dockSwipe: Int64 = 23
    private static let horizontal: Int64 = 1
    private static let phases: [Int64] = [1, 2, 4]   // began, changed, ended
    private static let ended: Int64 = 4

    private static var modern: Bool { ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 }

    /// One complete swipe, began through ended.
    private static func swipe(right: Bool) -> Bool {
        let events = phases.compactMap { modern ? modernEvents(phase: $0, right: right) : legacyEvents(phase: $0, right: right) }
        // All or nothing: a began without its ended would leave the Dock mid-gesture.
        guard events.count == phases.count else { return false }
        for pair in events { pair.forEach { $0.post(tap: .cgSessionEventTap) } }
        return true
    }

    /// Before macOS 27: the dock event alone, with a huge velocity.
    private static func legacyEvents(phase: Int64, right: Bool) -> [CGEvent]? {
        guard let e = dockEvent(phase: phase) else { return nil }
        let sign = right ? 1.0 : -1.0
        e.setDoubleValueField(progressField, value: sign * 0.000016)
        e.setDoubleValueField(velocityX, value: sign * 2000)
        e.setDoubleValueField(velocityY, value: sign * 2000)
        return [e]
    }

    /// macOS 27: the fields a real trackpad swipe carries, nearly no travel (so nothing is drawn
    /// in between), the fling on the ended phase only, the trackpad data attached, and a
    /// companion gesture event (the Dock ignores a swipe without one).
    private static func modernEvents(phase: Int64, right: Bool) -> [CGEvent]? {
        guard let e = dockEvent(phase: phase), let companion = CGEvent(source: nil) else { return nil }
        // Right is negative with Natural scrolling on (the default), positive with it off.
        let natural = CFPreferencesCopyAppValue("com.apple.swipescrolldirection" as CFString,
                                                kCFPreferencesAnyApplication) as? Bool ?? true
        let sign = (right ? -1.0 : 1.0) * (natural ? 1 : -1)
        e.setDoubleValueField(progressField, value: sign * 0.000016)
        e.setIntegerValueField(phaseMirror, value: phase)
        e.setDoubleValueField(flavorField, value: 3)   // primary dock swipe
        e.setDoubleValueField(timestampField, value: Double(mach_absolute_time()))
        e.setDoubleValueField(positionX, value: 0.1)
        if phase == ended { e.setDoubleValueField(velocityX, value: sign * 9999) }
        guard let attached = attachingTrackpadData(e) else { return nil }
        companion.setIntegerValueField(typeField, value: gestureEvent)
        return [attached, companion]
    }

    private static func dockEvent(phase: Int64) -> CGEvent? {
        guard let e = CGEvent(source: nil) else { return nil }
        e.setIntegerValueField(typeField, value: dockControl)
        e.setIntegerValueField(hidType, value: dockSwipe)
        e.setIntegerValueField(phaseField, value: phase)
        e.setIntegerValueField(motionField, value: horizontal)
        return e
    }

    // MARK: Trackpad data (macOS 27)

    /// `event` rebuilt with field 4205: the trackpad's queue record (a header, the swipe, and on
    /// the ended phase its velocity), packed little-endian as IOHID lays it out.
    private static func attachingTrackpadData(_ event: CGEvent) -> CGEvent? {
        guard var bytes = event.data as Data?, bytes.count >= 4, bytes.prefix(4) == Data([0, 0, 0, 2]) else { return nil }
        let phase = event.getIntegerValueField(phaseField)
        let velocity = (event.getDoubleValueField(velocityX), event.getDoubleValueField(velocityY))
        let withVelocity = velocity.0 != 0 || velocity.1 != 0 || phase == ended

        var record = Data()
        // Queue element header.
        record.appendLE(event.timestamp != 0 ? event.timestamp : mach_absolute_time())
        record.appendLE(UInt64(0))                   // sender
        record.appendLE(UInt32(0))                   // options
        record.appendLE(UInt32(0))                   // attribute length
        record.appendLE(UInt32(withVelocity ? 2 : 1)) // events
        // The swipe (a fluid touch gesture).
        record.appendLE(UInt32(40))                  // size
        record.appendLE(UInt32(23))                  // type: fluid touch gesture
        record.appendLE(UInt32((phase & 0xFF) << 24)) // options: the phase, in the top byte
        record.append(contentsOf: [0, 0, 0, 0])      // depth, reserved
        record.appendLE(fixed(event.getDoubleValueField(positionX)))
        record.appendLE(fixed(event.getDoubleValueField(positionY)))
        record.appendLE(Int32(0))
        record.appendLE(UInt32(truncatingIfNeeded: event.getIntegerValueField(swipeMaskField)))
        record.appendLE(UInt16(truncatingIfNeeded: event.getIntegerValueField(motionField)))
        record.appendLE(UInt16(3))                   // flavor: primary dock swipe
        record.appendLE(fixed(event.getDoubleValueField(progressField)))
        if withVelocity {
            record.appendLE(UInt32(28))              // size
            record.appendLE(UInt32(9))               // type: velocity
            record.appendLE(UInt32(0))
            record.append(contentsOf: [1, 0, 0, 0])  // depth 1, reserved
            record.appendLE(fixed(velocity.0))
            record.appendLE(fixed(velocity.1))
            record.appendLE(Int32(0))
        }
        // A binary field: its length and id, big-endian, then the bytes.
        let field: UInt16 = 4205
        bytes.append(contentsOf: [UInt8(record.count >> 8), UInt8(record.count & 0xFF), UInt8(field >> 8), UInt8(field & 0xFF)])
        bytes.append(record)
        return CGEvent(withDataAllocator: kCFAllocatorDefault, data: bytes as CFData)
    }

    /// 16.16 fixed point; anything too small to show keeps its sign.
    private static func fixed(_ value: Double) -> Int32 {
        guard value.isFinite else { return 0 }
        let f = Int32(clamping: Int64((value * 65536).rounded(.towardZero)))
        return f == 0 && value != 0 ? (value > 0 ? 1 : -1) : f
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
