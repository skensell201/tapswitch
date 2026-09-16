import Foundation

// Layout of MultitouchSupport's per-finger record, as reverse-engineered and used
// by MiddleClick, Fingers, OpenMultitouchSupport and others. Field order and
// types must not change: the framework writes these bytes, we only read them.

struct MTPoint {
    var x: Float
    var y: Float
}

struct MTReadout {
    var position: MTPoint
    var velocity: MTPoint
}

struct MTFinger {
    var frame: Int32
    var timestamp: Double
    var identifier: Int32
    /// 3 = touch beginning, 4 = touching; anything else is hover or lift-off.
    var state: Int32
    var foo3: Int32
    var foo4: Int32
    /// Position normalized to 0…1 across the device.
    var normalized: MTReadout
    var size: Float
    var zero1: Int32
    var angle: Float
    var majorAxis: Float
    var minorAxis: Float
    var mm: MTReadout
    var zero2: (Int32, Int32)
    var unk2: Float
}

typealias MTDeviceRef = UnsafeMutableRawPointer
/// (device, fingers, count, timestamp, frame). `fingers` points at `count`
/// consecutive `MTFinger` records; C callbacks cannot spell a Swift struct
/// pointer, so it arrives raw and is bound on the other side.
typealias MTContactCallback = @convention(c) (
    MTDeviceRef?, UnsafeMutableRawPointer?, Int32, Double, Int32
) -> Int32

/// `dlopen`'d handle to the private framework plus the five entry points we use.
struct MultitouchFramework {
    private typealias CreateList = @convention(c) () -> Unmanaged<CFArray>?
    private typealias Register = @convention(c) (MTDeviceRef?, MTContactCallback?) -> Void
    private typealias Start = @convention(c) (MTDeviceRef?, Int32) -> Void
    private typealias Stop = @convention(c) (MTDeviceRef?) -> Void

    private let createList: CreateList
    private let register: Register
    private let unregister: Register
    private let start: Start
    private let stop: Stop

    static let path =
        "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"

    static func load() throws -> MultitouchFramework {
        guard let handle = dlopen(path, RTLD_NOW) else {
            throw MultitouchError.frameworkUnavailable("dlopen failed: \(String(cString: dlerror()))")
        }
        func symbol<T>(_ name: String, as _: T.Type) throws -> T {
            guard let sym = dlsym(handle, name) else {
                throw MultitouchError.frameworkUnavailable("missing symbol \(name)")
            }
            return unsafeBitCast(sym, to: T.self)
        }
        return MultitouchFramework(
            createList: try symbol("MTDeviceCreateList", as: CreateList.self),
            register: try symbol("MTRegisterContactFrameCallback", as: Register.self),
            unregister: try symbol("MTUnregisterContactFrameCallback", as: Register.self),
            start: try symbol("MTDeviceStart", as: Start.self),
            stop: try symbol("MTDeviceStop", as: Stop.self))
    }

    /// Every multitouch device. The array owns the device refs; keep it alive
    /// for as long as they are in use.
    func devices() -> (CFArray, [MTDeviceRef])? {
        guard let list = createList()?.takeRetainedValue() else { return nil }
        let refs = (0..<CFArrayGetCount(list)).compactMap { index -> MTDeviceRef? in
            guard let raw = CFArrayGetValueAtIndex(list, index) else { return nil }
            return MTDeviceRef(mutating: raw)
        }
        return (list, refs)
    }

    func startListening(_ device: MTDeviceRef, callback: MTContactCallback) {
        register(device, callback)
        start(device, 0)
    }

    func stopListening(_ device: MTDeviceRef, callback: MTContactCallback) {
        stop(device)
        unregister(device, callback)
    }
}

public enum MultitouchError: Error, Equatable {
    case frameworkUnavailable(String)
    case noDevices
}
