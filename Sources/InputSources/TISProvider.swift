import AppKit
import Carbon

/// `InputSourceProvider` over Carbon's Text Input Source API. Must be used from
/// the main thread: `TISSelectInputSource` called elsewhere reports success and
/// changes nothing.
@MainActor
public final class TISProvider: InputSourceProvider {
    public var onSelectionChanged: (() -> Void)?

    private var observer: NSObjectProtocol?

    public init() {
        let name = Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)
        observer = DistributedNotificationCenter.default().addObserver(
            forName: name, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onSelectionChanged?()
            }
        }
    }

    isolated deinit {
        if let observer {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }

    public func enabledKeyboardLayouts() -> [InputSource] {
        let filter: [CFString: Any] = [
            kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource as String,
            kTISPropertyInputSourceIsEnabled: true,
            kTISPropertyInputSourceIsSelectCapable: true
        ]
        return sources(matching: filter).compactMap(Self.describe)
    }

    public func current() -> InputSource? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }
        return Self.describe(source)
    }

    public func select(_ source: InputSource) {
        let filter: [CFString: Any] = [kTISPropertyInputSourceID: source.id]
        guard let tis = sources(matching: filter).first else { return }
        TISSelectInputSource(tis)
    }

    private func sources(matching filter: [CFString: Any]) -> [TISInputSource] {
        guard let list = TISCreateInputSourceList(filter as CFDictionary, false)?
            .takeRetainedValue() as? [TISInputSource]
        else { return [] }
        return list
    }

    private static func describe(_ source: TISInputSource) -> InputSource? {
        guard let id = string(property: kTISPropertyInputSourceID, of: source),
              let name = string(property: kTISPropertyLocalizedName, of: source)
        else { return nil }
        return InputSource(id: id, name: name)
    }

    private static func string(property: CFString, of source: TISInputSource) -> String? {
        guard let raw = TISGetInputSourceProperty(source, property) else { return nil }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }
}
