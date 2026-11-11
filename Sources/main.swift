import AppKit
import AVFoundation
import UniformTypeIdentifiers

let preferences = CommandLine.arguments.contains("--smoke-test") ? UserDefaults(suiteName: "local.winampclassic.smoketest")! : UserDefaults.standard
let green = NSColor(calibratedRed: 0.1, green: 1, blue: 0, alpha: 1)
let gold = NSColor(calibratedRed: 0.78, green: 0.69, blue: 0.37, alpha: 1)
struct Track: Codable { var path: String; var title: String; var duration: Double }

final class Player: NSObject {
    let engine = AVAudioEngine()
    let node = AVAudioPlayerNode()
    let eq = AVAudioUnitEQ(numberOfBands: 10)
    var file: AVAudioFile?
    var tracks: [Track] = []
    var current = -1
    var selected = -1
    var playing = false
    var offset: Double = 0
    var generation = 0
    var volume: Float = 0.75 { didSet { node.volume = volume; save() } }
    var balance: Float = 0 { didSet { node.pan = balance } }
    var autoEQ = preferences.bool(forKey: "autoEQ")
    var shuffle = false
    var repeatAll = false
    var eqOn = true { didSet { eq.bypass = !eqOn; preferences.set(eqOn, forKey: "eqOn") } }
    var gains: [Float] = Array(repeating: 0, count: 11)
    var spectrum = Array(repeating: Float(0), count: 19)
    var changed: (() -> Void)?
    var timer: Timer?
    let frequencies: [Float] = [70,180,320,600,1000,3000,6000,12000,14000,16000]
    var duration: Double { file.map { Double($0.length) / $0.processingFormat.sampleRate } ?? 0 }
    var position: Double {
        guard playing, let t = node.lastRenderTime, let p = node.playerTime(forNodeTime: t) else { return offset }
        return min(duration, offset + Double(p.sampleTime) / p.sampleRate)
    }
    override init() {
        super.init()
        engine.attach(node); engine.attach(eq)
        engine.connect(node, to: eq, format: nil)
        engine.connect(eq, to: engine.mainMixerNode, format: nil)
        for (i, f) in frequencies.enumerated() {
            eq.bands[i].filterType = .parametric; eq.bands[i].frequency = f
            eq.bands[i].bandwidth = 1; eq.bands[i].bypass = false
        }
        node.volume = volume
        if let data = preferences.data(forKey: "playlist"), let list = try? JSONDecoder().decode([Track].self, from: data) { tracks = list.filter { FileManager.default.fileExists(atPath: $0.path) } }
        if preferences.object(forKey: "volume") != nil { volume = preferences.float(forKey: "volume"); node.volume = volume }
        if let saved = preferences.array(forKey: "gains") as? [Float], saved.count == 11 {
            for (i, gain) in saved.enumerated() { setGain(i, gain) }
        }
        if preferences.object(forKey: "eqOn") != nil { eqOn = preferences.bool(forKey: "eqOn"); eq.bypass = !eqOn }
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            guard let samples = buffer.floatChannelData?[0] else { return }
            let count = min(Int(buffer.frameLength), 1024), rate = buffer.format.sampleRate
            var values = [Float](repeating: 0, count: 19)
            for band in 0..<19 {
                let freq = 65 * pow(1.345, Double(band))
                var re = 0.0, im = 0.0
                for j in stride(from: 0, to: count, by: 2) {
                    let window = 0.5 - 0.5 * cos(2 * Double.pi * Double(j) / Double(count))
                    let a = 2 * Double.pi * freq * Double(j) / rate, s = Double(samples[j]) * window
                    re += s * cos(a); im += s * sin(a)
                }
                values[band] = Float(min(1, max(0, (20 * log10(max(0.00001, sqrt(re*re+im*im) / Double(count))) + 75) / 60)))
            }
            DispatchQueue.main.async { self?.spectrum = values }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0/30, repeats: true) { [weak self] _ in self?.changed?() }
    }
    func save() {
        if let data = try? JSONEncoder().encode(tracks) { preferences.set(data, forKey: "playlist") }
        preferences.set(volume, forKey: "volume")
    }
    func add(_ urls: [URL]) {
        var added = false
        for url in urls {
            do {
                let f = try AVAudioFile(forReading: url)
                tracks.append(Track(path: url.path, title: url.deletingPathExtension().lastPathComponent, duration: Double(f.length)/f.processingFormat.sampleRate)); added = true
            } catch { NSSound.beep() }
        }
        if added { if selected < 0 { selected = 0 }; save(); changed?() }
    }
    func load(_ index: Int, autoplay: Bool = true) {
        guard tracks.indices.contains(index) else { return }
        stop()
        do {
            file = try AVAudioFile(forReading: URL(fileURLWithPath: tracks[index].path))
            engine.stop()
            engine.disconnectNodeOutput(node); engine.disconnectNodeOutput(eq)
            engine.connect(node, to: eq, format: file!.processingFormat)
            engine.connect(eq, to: engine.mainMixerNode, format: file!.processingFormat)
            current = index; selected = index; offset = 0
            if autoEQ, let saved = preferences.dictionary(forKey: "trackEQ")?[tracks[index].path] as? [Float], saved.count == 11 {
                for (i, gain) in saved.enumerated() { setGain(i,gain) }
            }
            if autoplay { resume() }
        } catch { alert("Не удалось открыть аудиофайл", error.localizedDescription) }
        changed?()
    }
    func resume() {
        if file == nil { if !tracks.isEmpty { load(max(0, selected)) }; return }
        guard let file else { return }
        if position >= duration - 0.02 { offset = 0 }
        let frame = AVAudioFramePosition(offset * file.processingFormat.sampleRate)
        let count = file.length - frame
        guard count > 0 else { return }
        generation += 1; let ticket = generation
        node.stop()
        node.scheduleSegment(file, startingFrame: frame, frameCount: AVAudioFrameCount(min(count, Int64(UInt32.max))), at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.generation == ticket, self.playing else { return }
                self.playing = false; self.offset = self.duration; self.next(automatic: true)
            }
        }
        do { if !engine.isRunning { try engine.start() }; node.play(); playing = true }
        catch { alert("Ошибка аудиодвижка", error.localizedDescription) }
    }
    func toggle() { if playing { pause() } else { resume() } }
    func pause() { offset = position; generation += 1; node.stop(); playing = false }
    func stop() { generation += 1; node.stop(); playing = false; offset = 0 }
    func seek(_ value: Double) { let wasPlaying = playing; pause(); offset = min(max(0, value), max(0, duration - 0.001)); if wasPlaying { resume() } }
    func next(automatic: Bool = false) {
        guard !tracks.isEmpty else { return }
        if shuffle { load(Int.random(in: 0..<tracks.count)); return }
        let index = current + 1
        if index < tracks.count { load(index) }
        else if repeatAll { load(0) }
        else if !automatic { load(0) }
    }
    func previous() { if position > 3 { seek(0) } else { load(max(0, current-1)) } }
    func removeSelected() {
        guard tracks.indices.contains(selected) else { return }
        let removed = selected
        if removed == current { stop(); file = nil; current = -1 }
        else if removed < current { current -= 1 }
        tracks.remove(at: removed); selected = min(removed, tracks.count-1); save()
    }
    func setGain(_ index: Int, _ value: Float) { gains[index] = value; preferences.set(gains, forKey: "gains");
        if autoEQ && tracks.indices.contains(current) {
            var presets = preferences.dictionary(forKey: "trackEQ") ?? [:]
            presets[tracks[current].path] = gains; preferences.set(presets, forKey: "trackEQ")
        }
        if index == 0 { eq.globalGain = value } else { eq.bands[index-1].gain = value } }
}
func alert(_ title: String, _ message: String) { let a = NSAlert(); a.messageText = title; a.informativeText = message; a.runModal() }
func timeString(_ seconds: Double) -> String { let s = max(0, Int(seconds)); return String(format: "%d:%02d", s/60, s%60) }

