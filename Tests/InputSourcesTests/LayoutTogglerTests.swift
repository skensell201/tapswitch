import Testing
@testable import InputSources

/// Stands in for TIS. `select` flips `current` and fires the change callback
/// synchronously — the real system posts a distributed notification shortly
/// after — and `externallySelect` fakes the user pressing fn.
@MainActor
private final class FakeProvider: InputSourceProvider {
    var enabled: [InputSource]
    var currentSource: InputSource?
    var selected: [InputSource] = []
    var onSelectionChanged: (() -> Void)?

    init(enabled: [InputSource], current: InputSource?) {
        self.enabled = enabled
        self.currentSource = current
    }

    func enabledKeyboardLayouts() -> [InputSource] { enabled }
    func current() -> InputSource? { currentSource }

    func select(_ source: InputSource) {
        selected.append(source)
        currentSource = source
        onSelectionChanged?()
    }

    func externallySelect(_ source: InputSource) {
        currentSource = source
        onSelectionChanged?()
    }
}

@MainActor
@Suite("Layout toggler")
struct LayoutTogglerTests {
    private let ru = InputSource(id: "com.apple.keylayout.Russian", name: "Russian")
    private let en = InputSource(id: "com.apple.keylayout.ABC", name: "ABC")
    private let de = InputSource(id: "com.apple.keylayout.German", name: "German")

    @Test("with two layouts, toggle picks the other one")
    func togglesToOther() {
        let provider = FakeProvider(enabled: [ru, en], current: ru)
        let toggler = LayoutToggler(provider: provider)
        toggler.toggle()
        #expect(provider.selected == [en])
        toggler.toggle()
        #expect(provider.selected == [en, ru])
    }

    @Test("with three layouts, toggle alternates the last two")
    func alternatesLastTwo() {
        let provider = FakeProvider(enabled: [ru, en, de], current: de)
        let toggler = LayoutToggler(provider: provider)
        toggler.toggle()
        #expect(provider.selected == [ru])
        toggler.toggle()
        #expect(provider.selected == [ru, de])
        toggler.toggle()
        #expect(provider.selected == [ru, de, ru])
    }

    @Test("a previous layout that was disabled is skipped")
    func previousDisabled() {
        let provider = FakeProvider(enabled: [ru, en, de], current: ru)
        let toggler = LayoutToggler(provider: provider)
        toggler.toggle()
        #expect(provider.currentSource == en)
        provider.enabled = [en, de]
        toggler.toggle()
        #expect(provider.selected == [en, de])
    }

    @Test("a single layout is a no-op")
    func singleLayout() {
        let provider = FakeProvider(enabled: [ru], current: ru)
        let toggler = LayoutToggler(provider: provider)
        toggler.toggle()
        #expect(provider.selected.isEmpty)
    }

    @Test("no current layout is a no-op")
    func noCurrent() {
        let provider = FakeProvider(enabled: [ru, en], current: nil)
        let toggler = LayoutToggler(provider: provider)
        toggler.toggle()
        #expect(provider.selected.isEmpty)
    }

    @Test("switching with fn between taps updates the history")
    func externalSwitchUpdatesHistory() {
        let provider = FakeProvider(enabled: [ru, en, de], current: ru)
        let toggler = LayoutToggler(provider: provider)
        provider.externallySelect(de)
        toggler.toggle()
        #expect(provider.selected == [ru])
    }
}
