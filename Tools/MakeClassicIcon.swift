import AppKit
let root = URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
let resources = root.appendingPathComponent("Resources")
let source = NSImage(contentsOf:resources.appendingPathComponent("Winamp-original.png"))!
let folder = resources.appendingPathComponent("WinampClassic.iconset")
try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
for size in [16,32,64,128,256,512,1024] {
    let n = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    rep.size = NSSize(width:n,height:n)
    let context = NSGraphicsContext(bitmapImageRep:rep)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
    NSColor.clear.setFill(); NSRect(x:0,y:0,width:n,height:n).fill(using:.copy)
    let factor = n*0.94/max(source.size.width,source.size.height)
    let w = source.size.width*factor, h = source.size.height*factor
    source.draw(in:NSRect(x:(n-w)/2,y:(n-h)/2,width:w,height:h),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:false,hints:[.interpolation:NSImageInterpolation.high])
    NSGraphicsContext.restoreGraphicsState()
    let data = rep.representation(using:.png,properties:[:])!
    try data.write(to:folder.appendingPathComponent("size-\(size).png"))
}
print("Prepared classic transparent Winamp icons at 16–1024 px")
