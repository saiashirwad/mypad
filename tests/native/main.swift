import Foundation
import UIKit
import PencilKit

if CommandLine.arguments.count == 3 {
    let before = try PKDrawing(data: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
    let after = try PKDrawing(data: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))
    assert(before.strokes.count == after.strokes.count)
    for (a, b) in zip(before.strokes, after.strokes) {
        assert(a.renderBounds == b.renderBounds && a.transform == b.transform && a.ink.inkType == b.ink.inkType && a.ink.color.isEqual(b.ink.color))
        assert(a.path.count == b.path.count)
        for i in 0..<a.path.count {
            let x = a.path[i], y = b.path[i]
            assert(x.location == y.location && x.size == y.size && x.opacity == y.opacity && x.force == y.force
                   && x.azimuth == y.azimuth && x.altitude == y.altitude && x.timeOffset == y.timeOffset)
        }
    }
    print("PASS physical restore preserves all \(before.strokes.count) native strokes and their control points")
    exit(0)
}

let base = FileManager.default.temporaryDirectory.appendingPathComponent("mypad-native-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: base) }
let support = base.appendingPathComponent("support")
let documents = base.appendingPathComponent("documents")
let bridgeRoot = documents.appendingPathComponent("AgentBridgePrototype")
try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: bridgeRoot.appendingPathComponent("assets"), withIntermediateDirectories: true)
let points = [CGPoint(x: 100, y: 100), CGPoint(x: 180, y: 160)].enumerated().map {
    PKStrokePoint(location: $0.element, timeOffset: Double($0.offset) * 0.1,
                  size: CGSize(width: 2, height: 2), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
}
let ink = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .blue), path: PKStrokePath(controlPoints: points, creationDate: Date()))])
let image = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100)).image { context in
    UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
}
let refID = UUID().uuidString.lowercased()
let artifact = CanvasArtifact(id: refID, title: "Legacy", imageFile: refID + ".png", x: 140, y: 140, width: 600, height: 600)
try image.pngData()!.write(to: bridgeRoot.appendingPathComponent("assets/" + artifact.imageFile))
try JSONEncoder().encode([artifact]).write(to: bridgeRoot.appendingPathComponent("board.json"))
try ink.dataRepresentation().write(to: support.appendingPathComponent("Canvas.drawing"))
let store = try DrawingStore(supportDirectory: support, documentsDirectory: documents)
assert(store.drawing.strokes.count == 1 && store.state.artifacts.count == 1)
assert(FileManager.default.fileExists(atPath: support.appendingPathComponent("Canvas.drawing").path))
print("PASS migration preserves ink, references, and legacy files")

let bridge = try AgentBridge(store: store, rootDirectory: bridgeRoot)
func command(_ kind: String, id: String = UUID().uuidString.lowercased(), revision: Int? = nil,
             expiry: Double = Date().timeIntervalSince1970 + 30, restoreFolder: String? = nil,
             extra: [String: Any] = [:]) throws -> [String: Any] {
    var value: [String: Any] = ["id": id, "kind": kind, "title": "Test", "x": 0, "y": 0,
                               "width": 0, "height": 0, "expiresAt": expiry]
    for (key, content) in extra { value[key] = content }
    if let revision { value["expectedRevision"] = revision }
    if let restoreFolder { value["restoreFolder"] = restoreFolder }
    try JSONSerialization.data(withJSONObject: value).write(to: bridgeRoot.appendingPathComponent("inbox/\(id).json"))
    let ack = bridgeRoot.appendingPathComponent("outbox/ack-\(id).json")
    // A write finishes on the poll after its render completes; a replayed command leaves its inbox file for one more poll.
    for _ in 0..<4 where !FileManager.default.fileExists(atPath: ack.path) {
        bridge.poll(view: BoardView(), visibleRect: CGRect(x: 100, y: 100, width: 800, height: 600), changed: { _, _ in }, render: { _ in image })
    }
    let data = try Data(contentsOf: ack)
    return try JSONSerialization.jsonObject(with: data) as! [String: Any]
}
let capture = try command("capture")
let captureID = capture["id"] as! String
let snapshot = try JSONDecoder().decode(AgentBridge.Snapshot.self,
    from: Data(contentsOf: bridgeRoot.appendingPathComponent("outbox/snapshot-\(captureID).json")))
assert(snapshot.strokeCount == 1 && snapshot.revision == store.state.revision)
print("PASS capture correlates image, metadata, and revision")