final class SkinView: NSView {
    let player: Player
    var scale: CGFloat = 1
    var showEQ = true, showPlaylist = true
    var scroll = 0
    var dragControl: Int?
    var elapsed = true
    var titleMarquee = Marquee()
    var playlistMarquee = Marquee()
    let ink = NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.17, alpha: 1)
    let face = NSColor(calibratedRed: 0.19, green: 0.20, blue: 0.29, alpha: 1)
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    var playlistY: CGFloat { showEQ ? 232 : 116 }
    var skinHeight: CGFloat { showPlaylist ? playlistY + 196 : (showEQ ? 232 : 116) }
    init(player: Player) {
        self.player = player
        super.init(frame: NSRect(x: 0, y: 0, width: 275, height: 428))
        registerForDraggedTypes([.fileURL]); player.changed = { [weak self] in self?.needsDisplay = true }
    }
    required init?(coder: NSCoder) { fatalError() }
    func rect(_ x: CGFloat,_ y: CGFloat,_ w: CGFloat,_ h: CGFloat,_ color: NSColor) { color.setFill(); NSRect(x:x,y:y,width:w,height:h).fill() }
    func line(_ x: CGFloat,_ y: CGFloat,_ w: CGFloat,_ color: NSColor) { rect(x,y,w,1,color) }
    func label(_ text: String,_ x: CGFloat,_ y: CGFloat,_ size: CGFloat = 7,_ color: NSColor = .white,_ bold: Bool = false) {
        let font = NSFont(name: bold ? "Menlo-Bold" : "Menlo", size: size) ?? .monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular)
        (text as NSString).draw(at: NSPoint(x:x,y:y), withAttributes: [.font:font,.foregroundColor:color])
    }
    func bitrate() -> Int {
        guard player.tracks.indices.contains(player.current), player.duration > 0,
              let attrs = try? FileManager.default.attributesOfItem(atPath:player.tracks[player.current].path), let size = attrs[.size] as? NSNumber else { return 0 }
        return Int(Double(truncating:size)*8/player.duration/1000)
    }
    var visibleRows: Int { 9 }
    let hdSkin = HDSkin()
    var sprites: [Int:NSImage] = [:]
    var crops: [String:NSImage] = [:]
    func spriteImage(_ id: Int) -> NSImage? {
        if let image = sprites[id] { return image }
        guard let root = Bundle.main.resourceURL, let image = NSImage(contentsOf:root.appendingPathComponent("Sprites/\(id).png")) else { return nil }
        if let remastered = hdSkin.sprite(id) {
            remastered.size = image.size
            sprites[id] = remastered; return remastered
        }
        sprites[id] = image; return image
    }
    func sprite(_ id: Int,_ x: CGFloat,_ y: CGFloat,_ w: CGFloat? = nil,_ h: CGFloat? = nil) {
        let id = pressedSprite(id)
        guard let image = spriteImage(id) else { return }
        let rect = NSRect(x:x,y:y,width:w ?? image.size.width,height:h ?? image.size.height)
        if id == 121 && hdSkin.available { hdSkin.drawGraph(in:rect); return }
        if hdSkin.available && hdSkin.needsPressedEffect(id) { hdSkin.drawDepressed(image,in:rect); return }
        image.draw(in:rect,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:[.interpolation:hdSkin.available && hdSkin.sprite(id) != nil ? NSImageInterpolation.high : NSImageInterpolation.none])
    }
    func crop(_ id: Int,_ sx: Int,_ sy: Int,_ w: Int,_ h: Int,_ x: CGFloat,_ y: CGFloat) {
        if hdSkin.drawSliderTrack(id,x:x,y:y,width:CGFloat(w),frame:sy/15) { return }
        if id == 110 && hdSkin.drawBand(x:x,y:y,level:(sy/65)*14+sx/15) { return }
        let key = "\(id):\(sx):\(sy):\(w):\(h)"
        if crops[key] == nil, let image = spriteImage(id), let cg = image.cgImage(forProposedRect:nil,context:nil,hints:nil), let part = cg.cropping(to:CGRect(x:sx,y:sy,width:w,height:h)) {
            crops[key] = NSImage(cgImage:part,size:NSSize(width:w,height:h))
        }
        crops[key]?.draw(in:NSRect(x:x,y:y,width:CGFloat(w),height:CGFloat(h)),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:[.interpolation:NSImageInterpolation.none])
    }
    func bitmapText(_ text: String,_ x: CGFloat,_ y: CGFloat) {
        let punctuation: [Character:Int] = [" ":267,".":269,":":270,"(":271,")":272,"-":273,"/":279,"?":292,"+":277,"_":276]
        for (i,c) in text.lowercased().enumerated() {
            let n = c.asciiValue.map(Int.init) ?? 0
            let id = (48...57).contains(n) ? 229+n-48 : ((97...122).contains(n) ? 239+n-97 : punctuation[c] ?? 292)
            sprite(id,x+CGFloat(i)*5,y)
        }
    }
    func bitmapField(_ text: String, in box: NSRect, rightAligned: Bool = false) {
        let interior = box.insetBy(dx:2,dy:2)
        guard interior.width > 0 else { return }
        let naturalWidth = CGFloat(text.count)*5
        let factor = min(1,interior.width/max(1,naturalWidth))
        let x = rightAligned ? interior.maxX-naturalWidth*factor : interior.minX
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect:interior).addClip()
        NSGraphicsContext.current?.cgContext.translateBy(x:x,y:interior.minY+max(0,(interior.height-6)/2))
        NSGraphicsContext.current?.cgContext.scaleBy(x:factor,y:1)
        bitmapText(text,0,0)
        NSGraphicsContext.restoreGraphicsState()
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill(); bounds.fill()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.imageInterpolation = .none
        NSGraphicsContext.current?.shouldAntialias = false
        NSGraphicsContext.current?.cgContext.scaleBy(x:scale,y:scale)
        sprite(17,0,0); sprite(167,0,0); sprite(179,10,22)
        if pressedKey == "close" { sprite(178,264,3) }
        if pressedKey == "minimize" { sprite(174,244,3) }
        sprite(player.playing ? 36 : (player.offset > 0 ? 37 : 38),24,28)
        sprite(player.playing ? 40 : 39,24,43)
        let seconds = Int(elapsed ? player.position : max(0,player.duration-player.position))
        let numbers = [min(9,seconds/600),(seconds/60)%10,(seconds%60)/10,seconds%10]
        for (i,n) in numbers.enumerated() { sprite(26+n,[CGFloat(48),60,78,90][i],26) }
        rect(72,30,2,2,green); rect(72,35,2,2,green)
        if !elapsed { sprite(25,40,32) }
        for i in 0..<19 {
            let level = player.playing ? Int(player.spectrum[i]*16) : 0
            for j in 0..<level { rect(24+CGFloat(i)*4,60-CGFloat(j),3,1,j > 12 ? .red : (j > 8 ? .yellow : green)) }
        }
        let hasTrack = player.tracks.indices.contains(player.current)
        let title = hasTrack ? "\(player.current+1). \(player.tracks[player.current].title) (\(timeString(player.duration)))" : "WINAMP - DROP YOUR MUSIC HERE"
        let bitmap = title.unicodeScalars.allSatisfy { $0.value < 128 }
        let titleFont = NSFont(name:"Menlo",size:7) ?? NSFont.monospacedSystemFont(ofSize:7,weight:.regular)
        let width = bitmap ? CGFloat(title.count)*5 : ceil((title as NSString).size(withAttributes:[.font:titleFont]).width)
        let shift = titleMarquee.offset(for:title,width:hasTrack ? width : 0,viewport:151)
        NSGraphicsContext.saveGraphicsState(); NSBezierPath(rect:NSRect(x:112,y:24,width:151,height:8)).addClip()
        func drawTitle(_ x: CGFloat) { if bitmap { bitmapText(title,x,25) } else { label(title,x,24,7,green) } }
        drawTitle(112-shift)
        if hasTrack && width > 151 { drawTitle(112-shift+width+Marquee.gap) }
        NSGraphicsContext.restoreGraphicsState()
        bitmapField(player.file == nil ? "" : "\(bitrate())",in:NSRect(x:109,y:40,width:21,height:12))
        bitmapField(player.file == nil ? "" : "\(Int((player.file?.processingFormat.sampleRate ?? 0)/1000))",in:NSRect(x:154,y:40,width:18,height:12))
        let stereo = (player.file?.processingFormat.channelCount ?? 0) > 1
        sprite(player.file != nil && !stereo ? 23 : 21,212,41); sprite(stereo ? 20 : 18,239,41)
        let volFrame = Int(player.volume*27)
        crop(202,0,volFrame*15,68,13,107,57); sprite(dragControl == 0 ? 205 : 203,107+CGFloat(player.volume)*51,58)
        let balanceFrame = Int(abs(player.balance)*27)
        crop(0,0,balanceFrame*15,38,13,177,57); sprite(dragControl == 1 ? 3 : 1,177+CGFloat((player.balance+1)/2)*24,58)
        sprite(showEQ ? 159 : 158,219,58); sprite(showPlaylist ? 163 : 162,242,58)
        sprite(145,16,72)
        let fraction = player.duration > 0 ? player.position/player.duration : 0
        sprite(dragControl == 2 ? 148 : 146,16+CGFloat(fraction)*219,72)
        for (i,id) in [5,7,9,11,13].enumerated() { sprite(id,16+CGFloat(i)*23,88) }
        sprite(15,136,89); sprite(player.shuffle ? 152 : 150,164,89); sprite(player.repeatAll ? 156 : 154,210,89)
        if hdSkin.available {
            rect(168,94,3,3,player.shuffle ? green : NSColor(calibratedRed:0.03,green:0.16,blue:0.04,alpha:1))
            rect(223,62,3,3,showEQ ? green : .darkGray); rect(246,62,3,3,showPlaylist ? green : .darkGray)
        }
        if showEQ { drawEQ() }; if showPlaylist { drawPlaylist(); drawPressedPlaylistControl() }
        NSGraphicsContext.restoreGraphicsState()
    }
    func drawEQ() {
        let y: CGFloat = 116
        sprite(107,0,y); sprite(109,0,y)
        if pressedKey == "eqClose" { sprite(142,264,y+3) }
        sprite(player.eqOn ? 115 : 113,14,y+18); sprite(player.autoEQ ? 119 : 117,40,y+18); sprite(122,217,y+18); sprite(121,86,y+17)
        if hdSkin.available {
            rect(18,y+22,3,3,player.eqOn ? green : .darkGray)
            rect(44,y+22,3,3,player.autoEQ ? green : .darkGray)
        }
        let curve = NSBezierPath(); curve.lineWidth = 1
        for i in 0..<10 {
            let p = NSPoint(x:88+CGFloat(i)*12,y:y+26-CGFloat(player.gains[i+1])/12*8)
            if i == 0 { curve.move(to:p) } else { curve.line(to:p) }
        }
        gold.setStroke(); curve.stroke()
        let xs: [CGFloat] = [21,78,96,114,132,150,168,186,204,222,240]
        for i in 0..<11 {
            let level = Int((12-player.gains[i])/24*27)
            let col = min(13,level%14), row = min(1,level/14)
            crop(110,col*15,row*65,14,63,xs[i],y+38)
            sprite(dragControl == 10+i ? 112 : 111,xs[i]+1,y+38+CGFloat(12-player.gains[i])/24*52)
        }
    }
    func drawPlaylist() {
        let y = playlistY
        rect(0,y,275,196,.black)
        sprite(52,0,y); sprite(48,25,y); sprite(48,50,y); sprite(49,75,y,12.5,20)
        sprite(53,87.5,y)
        sprite(51,187.5,y,12.5,20); sprite(50,200,y); sprite(50,225,y); sprite(54,250,y)
        if pressedKey == "plClose" { sprite(90,264,y+3) }
        for n in 0..<5 { sprite(55,0,y+20+CGFloat(n)*29); sprite(56,255,y+20+CGFloat(n)*29) }
        sprite(60,0,y+158); sprite(61,125,y+158)
        scroll = max(0,min(scroll,max(0,player.tracks.count-visibleRows)))
        let fraction = CGFloat(scroll)/CGFloat(max(1,player.tracks.count-visibleRows))
        sprite(57,261,y+20+fraction*119)
        NSGraphicsContext.saveGraphicsState(); NSBezierPath(rect:NSRect(x:12,y:y+20,width:243,height:138)).addClip()
        if player.tracks.isEmpty {
            playlistText("Drop audio files here",16,y+25,green)
            playlistText("or press ADD",16,y+39,green)
        }
        for row in 0..<visibleRows {
            let i = scroll+row; guard player.tracks.indices.contains(i) else { break }
            let yy = y+23+CGFloat(row)*14
            if i == player.selected { rect(12,yy-1,243,14,NSColor(calibratedRed:0,green:0,blue:0.3,alpha:1)) }
            let color: NSColor = i == player.current ? .white : green
            let font = NSFont(name:"Arial",size:12) ?? NSFont.systemFont(ofSize:12)
            let prefix = "\(i+1). "
            let prefixWidth = ceil((prefix as NSString).size(withAttributes:[.font:font]).width)
            let titleX = 14+prefixWidth
            let durationText = timeString(player.tracks[i].duration)
            let durationWidth = min(65,ceil((durationText as NSString).size(withAttributes:[.font:font]).width))
            let durationBox = NSRect(x:253-durationWidth,y:yy,width:durationWidth,height:14)
            let available = max(1,durationBox.minX-5-titleX)
            let titleWidth = ceil((player.tracks[i].title as NSString).size(withAttributes:[.font:font]).width)
            let shift = i == player.selected ? playlistMarquee.offset(for:"\(i):\(player.tracks[i].path)",width:titleWidth,viewport:available) : 0
            playlistText(prefix,14,yy,color)
            NSGraphicsContext.saveGraphicsState(); NSBezierPath(rect:NSRect(x:titleX,y:yy,width:available,height:14)).addClip()
            playlistText(player.tracks[i].title,titleX-shift,yy,color)
            if i == player.selected && titleWidth > available { playlistText(player.tracks[i].title,titleX-shift+titleWidth+Marquee.gap,yy,color) }
            NSGraphicsContext.restoreGraphicsState()
            NSGraphicsContext.saveGraphicsState(); NSBezierPath(rect:durationBox).addClip()
            playlistText(durationText,durationBox.minX,yy,color)
            NSGraphicsContext.restoreGraphicsState()
        }
        NSGraphicsContext.restoreGraphicsState()
        bitmapField("\(timeString(player.position))/\(timeString(player.tracks.reduce(0) { $0+$1.duration }))",in:NSRect(x:129,y:y+165,width:94,height:12))
        // The original mini transport ends at x=182. Keep six pixels clear before time.
        bitmapField(timeString(player.position),in:NSRect(x:188,y:y+178,width:35,height:12),rightAligned:true)
    }
    func playlistText(_ text: String,_ x: CGFloat,_ y: CGFloat,_ color: NSColor) {
        (text as NSString).draw(at:NSPoint(x:x,y:y),withAttributes:[.font:NSFont(name:"Arial",size:12) ?? NSFont.systemFont(ofSize:12),.foregroundColor:color])
    }
    func resizeSkin() { let size = NSSize(width:275*scale,height:skinHeight*scale); setFrameSize(size); window?.setContentSize(size); needsDisplay = true }
    func openFiles() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.allowedContentTypes = [.audio]; panel.canChooseDirectories = false
        if panel.runModal() == .OK { let empty = player.tracks.isEmpty; player.add(panel.urls); if empty { player.load(0) } }
    }
    var skinMenu: ClassicMenu?
    func menu(_ items: [(String,Selector)], at event: NSEvent) {
        skinMenu?.dismiss()
        guard let window else { return }
        let anchor: NSRect
        if let button = heldButton {
            let r = button.rect
            let local = NSRect(x:r.minX*scale,y:r.minY*scale,width:r.width*scale,height:r.height*scale)
            anchor = window.convertToScreen(convert(local,to:nil))
        } else {
            let p = window.convertPoint(toScreen:event.locationInWindow)
            anchor = NSRect(x:p.x,y:p.y,width:1,height:1)
        }
        let popup = ClassicMenu(items:items,target:self,anchor:anchor,scale:scale)
        skinMenu = popup
        popup.onClose = { [weak self] in self?.skinMenu = nil }
        popup.show()
    }
    @objc func resetEQ() { for i in 0..<11 { player.setGain(i,0) } }
    @objc func bassEQ() { resetEQ(); for (i,g) in [Float(6),5,3,1,0,0,1,2,2,1].enumerated() { player.setGain(i+1,g) } }
    @objc func rockEQ() { resetEQ(); for (i,g) in [Float(5),3,-2,-4,-2,2,4,5,5,4].enumerated() { player.setGain(i+1,g) } }
    @objc func removeTrack() { player.removeSelected() }
    @objc func clearList() { player.stop(); player.file = nil; player.tracks = []; player.current = -1; player.selected = -1; player.save() }
    @objc func sortList() {
        let path = player.tracks.indices.contains(player.current) ? player.tracks[player.current].path : nil
        player.tracks.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        player.current = player.tracks.firstIndex { $0.path == path } ?? -1; player.selected = player.current; player.save()
    }
    @objc func zoom() { scale = scale == 2 ? 3 : (scale == 3 ? 1 : 2); resizeSkin() }
    @objc func importList() {
        let p = NSOpenPanel(); p.allowedContentTypes = [UTType(filenameExtension:"m3u")!,UTType(filenameExtension:"m3u8")!]
        if p.runModal() == .OK, let url = p.url, let body = try? String(contentsOf:url,encoding:.utf8) {
            player.add(body.components(separatedBy:.newlines).filter { !$0.isEmpty && !$0.hasPrefix("#") }.map { line in line.hasPrefix("/") ? URL(fileURLWithPath:line) : url.deletingLastPathComponent().appendingPathComponent(line) })
        }
    }
    @objc func exportList() {
        let p = NSSavePanel(); p.nameFieldStringValue = "Playlist.m3u8"
        if p.runModal() == .OK, let url = p.url { do { try ("#EXTM3U\n"+player.tracks.map { "#EXTINF:\(Int($0.duration)),\($0.title)\n\($0.path)" }.joined(separator:"\n")).write(to:url,atomically:true,encoding:.utf8) } catch { alert("Не удалось сохранить плейлист",error.localizedDescription) } }
    }
    struct SkinButton {
        let key: String
        let rect: NSRect
    }
    var heldButton: SkinButton?
    var heldEvent: NSEvent?
    var heldInside = false
    var pressedKey: String? { heldInside ? heldButton?.key : nil }
    var buttons: [SkinButton] {
        var result: [SkinButton] = []
        func add(_ key: String,_ x: CGFloat,_ y: CGFloat,_ w: CGFloat,_ h: CGFloat) {
            result.append(SkinButton(key:key,rect:NSRect(x:x,y:y,width:w,height:h)))
        }
        for i in 0..<5 { add("transport\(i)",16+CGFloat(i)*23,88,23,18) }
        add("eject",136,89,22,16); add("shuffle",164,89,47,15); add("repeat",210,89,28,15)
        add("eq",219,58,23,12); add("pl",242,58,23,12)
        add("minimize",243,3,10,10); add("close",263,3,10,10)
        if showEQ {
            add("eqOn",14,134,26,12); add("eqAuto",40,134,32,12); add("presets",217,134,44,12)
            add("eqClose",263,119,10,10)
        }
        if showPlaylist {
            for (i,key) in ["add","remove","select","misc"].enumerated() { add(key,12+CGFloat(i)*29,playlistY+166,i == 3 ? 24 : 23,20) }
            add("list",230,playlistY+166,25,20); add("plClose",263,playlistY+3,10,10)
            for (i,key) in ["miniPrevious","miniPlay","miniPause","miniStop","miniNext","miniEject"].enumerated() {
                add(key,128+CGFloat(i)*9,playlistY+179,9,11)
            }
        }
        return result
    }
    func skinPoint(_ event: NSEvent) -> NSPoint {
        let p = convert(event.locationInWindow,from:nil)
        return NSPoint(x:p.x/scale,y:p.y/scale)
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = skinPoint(event)
        if let button = buttons.first(where: { $0.rect.contains(p) }) {
            heldButton = button; heldEvent = event; heldInside = true
            needsDisplay = true; displayIfNeeded()
        } else { performClick(with:event) }
    }
    override func mouseDragged(with event: NSEvent) {
        if let button = heldButton {
            heldInside = button.rect.contains(skinPoint(event)); needsDisplay = true
        } else { let p = skinPoint(event); updateSlider(p.x,p.y) }
    }
    override func mouseUp(with event: NSEvent) {
        if let button = heldButton, button.rect.contains(skinPoint(event)), let click = heldEvent {
            activateButton(button.key,event:click)
        }
        heldButton = nil; heldEvent = nil; heldInside = false; dragControl = nil; needsDisplay = true
    }
    func activateButton(_ key: String, event: NSEvent) {
        switch key {
        case "transport0", "miniPrevious": player.previous()
        case "transport1", "miniPlay":
            if player.file == nil && player.tracks.isEmpty { openFiles() }
            else if !player.playing { player.resume() }
        case "transport2", "miniPause": player.toggle()
        case "transport3", "miniStop": player.stop()
        case "transport4", "miniNext": player.next()
        case "eject", "miniEject", "add": openFiles()
        case "shuffle": player.shuffle.toggle()
        case "repeat": player.repeatAll.toggle()
        case "eq", "eqClose": showEQ.toggle(); resizeSkin()
        case "pl", "plClose": showPlaylist.toggle(); resizeSkin()
        case "minimize": window?.miniaturize(nil)
        case "close": NSApp.terminate(nil)
        case "eqOn": player.eqOn.toggle()
        case "eqAuto":
            player.autoEQ.toggle(); preferences.set(player.autoEQ,forKey:"autoEQ")
            if player.autoEQ { player.setGain(0,player.gains[0]) }
        case "presets": menu([("Flat",#selector(resetEQ)),("Bass boost",#selector(bassEQ)),("Rock",#selector(rockEQ))],at:event)
        case "remove": menu([("Remove selected",#selector(removeTrack)),("Clear playlist",#selector(clearList))],at:event)
        case "select": player.selected = max(0,player.current); scroll = max(0,player.selected-4)
        case "misc": menu([("Sort by title",#selector(sortList)),("Interface size: 1× / 2× / 3×",#selector(zoom))],at:event)
        case "list": menu([("Open playlist…",#selector(importList)),("Save playlist…",#selector(exportList))],at:event)
        default: break
        }
    }
    func drawPressedPlaylistControl() {
        guard let button = heldButton, heldInside,
              ["add","remove","select","misc","list","miniPrevious","miniPlay","miniPause","miniStop","miniNext","miniEject"].contains(button.key) else { return }
        let r = button.rect
        if hdSkin.drawPressedControl(r,playlistY:playlistY,key:button.key) { return }
        NSColor(calibratedWhite:0,alpha:0.22).setFill(); r.fill()
        line(r.minX,r.minY,r.width,ink); rect(r.minX,r.minY,1,r.height,ink)
        let light = NSColor(calibratedRed:0.65,green:0.69,blue:0.73,alpha:1)
        line(r.minX,r.maxY-1,r.width,light); rect(r.maxX-1,r.minY,1,r.height,light)
    }
    func pressedSprite(_ id: Int) -> Int {
        guard let key = pressedKey else { return id }
        switch key {
        case "transport0": return id == 5 ? 6 : id
        case "transport1": return id == 7 ? 8 : id
        case "transport2": return id == 9 ? 10 : id
        case "transport3": return id == 11 ? 12 : id
        case "transport4": return id == 13 ? 14 : id
        case "eject": return id == 15 ? 16 : id
        case "shuffle": return [150,152].contains(id) ? id+1 : id
        case "repeat": return [154,156].contains(id) ? id+1 : id
        case "eq": return id == 158 ? 160 : (id == 159 ? 161 : id)
        case "pl": return [162,163].contains(id) ? id+2 : id
        case "eqOn": return [113,115].contains(id) ? id+1 : id
        case "eqAuto": return [117,119].contains(id) ? id+1 : id
        case "presets": return id == 122 ? 123 : id
        default: return id
        }
    }
    func performClick(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let q = convert(event.locationInWindow,from:nil); let x = q.x/scale, y = q.y/scale
        if y < 14 {
            if x > 262 { NSApp.terminate(nil) } else if x > 242 { window?.miniaturize(nil) } else { window?.performDrag(with:event) }; return
        }
        if y >= 24 && y < 43 && x < 102 { elapsed.toggle() }
        if y >= 56 && y <= 70 {
            if x >= 109 && x <= 173 { dragControl = 0; updateSlider(x,y) }
            else if x >= 180 && x <= 211 { dragControl = 1; updateSlider(x,y) }
            else if x >= 220 && x <= 240 { showEQ.toggle(); resizeSkin() }
            else if x >= 243 { showPlaylist.toggle(); resizeSkin() }
        } else if y >= 72 && y <= 83 { dragControl = 2; updateSlider(x,y) }
        else if y >= 87 && y <= 107 {
            if x >= 16 && x < 39 { player.previous() }
            else if x < 62 { if player.file == nil && player.tracks.isEmpty { openFiles() } else if !player.playing { player.resume() } }
            else if x < 85 { player.toggle() }
            else if x < 108 { player.stop() }
            else if x < 131 { player.next() }
            else if x < 161 { openFiles() }
            else if x < 210 { player.shuffle.toggle() }
            else if x < 239 { player.repeatAll.toggle() }
        } else if showEQ && y >= 116 && y < 232 {
            if y < 131 { if x > 262 { showEQ = false; resizeSkin() } else { window?.performDrag(with:event) }; return }
            if y >= 133 && y <= 144 {
                if x < 41 { player.eqOn.toggle() }
                else if x < 74 { player.autoEQ.toggle(); preferences.set(player.autoEQ,forKey:"autoEQ"); if player.autoEQ { player.setGain(0,player.gains[0]) } }
                else if x > 220 { menu([("Flat",#selector(resetEQ)),("Bass boost",#selector(bassEQ)),("Rock",#selector(rockEQ))],at:event) }
            } else if y >= 152 && y <= 216 {
                let xs: [CGFloat] = [27,85,103,121,139,157,175,193,211,229,247]
                if let i = xs.indices.min(by: { abs(xs[$0]-x)<abs(xs[$1]-x) }), abs(xs[i]-x)<9 { dragControl = 10+i; updateSlider(x,y) }
            }
        } else if showPlaylist && y >= playlistY {
            let yy = y-playlistY
            if yy < 15 { if x > 262 { showPlaylist = false; resizeSkin() } else { window?.performDrag(with:event) }; return }
            if yy >= 20 && yy < 164 {
                if x >= 253 { dragControl = 3; updateSlider(x,y) }
                else { let i = scroll+Int((yy-23)/14); if player.tracks.indices.contains(i) { player.selected = i; if event.clickCount == 2 { player.load(i) } } }
            } else if yy >= 164 {
                if x < 38 { openFiles() }
                else if x < 67 { menu([("Remove selected",#selector(removeTrack)),("Clear playlist",#selector(clearList))],at:event) }
                else if x < 96 { player.selected = max(0,player.current); scroll = max(0,player.selected-4) }
                else if x < 127 { menu([("Sort by title",#selector(sortList)),("Interface size: 1× / 2× / 3×",#selector(zoom))],at:event) }
                else if x >= 232 { menu([("Open playlist…",#selector(importList)),("Save playlist…",#selector(exportList))],at:event) }
                else if x < 144 { player.previous() } else if x < 155 { player.resume() } else if x < 170 { player.toggle() } else if x < 184 { player.stop() } else if x < 198 { player.next() } else { openFiles() }
            }
        }
        needsDisplay = true
    }
    func updateSlider(_ x: CGFloat,_ y: CGFloat) {
        guard let control = dragControl else { return }
        func clamp(_ v: CGFloat) -> CGFloat { min(1,max(0,v)) }
        switch control {
        case 0: player.volume = Float(clamp((x-109)/64))
        case 1: player.balance = Float(clamp((x-180)/31))*2-1
        case 2: player.seek(Double(clamp((x-16)/219))*player.duration)
        case 3: scroll = Int(clamp((y-playlistY-25)/124)*CGFloat(max(0,player.tracks.count-visibleRows)))
        default: player.setGain(control-10,Float(12-clamp((y-156)/54)*24))
        }
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) { scroll = max(0,min(max(0,player.tracks.count-visibleRows),scroll+Int(event.scrollingDeltaY > 0 ? -1 : 1))); needsDisplay = true }
    override func rightMouseDown(with event: NSEvent) { menu([("Add audio files…",#selector(addAction)),("Open playlist…",#selector(importList)),("Save playlist…",#selector(exportList)),("Show equalizer",#selector(toggleEQ)),("Show playlist",#selector(togglePlaylist)),("Interface size: 1× / 2× / 3×",#selector(zoom))],at:event) }
    @objc func addAction() { openFiles() }
    @objc func toggleEQ() { showEQ.toggle(); resizeSkin() }
    @objc func togglePlaylist() { showPlaylist.toggle(); resizeSkin() }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 49: player.toggle()
        case 123: player.seek(player.position-5)
        case 124: player.seek(player.position+5)
        case 125: player.selected = min(player.tracks.count-1,player.selected+1); scroll = max(scroll,player.selected-visibleRows+1)
        case 126: player.selected = max(0,player.selected-1); scroll = min(scroll,player.selected)
        case 36: player.load(player.selected)
        case 51,117: player.removeSelected()
        default:
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "x": player.resume()
            case "c": player.toggle()
            case "v": player.stop()
            case "z": player.previous()
            case "b": player.next()
            default: super.keyDown(with:event)
            }
        }
        needsDisplay = true
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL] else { return false }
        let empty = player.tracks.isEmpty; player.add(urls); if empty { player.load(0) }; return true
    }
}
final class MainWindow: NSWindow { override var canBecomeKey: Bool { true }; override var canBecomeMain: Bool { true } }
final class AppDelegate: NSObject, NSApplicationDelegate {
    let player = Player()
    var window: NSWindow!
    var skin: SkinView!
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("WinampOriginal.icns"), let icon = NSImage(contentsOf:url) { NSApp.applicationIconImage = icon }
        skin = SkinView(player:player)
        window = MainWindow(contentRect:skin.frame,styleMask:[.borderless,.miniaturizable],backing:.buffered,defer:false)
        window.title = "Winamp Classic"; window.contentView = skin; window.backgroundColor = .black; window.hasShadow = true
        window.isMovableByWindowBackground = false; window.center(); window.makeKeyAndOrderFront(nil); window.makeFirstResponder(skin)
        let main = NSMenu(), app = NSMenu(), file = NSMenu(), view = NSMenu(), playback = NSMenu()
        func root(_ title: String,_ submenu: NSMenu) { let i = NSMenuItem(title:title,action:nil,keyEquivalent:""); i.submenu = submenu; main.addItem(i) }
        func item(_ title: String,_ selector: Selector,_ key: String,_ target: AnyObject,_ menu: NSMenu) { let i = NSMenuItem(title:title,action:selector,keyEquivalent:key); i.target = target; menu.addItem(i) }
        root("Winamp Classic",app); item("About Winamp Classic",#selector(about),"",self,app); app.addItem(.separator()); item("Quit Winamp Classic",#selector(NSApplication.terminate(_:)),"q",NSApp,app)
        root("File",file); item("Add audio files…",#selector(SkinView.addAction),"o",skin,file); item("Open playlist…",#selector(SkinView.importList),"",skin,file); item("Save playlist…",#selector(SkinView.exportList),"s",skin,file)
        root("Playback",playback); item("Play / Pause",#selector(playPause),"p",self,playback)
        root("View",view); item("Equalizer",#selector(SkinView.toggleEQ),"e",skin,view); item("Playlist",#selector(SkinView.togglePlaylist),"l",skin,view); item("Change scale",#selector(SkinView.zoom),"2",skin,view)
        NSApp.mainMenu = main; NSApp.activate(ignoringOtherApps:true)
        if CommandLine.arguments.contains("--smoke-test") {
            DispatchQueue.main.asyncAfter(deadline:.now()+0.5) { self.smokeTest() }
        }
    }
    @objc func playPause() { player.toggle() }
    @objc func about() { alert("Winamp Classic for Mac", "Классический интерфейс, нативный звук macOS.\nMP3, WAV, AIFF, AAC, M4A, FLAC и другие форматы AVFoundation.\n\nПробел — пауза · ← → — перемотка\nZ/X/C/V/B — назад/играть/пауза/стоп/вперёд\n⌘O — добавить файлы · ⌘2 — масштаб\nПеретаскивайте окно за заголовок, файлы — в плейлист.") }
    func application(_ sender: NSApplication, openFiles filenames: [String]) { player.add(filenames.map { URL(fileURLWithPath:$0) }); if player.current < 0 && !player.tracks.isEmpty { player.load(0) }; sender.reply(toOpenOrPrint:.success) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { player.save() }
    func resetSmokeState() { player.stop(); player.selected = player.current; player.removeSelected(); for i in 0..<11 { player.setGain(i,0) } }
    func smokeTest() {
        precondition(skin.scale == 1 && skin.bounds.size == NSSize(width:275,height:428), "Keep original compact geometry")
        precondition(skin.hdSkin.hasGeneratedPressedButtons, "Generated pressed sheet must be bundled and mapped")
        for id in [6,8,10,12,14,16,151,155,160,164,205,3,112,114,118,123,174,178] {
            precondition(skin.hdSkin.sprite(id) != nil && !skin.hdSkin.needsPressedEffect(id), "Use actual generated pressed artwork")
        }
        var marquee = Marquee()
        precondition(marquee.offset(for:"long",width:300,viewport:153,now:0) == 0)
        precondition(marquee.offset(for:"long",width:300,viewport:153,now:3) > 0)
        precondition(marquee.offset(for:"next",width:300,viewport:153,now:4) == 0)
        precondition(marquee.offset(for:"short",width:50,viewport:153,now:100) == 0)
        player.autoEQ = false; resetSmokeState(); player.tracks = []; player.current = -1; player.file = nil
        let menuPreview = ClassicMenu(items:[("Sort by title",#selector(SkinView.sortList)),("Interface size: 1× / 2× / 3×",#selector(SkinView.zoom))],target:skin,anchor:.zero,scale:1)
        menuPreview.savePreview(to:URL(fileURLWithPath:"/tmp/winamp-menu-preview.png"))
        let url = URL(fileURLWithPath:"/tmp/winamp-smoke.wav")
        do {
            let format = AVAudioFormat(standardFormatWithSampleRate:44100,channels:2)!
            let buffer = AVAudioPCMBuffer(pcmFormat:format,frameCapacity:88200)!; buffer.frameLength = 88200
            for channel in 0..<2 { for i in 0..<88200 { buffer.floatChannelData![channel][i] = Float(sin(Double(i)*2*Double.pi*440/44100))*0.1 } }
            do { let f = try AVAudioFile(forWriting:url,settings:format.settings); try f.write(from:buffer) }
            player.add([url]); player.load(player.tracks.count-1)
            precondition(player.playing); precondition(player.duration > 1.9)
            player.pause(); precondition(!player.playing); player.seek(0.5); precondition(abs(player.position-0.5)<0.01)
            player.setGain(1,6); precondition(player.eq.bands[0].gain == 6)
            player.eqOn = false; precondition(player.eq.bypass); player.eqOn = true
            player.stop()
            func event(_ type: NSEvent.EventType, _ x: CGFloat, _ y: CGFloat) -> NSEvent {
                let p = skin.convert(NSPoint(x:x*skin.scale,y:y*skin.scale),to:nil)
                return NSEvent.mouseEvent(with:type,location:p,modifierFlags:[],timestamp:0,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
            }
            skin.mouseDown(with:event(.leftMouseDown,50,95))
            precondition(skin.pressedSprite(7) == 8 && !player.playing, "Play must depress without activating before mouse-up")
            let pressedRep = skin.bitmapImageRepForCachingDisplay(in:skin.bounds)!
            skin.cacheDisplay(in:skin.bounds,to:pressedRep)
            try pressedRep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"/tmp/winamp-pressed-preview.png"))
            skin.mouseDragged(with:event(.leftMouseDragged,270,110))
            precondition(skin.pressedSprite(7) == 7, "Dragging outside must unpress")
            skin.mouseUp(with:event(.leftMouseUp,270,110))
            precondition(!player.playing, "Releasing outside must cancel")
            skin.mouseDown(with:event(.leftMouseDown,50,95))
            skin.mouseUp(with:event(.leftMouseUp,50,95))
            precondition(player.playing && skin.pressedKey == nil, "Releasing inside must play and clear pressed state")
            player.seek(0.5)

            DispatchQueue.main.asyncAfter(deadline:.now()+0.35) {
                precondition(self.player.position > 0.6, "Playback clock must advance")
                precondition(self.player.spectrum.max()! > 0, "Audio tap must receive a signal")
                let rep = self.skin.bitmapImageRepForCachingDisplay(in:self.skin.bounds)!
                self.skin.cacheDisplay(in:self.skin.bounds,to:rep)
                do { try rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"/tmp/winamp-preview.png")) }
                catch { print("SMOKE FAIL: screenshot: \(error)"); exit(1) }
                self.player.pause()
                self.player.offset = 3599999
                self.player.tracks[self.player.current].title = "Очень длинное название — длинная строка в плейлисте и дисплее / Long scrolling title with padding"
                self.player.tracks[self.player.current].duration = 36000000
                for zoom in [CGFloat(1),CGFloat(2),CGFloat(3)] {
                    self.skin.scale = zoom; self.skin.resizeSkin()
                    let layout = self.skin.bitmapImageRepForCachingDisplay(in:self.skin.bounds)!
                    self.skin.cacheDisplay(in:self.skin.bounds,to:layout)
                    try? layout.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/tmp/winamp-layout-\(Int(zoom)).png"))
                }
                self.skin.scale = 1; self.skin.resizeSkin()
                self.resetSmokeState()
                print("SMOKE PASS: load, play, pause, seek, EQ, bypass, mouse-down/up, drag-out cancellation, advancing audio clock, spectrum signal, stop, remove, marquee timing, layout at 1x/2x/3x, UI render")
                NSApp.terminate(nil)
            }
        } catch { print("SMOKE FAIL: \(error)"); exit(1) }
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
