import AppKit
let root = URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
let source = NSImage(contentsOf:root.appendingPathComponent("Resources/HD/classic-remastered.png"))!.cgImage(forProposedRect:nil,context:nil,hints:nil)!
let entries: [(String,NSRect)] = [
    ("previous",NSRect(x:16,y:88,width:23,height:18)),("play",NSRect(x:39,y:88,width:23,height:18)),("pause",NSRect(x:62,y:88,width:23,height:18)),("stop",NSRect(x:85,y:88,width:23,height:18)),("next",NSRect(x:108,y:88,width:23,height:18)),("eject",NSRect(x:136,y:89,width:22,height:16)),
    ("eq",NSRect(x:219,y:58,width:23,height:12)),("pl",NSRect(x:242,y:58,width:23,height:12)),("shuffle",NSRect(x:164,y:89,width:47,height:15)),("repeat",NSRect(x:210,y:89,width:28,height:15)),("on",NSRect(x:14,y:134,width:26,height:12)),("auto",NSRect(x:40,y:134,width:32,height:12)),
    ("presets",NSRect(x:217,y:134,width:44,height:12)),("add",NSRect(x:12,y:398,width:23,height:20)),("remove",NSRect(x:41,y:398,width:23,height:20)),("select",NSRect(x:70,y:398,width:23,height:20)),("misc",NSRect(x:99,y:398,width:24,height:20)),("list",NSRect(x:230,y:398,width:25,height:20)),
    ("volume",NSRect(x:145,y:58,width:14,height:11)),("balance",NSRect(x:189,y:58,width:14,height:11)),("seek",NSRect(x:109,y:72,width:29,height:10)),("band",NSRect(x:79,y:180,width:11,height:11)),("minimize",NSRect(x:244,y:3,width:9,height:9)),("close",NSRect(x:264,y:3,width:9,height:9))
]
let sheet = NSImage(size:NSSize(width:1200,height:560))
sheet.lockFocusFlipped(true)
NSColor(calibratedRed:0.17,green:0.18,blue:0.27,alpha:1).setFill(); NSRect(x:0,y:0,width:1200,height:560).fill()
var mapping: [[String:Any]] = []
for (i,entry) in entries.enumerated() {
    let r = entry.1
    let pixelRect = NSRect(x:r.minX*CGFloat(source.width)/275,y:r.minY*CGFloat(source.height)/428,width:r.width*CGFloat(source.width)/275,height:r.height*CGFloat(source.height)/428).integral
    let part = NSImage(cgImage:source.cropping(to:pixelRect)!,size:r.size)
    let dest = NSRect(x:CGFloat(i%6)*200+(200-r.width*4)/2,y:CGFloat(i/6)*140+(140-r.height*4)/2,width:r.width*4,height:r.height*4)
    part.draw(in:dest,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:[.interpolation:NSImageInterpolation.high])
    mapping.append(["name":entry.0,"x":dest.minX,"y":dest.minY,"width":dest.width,"height":dest.height])
}
sheet.unlockFocus()
let png = NSBitmapImageRep(data:sheet.tiffRepresentation!)!.representation(using:.png,properties:[:])!
try png.write(to:root.appendingPathComponent("Resources/HD/buttons-reference.png"))
try JSONSerialization.data(withJSONObject:["width":1200,"height":560,"buttons":mapping],options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("Resources/HD/buttons-layout.json"))
print("Prepared 24 aligned HD button references")