let backup = try command("backup")
let backupPath = bridgeRoot.appendingPathComponent("outbox/" + (backup["backupFolder"] as! String))
let savedInk = try PKDrawing(data: Data(contentsOf: backupPath.appendingPathComponent("ink.drawing")))
assert(savedInk.strokes.count == 1)
print("PASS full backup retains real editable PencilKit strokes")

store.updateDrawing(PKDrawing(strokes: ink.strokes + ink.strokes))
store.save { _ in }
let stale = try command("clear", revision: snapshot.revision)
assert(stale["code"] as? String == "revision_conflict" && store.drawing.strokes.count == 2)
let expired = try command("clear", revision: store.state.revision, expiry: Date().timeIntervalSince1970 - 1)
assert(expired["code"] as? String == "expired" && store.drawing.strokes.count == 2)
print("PASS stale and expired destructive requests preserve new ink")

let clearID = UUID().uuidString.lowercased()
let cleared = try command("clear", id: clearID, revision: store.state.revision)
let clearedRevision = store.state.revision
assert(cleared["status"] as? String == "ok" && store.drawing.strokes.isEmpty && store.state.artifacts.isEmpty)
let reopened = try DrawingStore(supportDirectory: support, documentsDirectory: documents)
assert(reopened.drawing.strokes.isEmpty && reopened.state.artifacts.isEmpty)
print("PASS clear persists one coherent empty board after queued autosave")

try FileManager.default.removeItem(at: bridgeRoot.appendingPathComponent("outbox/ack-\(clearID).json"))
let replay = try command("clear", id: clearID, revision: snapshot.revision)
assert(replay["status"] as? String == "ok" && store.state.revision == clearedRevision)
print("PASS interrupted receipt recovers without reapplying mutation")

let restoreID = UUID().uuidString.lowercased()
try FileManager.default.copyItem(at: backupPath, to: bridgeRoot.appendingPathComponent("restore/" + restoreID))
let restored = try command("restore", id: restoreID, revision: store.state.revision, restoreFolder: restoreID)
assert(restored["status"] as? String == "ok" && store.drawing.strokes.count == 1 && store.state.artifacts.count == 1)
let reopenedRestored = try DrawingStore(supportDirectory: support, documentsDirectory: documents)
assert(reopenedRestored.drawing.strokes.count == 1 && reopenedRestored.state.artifacts.count == 1)
print("PASS restore recovers editable ink, references, and persisted board")

let badID = UUID().uuidString.lowercased()
let badFolder = bridgeRoot.appendingPathComponent("restore/" + badID)
try FileManager.default.copyItem(at: backupPath, to: badFolder)
try Data("invalid ink".utf8).write(to: badFolder.appendingPathComponent("ink.drawing"))
let beforeInvalid = store.state.revision
let invalid = try command("restore", id: badID, revision: beforeInvalid, restoreFolder: badID)
assert(invalid["status"] as? String == "error" && store.state.revision == beforeInvalid && store.drawing.strokes.count == 1)
print("PASS corrupt native ink cannot replace the current board")

let putID = UUID().uuidString.lowercased()
let upload = "upload-\(putID).png"
try image.pngData()!.write(to: bridgeRoot.appendingPathComponent("assets/" + upload))
let placed = try command("image", id: putID, extra: ["imageFile": upload])
assert(placed["status"] as? String == "ok" && store.state.artifacts.count == 2)
assert((placed["reference"] as? [String: Any])?["id"] as? String == putID)
let inserted = store.state.artifacts.last!
assert(inserted.width == 520 && inserted.height == 520 && inserted.x == 240 && inserted.y == 140)
_ = try command("image", id: putID, extra: ["imageFile": upload])
assert(store.state.artifacts.count == 2)
print("PASS default image placement fits the view and replay does not duplicate it")
let invalidImage = try command("image", extra: ["imageFile": "../outside.png"])
assert(invalidImage["status"] as? String == "error" && store.state.artifacts.count == 2)
print("PASS invalid image paths leave references unchanged")

