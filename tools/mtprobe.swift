// mtprobe — prints raw MultitouchSupport frames to check that touch input arrives.
// Usage: mtprobe [seconds] [--release-list]
//   --release-list frees the device list after registering (debug aid).
import Foundation
import IOKit.hid
import ApplicationServices

struct MTPoint { var x: Float; var y: Float }
struct MTVector { var pos: MTPoint; var vel: MTPoint }
struct MTTouch {
    var frame: Int32; var timestamp: Double; var identifier: Int32; var state: Int32
    var fingerID: Int32; var handID: Int32; var normalized: MTVector; var size: Float; var zero1: Int32
    var angle: Float; var majorAxis: Float; var minorAxis: Float; var mm: MTVector
    var zero2: (Int32, Int32); var density: Float
}
typealias Callback = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32

let mt = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW)!
func sym<T>(_ n: String, _: T.Type) -> T { unsafeBitCast(dlsym(mt, n)!, to: T.self) }
let createList = sym("MTDeviceCreateList", (@convention(c) () -> Unmanaged<CFArray>).self)
let register = sym("MTRegisterContactFrameCallback", (@convention(c) (UnsafeMutableRawPointer, Callback) -> Void).self)
let start = sym("MTDeviceStart", (@convention(c) (UnsafeMutableRawPointer, Int32) -> Int32).self)

var frames = 0
var lastSummary = ""
let cb: Callback = { _, raw, count, ts, _ in
    frames += 1
    let touches = UnsafeBufferPointer(start: raw?.assumingMemoryBound(to: MTTouch.self), count: Int(count))
    let summary = "contacts=\(count) states=\(touches.map { $0.state })"
    if summary != lastSummary {
        lastSummary = summary
        print(String(format: "%.3f  ", ts) + summary + "  " +
              touches.map { String(format: "(%.2f,%.2f)", $0.normalized.pos.x, $0.normalized.pos.y) }.joined(separator: " "))
    }
    return 0
}

let seconds = Double(CommandLine.arguments.dropFirst().first { Double($0) != nil } ?? "15")!
let releaseList = CommandLine.arguments.contains("--release-list")
var keep: [AnyObject]? = (createList().takeRetainedValue() as [AnyObject])
let listen = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
print("Input Monitoring (ListenEvent) access: \(listen == kIOHIDAccessTypeGranted ? "granted" : listen == kIOHIDAccessTypeDenied ? "DENIED" : "unknown/not asked")")
print("Accessibility trusted: \(AXIsProcessTrusted())")
print("MTTouch stride: \(MemoryLayout<MTTouch>.stride) bytes (expect 96); devices: \(keep!.count)")
for d in keep! {
    let p = Unmanaged.passUnretained(d).toOpaque()
    register(p, cb)
    print("MTDeviceStart -> \(start(p, 0))")
}
if releaseList { keep = nil; print("(device list released)") }
print("Touch the trackpad for \(Int(seconds))s: try a three-finger tap and a three-finger click…")
RunLoop.main.run(until: Date().addingTimeInterval(seconds))
print("done: \(frames) frames received" + (keep == nil ? " [list released]" : ""))
