import AppKit

/// High resolution generated artwork, cropped at the original skin's logical coordinates.
/// App geometry and hit regions remain in the original 275 × 428 coordinate system.
final class HDSkin {
    private let normal: CGImage?
    private let pressed: CGImage?
    private let pressedButtons: CGImage?
    private let buttonRegions: [String:NSRect]
    private var cache: [String:NSImage] = [:]
    var available: Bool { normal != nil }
    var hasGeneratedPressedButtons: Bool { pressedButtons != nil && buttonRegions.count == 24 }
    private let chassis = NSColor(calibratedRed:0.17,green:0.18,blue:0.27,alpha:1)

    init() {
        func load(_ name: String) -> CGImage? {
            guard let url = Bundle.main.resourceURL?.appendingPathComponent("HD/\(name).png"), let image = NSImage(contentsOf:url) else { return nil }
            return image.cgImage(forProposedRect:nil,context:nil,hints:nil)
        }
        normal = load("classic-remastered")
        pressed = load("classic-remastered-pressed")
        pressedButtons = load("buttons-pressed")
        var regions: [String:NSRect] = [:]
        if let url = Bundle.main.resourceURL?.appendingPathComponent("HD/buttons-layout.json"), let data = try? Data(contentsOf:url),
           let json = try? JSONSerialization.jsonObject(with:data) as? [String:Any], let entries = json["buttons"] as? [[String:Any]] {
            for item in entries {
                if let name = item["name"] as? String, let x = item["x"] as? Double, let y = item["y"] as? Double,
                   let width = item["width"] as? Double, let height = item["height"] as? Double {
                    regions[name] = NSRect(x:x,y:y,width:width,height:height)
                }
            }
        }
        buttonRegions = regions
    }
    private func buttonName(for id: Int) -> String? {
        switch id {
        case 6: return "previous"
        case 8: return "play"
        case 10: return "pause"
        case 12: return "stop"
        case 14: return "next"
        case 16: return "eject"
        case 148,149: return "seek"
        case 151,153: return "shuffle"
        case 155,157: return "repeat"
        case 160,161: return "eq"
        case 164,165: return "pl"
        case 205,206: return "volume"
        case 3,4: return "balance"
        case 112: return "band"
        case 114,116: return "on"
        case 118,120: return "auto"
        case 123: return "presets"
        case 173,174: return "minimize"
        case 177,178,141,142,90: return "close"
        default: return nil
        }
    }
    private func generatedButton(named name: String) -> NSImage? {
        let key = "button:\(name)"
        if let cached = cache[key] { return cached }
        guard let source = pressedButtons, let r = buttonRegions[name] else { return nil }
        let sx = CGFloat(source.width)/1200, sy = CGFloat(source.height)/560
        guard let part = source.cropping(to:CGRect(x:r.minX*sx,y:r.minY*sy,width:r.width*sx,height:r.height*sy).integral) else { return nil }
        let image = NSImage(cgImage:part,size:NSSize(width:r.width/4,height:r.height/4))
        cache[key] = image
        return image
    }
    func region(_ r: NSRect, down: Bool = false) -> NSImage? {
        guard let source = down ? (pressed ?? normal) : normal else { return nil }
        let key = "\(r):\(down)"
        if let image = cache[key] { return image }
        let sx = CGFloat(source.width)/275, sy = CGFloat(source.height)/428
        guard let cropped = source.cropping(to:CGRect(x:r.minX*sx,y:r.minY*sy,width:r.width*sx,height:r.height*sy).integral) else { return nil }
        let image = NSImage(cgImage:cropped,size:r.size)
        cache[key] = image
        return image
    }
    func sprite(_ id: Int) -> NSImage? {
        if let name = buttonName(for:id), let image = generatedButton(named:name) { return image }
        var r: NSRect?
        var down = false
        func box(_ x: CGFloat,_ y: CGFloat,_ w: CGFloat,_ h: CGFloat) { r = NSRect(x:x,y:y,width:w,height:h) }
        switch id {
        case 17: box(0,0,275,116)
        case 166,167: box(0,0,275,14)
        case 5...14:
            let index = (id-5)/2; down = id % 2 == 0
            box(16+CGFloat(index)*23,88,23,18)
        case 15,16: box(136,89,22,16); down = id == 16
        case 20: box(239,41,29,12)
        case 21,22,23: box(212,41,27,12)
        case 145: box(17,72,80,10)
        case 146...149: box(109,72,29,10); down = id >= 148
        case 150...153: box(164,89,47,15); down = id % 2 == 1
        case 154...157: box(210,89,28,15); down = id % 2 == 1
        case 158...161: box(219,58,23,12); down = id >= 160
        case 162...165: box(242,58,23,12); down = id >= 164
        case 203...206: box(145,58,14,11); down = id >= 205
        case 1...4: box(189,58,14,11); down = id >= 3
        case 107: box(0,116,275,116)
        case 108,109: box(0,116,275,14)
        case 111,112: box(79,180,11,11); down = id == 112
        case 113...116: box(14,134,26,12); down = id % 2 == 0
        case 117...120: box(40,134,32,12); down = id % 2 == 0
        case 122,123: box(217,134,44,12); down = id == 123
        case 173,174: box(244,3,9,9); down = true
        case 177,178: box(264,3,9,9); down = true
        case 141,142: box(264,119,9,9); down = true
        case 90: box(264,235,9,9); down = true
        case 45,52: box(0,232,25,20)
        case 41,48: box(25,232,25,20)
        case 42,49: box(62.5,232,25,20)
        case 46,53: box(87.5,232,100,20)
        case 44,51: box(187.5,232,25,20)
        case 43,50: box(225,232,25,20)
        case 47,54: box(250,232,25,20)
        case 55: box(0,252,12,29)
        case 56: box(255,281,20,29)
        case 57,58: box(261,252,8,18); down = id == 58
        case 60: box(0,390,125,38)
        case 61: box(125,390,150,38)
        default: return nil
        }
        guard let r else { return nil }
        return region(r,down:down)
    }
    func needsPressedEffect(_ id: Int) -> Bool {
        if let name = buttonName(for:id), generatedButton(named:name) != nil { return false }
        return pressed == nil && [6,8,10,12,14,16,148,149,151,153,155,157,160,161,164,165,205,206,3,4,112,114,116,118,120,123,173,174,177,178,141,142,90,58].contains(id)
    }
    /// Keep the HD face and icon, with the reversed Winamp bevel while the mouse is held.
    func drawDepressed(_ image: NSImage, in r: NSRect) {
        let edge: CGFloat = min(r.width,r.height) < 12 ? 1 : 1.5
        let dark = NSColor(calibratedRed:0.08,green:0.10,blue:0.14,alpha:1)
        dark.setFill(); r.fill()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect:r.insetBy(dx:edge,dy:edge)).addClip()
        draw(image,in:r.offsetBy(dx:0.5,dy:0.5))
        NSColor(calibratedWhite:0,alpha:0.17).setFill(); r.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor(calibratedRed:0.68,green:0.72,blue:0.75,alpha:1).setFill()
        NSRect(x:r.minX,y:r.maxY-0.5,width:r.width,height:0.5).fill()
        NSRect(x:r.maxX-0.5,y:r.minY,width:0.5,height:r.height).fill()
    }
    func draw(_ image: NSImage, in r: NSRect) {
        image.draw(in:r,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:[.interpolation:NSImageInterpolation.high])
    }
    /// Tracks must be live: clear the handle baked into the reference before drawing its live position.
    func drawSliderTrack(_ id: Int, x: CGFloat, y: CGFloat, width: CGFloat, frame: Int) -> Bool {
        guard available, id == 202 || id == 0 else { return false }
        chassis.setFill(); NSRect(x:x,y:y,width:width,height:13).fill()
        let bar = NSRect(x:x+1,y:y+4,width:width-2,height:5)
        NSColor(calibratedWhite:0.04,alpha:1).setFill(); bar.insetBy(dx:-1,dy:-1).fill()
        let level = CGFloat(frame)/27
        let color = id == 0 ? NSColor(calibratedRed:0.08,green:0.85,blue:0.02,alpha:1) : NSColor(calibratedRed:min(1,level*1.7),green:max(0.2,1-level*0.55),blue:0.01,alpha:1)
        NSGradient(starting:color.blended(withFraction:0.3,of:.white)!,ending:color.blended(withFraction:0.4,of:.black)!)!.draw(in:bar,angle:90)
        return true
    }
    func drawBand(x: CGFloat,y: CGFloat,level: Int) -> Bool {
        guard available else { return false }
        chassis.setFill(); NSRect(x:x,y:y,width:14,height:63).fill()
        let color = NSColor(calibratedRed:0.72+CGFloat(level)/27*0.25,green:0.91,blue:0.02,alpha:1)
        NSColor(calibratedWhite:0.035,alpha:1).setFill(); NSRect(x:x+4,y:y+1,width:6,height:60).fill()
        NSGradient(starting:color.blended(withFraction:0.2,of:.white)!,ending:color)!.draw(in:NSRect(x:x+5,y:y+2,width:4,height:58),angle:0)
        return true
    }
    func drawGraph(in rect: NSRect) {
        chassis.setFill(); rect.fill()
        NSColor(calibratedWhite:0.55,alpha:1).setFill()
        for i in 0..<10 { NSRect(x:rect.minX+4+CGFloat(i)*11,y:rect.minY+1,width:0.5,height:rect.height-2).fill() }
    }
    func drawPressedControl(_ rect: NSRect, playlistY: CGFloat, key: String) -> Bool {
        guard available else { return false }
        if ["add","remove","select","misc","list"].contains(key), let image = generatedButton(named:key) {
            draw(image,in:rect); return true
        }
        var source = rect; source.origin.y += 232-playlistY
        guard let image = region(source,down:true) else { return false }
        if pressed == nil { drawDepressed(image,in:rect) } else { draw(image,in:rect) }
        return true
    }
}