let strokesBefore = store.drawing.strokes.count
bridge.renderer = { _, _, width, done in
    let png = UIGraphicsImageRenderer(size: CGSize(width: width * 2, height: 200)).image { context in
        UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: width * 2, height: 200))
    }.pngData()!
    done(.success((png: png, height: 100)))
}
let source = "write-source.md"
try Data("# hi".utf8).write(to: bridgeRoot.appendingPathComponent("assets/" + source))
let writeArgs: [String: Any] = ["sourceFile": source, "format": "md", "protocolVersion": 2]
let writeID = UUID().uuidString.lowercased()
let written = try command("write", id: writeID, extra: writeArgs.merging(["width": 300]) { $1 })
assert(written["status"] as? String == "ok" && store.state.artifacts.count == 3)
let centered = store.state.artifacts.last!.frame
assert(centered.width == 300 && centered.height == 100 && centered.minX == 350)
assert(store.drawing.strokes.allSatisfy { !$0.renderBounds.intersects(centered) })
assert(store.state.artifacts.dropLast().allSatisfy { !$0.frame.intersects(centered) })
print("PASS write renders its source centered in view, below anything it would cover")
assert(store.state.artifacts.last!.adaptive == true && store.state.artifacts.first!.adaptive == nil
       && store.state.artifacts.first { $0.id == putID }!.adaptive == false)
let sample = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 1), format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }()).image { context in
    UIColor(red: 0.11, green: 0.14, blue: 0.19, alpha: 1).setFill(); context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
}
func rgba(_ image: UIImage, _ x: Int) -> [UInt8] {
    var px = [UInt8](repeating: 0, count: 8)
    let ctx = CGContext(data: &px, width: 2, height: 1, bitsPerComponent: 8, bytesPerRow: 8, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image.cgImage!, in: CGRect(x: 0, y: 0, width: 2, height: 1))
    return Array(px[x * 4..<x * 4 + 4])
}
let dark = WriteRenderer.darkVariant(sample)!
let textPixel = rgba(dark, 0), clear = rgba(dark, 1)
assert(textPixel[3] == 255 && textPixel[0] > 200 && textPixel[1] > 200 && textPixel[2] > 200, "text should turn light: \(textPixel)")
assert(clear[3] == 0, "transparent stays transparent: \(clear)")
assert(WriteRenderer.hasTransparentBackground(UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { _ in }))
assert(!WriteRenderer.hasTransparentBackground(image))
print("PASS writes are marked adaptive and their dark version keeps transparency")
let belowID = UUID().uuidString.lowercased()
_ = try command("write", id: belowID, extra: writeArgs.merging(["width": 300, "below": writeID]) { $1 })
assert(store.state.artifacts.last!.frame == CGRect(x: 350, y: centered.maxY + 40, width: 300, height: 100))
print("PASS write --below places it under its anchor")
let rewritten = try command("write", extra: writeArgs.merging(["target": writeID]) { $1 })
assert(rewritten["message"] as? String == "Reference replaced" && store.state.artifacts.count == 4)
assert(store.state.artifacts.first { $0.id == writeID }!.frame == centered)
print("PASS write --replace keeps the id, origin and width")
let upload2 = "upload-replacement.png"
try UIGraphicsImageRenderer(size: CGSize(width: 200, height: 100)).image { _ in }.pngData()!
    .write(to: bridgeRoot.appendingPathComponent("assets/" + upload2))
let oldFile = store.state.artifacts.first { $0.id == putID }!.imageFile
_ = try command("image", extra: ["imageFile": upload2, "target": putID, "protocolVersion": 2])
let swapped = store.state.artifacts.first { $0.id == putID }!
assert(swapped.width == 520 && swapped.height == 260 && swapped.x == 240 && swapped.imageFile != oldFile)
assert(!FileManager.default.fileExists(atPath: store.root.appendingPathComponent("assets/" + oldFile).path))
print("PASS put --replace swaps the image, keeps id and origin, and drops the old asset")
let removed = try command("remove", extra: ["target": belowID, "protocolVersion": 2])
assert(removed["status"] as? String == "ok" && store.state.artifacts.count == 3 && store.drawing.strokes.count == strokesBefore)
let missing = try command("remove", extra: ["target": belowID, "protocolVersion": 2])
assert(missing["code"] as? String == "unknown_reference")
print("PASS remove deletes one reference, keeps ink, and reports unknown ids")
let future = try command("status", extra: ["protocolVersion": 3])
assert(future["status"] as? String == "error")
print("PASS unknown protocol versions are rejected")

try Data("{incomplete".utf8).write(to: bridgeRoot.appendingPathComponent("inbox/00000000-partial.json"))
let responsive = try command("status")
assert(responsive["status"] as? String == "ok")
print("PASS incomplete inbox files do not block later valid commands")
