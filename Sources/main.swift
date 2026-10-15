// Midpoint — middle click for Apple trackpads (three-finger click and three-finger tap).
//
// How it works:
//   1. MultitouchSupport (private framework) contact-frame callback -> how many fingers are down.
//   2. Active CGEventTap (session, head insert) on left-mouse events:
//        three fingers + physical click  -> rewrite the event in place to otherMouse*, button 2.
//   3. Three-finger tap (lift within 0.35 s, little movement, no physical click)
//        -> synthesize otherMouseDown/Up (button 2) at the cursor.

import AppKit
import ApplicationServices
import Foundation

// MARK: - MultitouchSupport (private) via dlopen

struct MTPoint { var x: Float; var y: Float }
struct MTVector { var pos: MTPoint; var vel: MTPoint }
// Community-documented MTTouch layout (same as open-source MiddleClick / Touch-Tab).
struct MTTouch {
    var frame: Int32
    var timestamp: Double
    var identifier: Int32
    var state: Int32          // 1..7; 4 == touching
    var fingerID: Int32
    var handID: Int32
    var normalized: MTVector  // 0..1 surface coordinates
    var size: Float
    var zero1: Int32
    var angle: Float
    var majorAxis: Float
    var minorAxis: Float
    var mm: MTVector
    var zero2: (Int32, Int32)
    var density: Float
}

typealias MTDeviceRef = UnsafeMutableRawPointer
typealias MTContactCallback = @convention(c) (MTDeviceRef?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32

private let mt = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW)
private func sym<T>(_ name: String, _: T.Type) -> T {
    guard let mt, let p = dlsym(mt, name) else { fatalError("MultitouchSupport symbol missing: \(name)") }
    return unsafeBitCast(p, to: T.self)
}
private let MTDeviceCreateList = sym("MTDeviceCreateList", (@convention(c) () -> Unmanaged<CFArray>).self)
private let MTRegisterContactFrameCallback = sym("MTRegisterContactFrameCallback", (@convention(c) (MTDeviceRef, MTContactCallback) -> Void).self)
private let MTUnregisterContactFrameCallback = sym("MTUnregisterContactFrameCallback", (@convention(c) (MTDeviceRef, MTContactCallback) -> Void).self)
private let MTDeviceStart = sym("MTDeviceStart", (@convention(c) (MTDeviceRef, Int32) -> Int32).self)
private let MTDeviceStop = sym("MTDeviceStop", (@convention(c) (MTDeviceRef) -> Int32).self)

// MARK: - Debug log (~/Library/Logs/Midpoint.log)

let logURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Midpoint.log")
let logQueue = DispatchQueue(label: "log")
func debugLog(_ message: String) {
    let line = "\(Date()) \(message)\n"
    logQueue.async {
        if let h = try? FileHandle(forWritingTo: logURL) {
            h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
        } else {
            try? line.write(to: logURL, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - Shared state (MT thread writes, event-tap thread reads)

let tapMaxDuration = 0.35       // seconds from first touch to full lift
let tapMaxTravel: Float = 0.04  // max finger movement, in normalized trackpad units
let fingersForMiddleClick = 3

final class State {
    private var lock = os_unfair_lock()
    private var _fingers = 0
    // tap-session tracking
    private var sessionStart = 0.0
    private var sessionMax = 0
    private var startPositions: [Int32: MTPoint] = [:]
    private var maxTravel: Float = 0
    private var physicalClickInSession = false

    var fingers: Int { os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }; return _fingers }
    func notePhysicalClick() { os_unfair_lock_lock(&lock); physicalClickInSession = true; os_unfair_lock_unlock(&lock) }

    /// Returns true when a completed three-finger tap was recognized.
    func update(touches: UnsafeBufferPointer<MTTouch>, time: Double) -> Bool {
        os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }
        let active = touches.filter { $0.state == 4 }
        let previous = _fingers
        _fingers = active.count

        if previous == 0 && !active.isEmpty {         // session begins
            sessionStart = time; sessionMax = 0; startPositions = [:]
            maxTravel = 0; physicalClickInSession = false
        }
        sessionMax = max(sessionMax, active.count)
        for t in active {
            if let s = startPositions[t.identifier] {
                maxTravel = max(maxTravel, hypot(t.normalized.pos.x - s.x, t.normalized.pos.y - s.y))
            } else {
                startPositions[t.identifier] = t.normalized.pos
            }
        }
        guard previous > 0 && active.isEmpty else { return false }  // session ends on full lift
        let isTap = sessionMax == fingersForMiddleClick
            && time - sessionStart < tapMaxDuration
            && maxTravel < tapMaxTravel
            && !physicalClickInSession
        debugLog(String(format: "session end: fingers=%d duration=%.3fs travel=%.3f clicked=%@ -> %@",
                        sessionMax, time - sessionStart, maxTravel, physicalClickInSession ? "yes" : "no",
                        isTap ? "TAP" : "ignored"))
        return isTap
    }
}
let state = State()

// MARK: - Settings & status (read by the UI)

enum Settings {
    static let threeClickKey = "trackpadThreeClick", threeTapKey = "trackpadThreeTap"
    static func register() { UserDefaults.standard.register(defaults: [threeClickKey: true, threeTapKey: true]) }
    static var threeClick: Bool { UserDefaults.standard.bool(forKey: threeClickKey) }
    static var threeTap: Bool { UserDefaults.standard.bool(forKey: threeTapKey) }
}

enum Status {     // main-thread only
    static var tapInstalled = false
    static var deviceCount = 0
    static var clickCount = 0
    static var lastClick: (gesture: String, at: Date)?
    static func record(_ gesture: String) { clickCount += 1; lastClick = (gesture, Date()) }
}

// MARK: - Synthesized middle click (tap path)

func postMiddleClick() {
    let loc = CGEvent(source: nil)?.location ?? .zero
    let src = CGEventSource(stateID: .hidSystemState)
    for type in [CGEventType.otherMouseDown, .otherMouseUp] {
        let e = CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: loc, mouseButton: .center)
        e?.setIntegerValueField(.mouseEventClickState, value: 1)   // some apps (e.g. Chromium) ignore clicks with click count 0
        e?.post(tap: .cghidEventTap)
    }
    Status.record("three-finger tap")
    debugLog("posted middle click at \(loc)")
}

let contactCallback: MTContactCallback = { _, touches, count, timestamp, _ in
    guard let raw = touches else { return 0 }
    let buf = UnsafeBufferPointer(start: raw.assumingMemoryBound(to: MTTouch.self), count: Int(count))
    if state.update(touches: buf, time: timestamp) && Settings.threeTap {
        DispatchQueue.main.async(execute: postMiddleClick)
    }
    return 0
}

// MARK: - Device registration (re-done after wake)

// The device objects must stay referenced: if the list is freed, AppKit's autorelease drain deallocates
// the MTDevices and their mt_ThreadedMTEntry thread stops delivering frames.
var deviceObjects: [AnyObject] = []
func registerDevices() {
    for d in deviceObjects {
        let p = Unmanaged.passUnretained(d).toOpaque()
        MTUnregisterContactFrameCallback(p, contactCallback); _ = MTDeviceStop(p)
    }
    deviceObjects = MTDeviceCreateList().takeRetainedValue() as [AnyObject]
    for d in deviceObjects {
        let p = Unmanaged.passUnretained(d).toOpaque()
        MTRegisterContactFrameCallback(p, contactCallback)
        _ = MTDeviceStart(p, 0)
    }
    Status.deviceCount = deviceObjects.count
    debugLog("listening to \(deviceObjects.count) multitouch device(s)")
}

/// Touch input needs no permission, so it starts at launch (the live finger count works even before Accessibility).
func startTouchInput() {
    registerDevices()
    NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: registerDevices)
    }
}

// MARK: - Event tap (click path): rewrite left click -> middle click

var converting = false
var tapPort: CFMachPort?

let tapCallback: CGEventTapCallBack = { _, type, event, _ in
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        if let tapPort { CGEvent.tapEnable(tap: tapPort, enable: true) }   // macOS disables slow taps; re-arm
    case .leftMouseDown where Settings.threeClick && state.fingers == fingersForMiddleClick:
        converting = true
        state.notePhysicalClick()
        Status.record("three-finger click")
        debugLog("converted physical click to middle click")
        event.type = .otherMouseDown
        event.setIntegerValueField(.mouseEventButtonNumber, value: 2)
    case .leftMouseDragged where converting:
        event.type = .otherMouseDragged
        event.setIntegerValueField(.mouseEventButtonNumber, value: 2)
    case .leftMouseUp where converting:
        converting = false
        event.type = .otherMouseUp
        event.setIntegerValueField(.mouseEventButtonNumber, value: 2)
    default: break
    }
    return Unmanaged.passUnretained(event)
}

/// Installs the event tap. Safe to call repeatedly; returns true once running.
@discardableResult
func startEngine() -> Bool {
    if Status.tapInstalled { return true }
    guard AXIsProcessTrusted() else { return false }
    let mask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
        | (1 << CGEventType.leftMouseDragged.rawValue)
    guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                       options: .defaultTap, eventsOfInterest: CGEventMask(mask),
                                       callback: tapCallback, userInfo: nil) else {
        debugLog("CGEventTapCreate failed"); return false
    }
    tapPort = port
    CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, port, 0), .commonModes)
    CGEvent.tapEnable(tap: port, enable: true)
    Status.tapInstalled = true
    return true
}

// MARK: - main

if CommandLine.arguments.contains("--list") {
    let n = (MTDeviceCreateList().takeRetainedValue() as [AnyObject]).count
    print("multitouch devices: \(n)"); exit(0)
}

Settings.register()
let appDelegate = AppDelegate()
NSApplication.shared.delegate = appDelegate
NSApplication.shared.setActivationPolicy(.accessory)   // menu bar app; no Dock icon
NSApplication.shared.run()
