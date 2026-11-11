import AppKit

private final class ClassicMenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// A Winamp-era popup, rendered independently of macOS's rounded system menus.
final class ClassicMenu {
    private let panel: ClassicMenuPanel
    private let list: ClassicMenuList
    private weak var target: NSView?
    private var monitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var closed = false
    var onClose: (() -> Void)?

    init(items: [(String, Selector)], target: NSView, anchor: NSRect, scale: CGFloat) {
        self.target = target
        list = ClassicMenuList(items: items, scale: min(2, max(1, scale)))
        panel = ClassicMenuPanel(contentRect: NSRect(origin: .zero, size: list.frame.size), styleMask: [.borderless], backing: .buffered, defer: false)
        panel.contentView = list
        panel.isOpaque = true
        panel.backgroundColor = ClassicMenuList.background
        panel.hasShadow = false
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.level = .popUpMenu
        panel.setAccessibilityLabel("Winamp menu")
        list.choose = { [weak self] index in self?.select(index) }
        list.cancel = { [weak self] in self?.dismiss() }
        let screen = target.window?.screen ?? NSScreen.main
        let area = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = list.frame.size
        var origin = NSPoint(x: anchor.minX, y: anchor.minY - size.height)
        if origin.y < area.minY { origin.y = anchor.maxY }
        origin.x = max(area.minX, min(origin.x, area.maxX - size.width))
        origin.y = max(area.minY, min(origin.y, area.maxY - size.height))
        panel.setFrameOrigin(origin)
    }

    func savePreview(to url: URL) {
        guard let image = list.bitmapImageRepForCachingDisplay(in:list.bounds) else { return }
        list.cacheDisplay(in:list.bounds,to:image)
        try? image.representation(using:.png,properties:[:])?.write(to:url)
    }

    func show() {
        target?.window?.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(list)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                self.list.keyDown(with: event)
                return nil
            }
            if event.window !== self.panel { self.dismiss() }
            return event
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.dismiss() }
    }

    private func select(_ index: Int) {
        guard list.items.indices.contains(index) else { return }
        let action = list.items[index].1
        let receiver = target
        dismiss()
        if let receiver { NSApp.sendAction(action, to: receiver, from: nil) }
    }

    func dismiss() {
        guard !closed else { return }
        closed = true
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver); self.resignObserver = nil }
        let parent = panel.parent
        parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        parent?.makeKey()
        onClose?()
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
    }
}

private final class ClassicMenuList: NSView {
    static let background = NSColor(calibratedRed: 0.73, green: 0.76, blue: 0.78, alpha: 1)
    let items: [(String, Selector)]
    let unit: CGFloat
    let font: NSFont
    var selected = -1 { didSet { needsDisplay = true } }
    var choose: ((Int) -> Void)?
    var cancel: (() -> Void)?
    private var tracking: NSTrackingArea?
    private var rowHeight: CGFloat { 19 * unit }
    private var inset: CGFloat { 3 * unit }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(items: [(String, Selector)], scale: CGFloat) {
        self.items = items
        unit = scale
        let menuFont = NSFont(name: "Arial", size: 11 * scale) ?? NSFont.systemFont(ofSize: 11 * scale)
        font = menuFont
        let widest = items.map { ($0.0 as NSString).size(withAttributes: [.font: menuFont]).width }.max() ?? 80
        super.init(frame: NSRect(x: 0, y: 0, width: ceil(widest) + 30 * scale, height: CGFloat(items.count) * 19 * scale + 6 * scale))
        setAccessibilityElement(true)
        setAccessibilityRole(.menu)
        setAccessibilityLabel(items.map(\.0).joined(separator: ", "))
    }
    required init?(coder: NSCoder) { fatalError() }
    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(tracking!)
        super.updateTrackingAreas()
    }
    private func row(at point: NSPoint) -> Int {
        guard bounds.insetBy(dx: inset, dy: inset).contains(point) else { return -1 }
        let index = Int((point.y - inset) / rowHeight)
        return items.indices.contains(index) ? index : -1
    }
    override func mouseMoved(with event: NSEvent) { selected = row(at: convert(event.locationInWindow, from: nil)) }
    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseExited(with event: NSEvent) { selected = -1 }
    override func mouseDown(with event: NSEvent) { selected = row(at: convert(event.locationInWindow, from: nil)) }
    override func mouseDragged(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseUp(with event: NSEvent) {
        let index = row(at: convert(event.locationInWindow, from: nil))
        if index >= 0 { choose?(index) } else { cancel?() }
    }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: cancel?()
        case 125: selected = selected < 0 ? 0 : (selected + 1) % max(1, items.count)
        case 126: selected = selected <= 0 ? items.count - 1 : selected - 1
        case 36, 76, 49: if selected >= 0 { choose?(selected) }
        default:
            if let prefix = event.charactersIgnoringModifiers?.lowercased(), !prefix.isEmpty,
               let index = items.firstIndex(where: { $0.0.lowercased().hasPrefix(prefix) }) { selected = index }
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        let light = NSColor(calibratedWhite: 0.95, alpha: 1)
        let dark = NSColor(calibratedRed: 0.19, green: 0.20, blue: 0.27, alpha: 1)
        Self.background.setFill(); bounds.fill()
        func fill(_ r: NSRect, _ c: NSColor) { c.setFill(); r.fill() }
        fill(NSRect(x: 0, y: 0, width: bounds.width, height: unit), light)
        fill(NSRect(x: 0, y: 0, width: unit, height: bounds.height), light)
        fill(NSRect(x: 0, y: bounds.height-unit, width: bounds.width, height: unit), dark)
        fill(NSRect(x: bounds.width-unit, y: 0, width: unit, height: bounds.height), dark)
        let blue = NSColor(calibratedRed: 0.04, green: 0.06, blue: 0.30, alpha: 1)
        for (i, item) in items.enumerated() {
            let y = inset + CGFloat(i) * rowHeight
            if i == selected { fill(NSRect(x: inset, y: y, width: bounds.width-2*inset, height: rowHeight), blue) }
            (item.0 as NSString).draw(at: NSPoint(x: 13*unit, y: y+3*unit), withAttributes: [.font: font, .foregroundColor: i == selected ? NSColor.white : NSColor.black])
        }
    }
}
