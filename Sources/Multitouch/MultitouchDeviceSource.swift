import Foundation
import Gesture

/// Anything that produces touch frames. The app talks to this, never to
/// `MultitouchDeviceSource` directly.
@MainActor
public protocol TouchSource: AnyObject {
    var onFrame: ((TouchFrame) -> Void)? { get set }
    func start() throws
    func stop()
}

/// Frames from every attached multitouch device. Only one instance may be
/// started at a time: the framework's callback carries no context pointer, so
/// delivery goes through `active`.
@MainActor
public final class MultitouchDeviceSource: TouchSource {
    public var onFrame: ((TouchFrame) -> Void)?

    private static var active: MultitouchDeviceSource?

    private var framework: MultitouchFramework?
    private var deviceList: CFArray?
    private var devices: [MTDeviceRef] = []

    public init() {}

    public func start() throws {
        stop()
        let framework = try self.framework ?? MultitouchFramework.load()
        self.framework = framework

        guard let (list, refs) = framework.devices(), !refs.isEmpty else {
            throw MultitouchError.noDevices
        }
        deviceList = list
        devices = refs
        Self.active = self
        for device in refs {
            framework.startListening(device, callback: contactCallback)
        }
    }

    public func stop() {
        guard let framework, !devices.isEmpty else { return }
        for device in devices {
            framework.stopListening(device, callback: contactCallback)
        }
        devices = []
        deviceList = nil
        if Self.active === self {
            Self.active = nil
        }
    }

    fileprivate static func deliver(_ frame: TouchFrame) {
        active?.onFrame?(frame)
    }
}

/// Runs on the framework's own thread. Builds an immutable frame and hops to
/// the main queue, so nothing downstream needs to be thread-safe.
private let contactCallback: MTContactCallback = { _, fingers, count, timestamp, _ in
    var contacts: [TouchContact] = []
    if let fingers, count > 0 {
        let records = fingers.assumingMemoryBound(to: MTFinger.self)
        for index in 0..<Int(count) {
            let finger = records[index]
            guard finger.state == 3 || finger.state == 4 else { continue }
            contacts.append(TouchContact(
                id: Int(finger.identifier),
                x: Double(finger.normalized.position.x),
                y: Double(finger.normalized.position.y)))
        }
    }
    let frame = TouchFrame(timestamp: timestamp, contacts: contacts)
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            MultitouchDeviceSource.deliver(frame)
        }
    }
    return 0
}
