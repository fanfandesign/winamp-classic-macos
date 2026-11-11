import Foundation

/// Pixel-aligned Winamp scrolling, with a short rest whenever a title changes.
struct Marquee {
    private var identity = ""
    private var started: TimeInterval = 0
    static let gap: CGFloat = 30

    mutating func offset(for key: String, width: CGFloat, viewport: CGFloat, now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> CGFloat {
        if key != identity { identity = key; started = now }
        guard width > viewport else { return 0 }
        let speed: CGFloat = 18
        let pause: TimeInterval = 1.2
        let cycle = pause + Double((width + Self.gap) / speed)
        let elapsed = max(0, now - started).truncatingRemainder(dividingBy: cycle)
        return floor(CGFloat(max(0, elapsed - pause)) * speed)
    }
}
