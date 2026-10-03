import UIKit
import PencilKit

// A paired-device file mailbox; board state and PencilKit ink live in DrawingStore.
struct CanvasArtifact: Codable {
    let id: String
    let title: String
    let imageFile: String
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
    /// Written text and drawings are shown color-inverted (hues kept) on the dark board; uploaded PNGs are not.
    /// Unset on references from before this flag: those count as written when their background is transparent.
    var adaptive: Bool? = nil
    var frame: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

struct DiagramScene: Codable {
    struct Node: Codable {
        let id: String
        let label: String
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
        let height: CGFloat
        var frame: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    }
    struct Edge: Codable {
        let from: String
        let to: String
        let label: String?
    }
    let nodes: [Node]
    let edges: [Edge]

    func image(size: CGSize) throws -> UIImage {
        guard nodes.count <= 100, edges.count <= 200,
              Set(nodes.map(\.id)).count == nodes.count,
              nodes.allSatisfy({ $0.width > 0 && $0.height > 0 && CGRect(origin: .zero, size: size).contains($0.frame) }),
              edges.allSatisfy({ edge in nodes.contains { $0.id == edge.from } && nodes.contains { $0.id == edge.to } })
        else { throw BridgeFailure("Invalid diagram bounds or node references") }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            UIColor.white.setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 18).fill()
            for edge in edges {
                guard let from = nodes.first(where: { $0.id == edge.from }),
                      let to = nodes.first(where: { $0.id == edge.to }) else { continue }
                let a = CGPoint(x: from.frame.midX, y: from.frame.midY)
                let b = CGPoint(x: to.frame.midX, y: to.frame.midY)
                let dx = b.x - a.x, dy = b.y - a.y
                guard abs(dx) + abs(dy) > 0 else { continue }
                let startScale = 1 / max(abs(dx) / (from.width / 2), abs(dy) / (from.height / 2))
                let endScale = 1 / max(abs(dx) / (to.width / 2), abs(dy) / (to.height / 2))
                let start = CGPoint(x: a.x + dx * startScale, y: a.y + dy * startScale)
                let end = CGPoint(x: b.x - dx * endScale, y: b.y - dy * endScale)
                cg.setStrokeColor(UIColor(red: 0.35, green: 0.42, blue: 0.48, alpha: 1).cgColor)
                cg.setLineWidth(2)
                cg.move(to: start)
                cg.addLine(to: end)
                let angle = atan2(dy, dx)
                cg.move(to: CGPoint(x: end.x - 11 * cos(angle - 0.45), y: end.y - 11 * sin(angle - 0.45)))
                cg.addLine(to: end)
                cg.addLine(to: CGPoint(x: end.x - 11 * cos(angle + 0.45), y: end.y - 11 * sin(angle + 0.45)))
                cg.strokePath()
                if let label = edge.label {
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 14), .foregroundColor: UIColor.darkGray,
                        .backgroundColor: UIColor.white
                    ]
                    let text = label as NSString
                    let textSize = text.size(withAttributes: attributes)
                    text.draw(at: CGPoint(x: (start.x + end.x - textSize.width) / 2,
                                          y: (start.y + end.y) / 2 - textSize.height - 5), withAttributes: attributes)
                }
            }
            for node in nodes {
                let path = UIBezierPath(roundedRect: node.frame, cornerRadius: 12)
                UIColor(red: 0.94, green: 0.97, blue: 0.96, alpha: 1).setFill()
                path.fill()
                UIColor(red: 0.22, green: 0.40, blue: 0.35, alpha: 1).setStroke()
                path.lineWidth = 1.5
                path.stroke()
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .center
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 19, weight: .medium),
                    .foregroundColor: UIColor(red: 0.12, green: 0.22, blue: 0.20, alpha: 1),
                    .paragraphStyle: paragraph
                ]
                let rect = node.frame.insetBy(dx: 12, dy: 12)
                let height = (node.label as NSString).boundingRect(
                    with: rect.size, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil
                ).height
                (node.label as NSString).draw(
                    in: CGRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height),
                    withAttributes: attributes
                )
            }
        }
    }
}

struct BridgeFailure: LocalizedError {
    let message: String
    let code: String
    init(_ message: String, code: String = "invalid_input") { self.message = message; self.code = code }
    var errorDescription: String? { message }
}

struct BackupReference: Codable {
    struct Frame: Codable { let x: CGFloat; let y: CGFloat; let width: CGFloat; let height: CGFloat }
    let id: String
    let title: String
    let file: String
    let frame: Frame
    var adaptive: Bool? = nil
}

struct BackupManifest: Codable {
    struct Size: Codable { let width: CGFloat; let height: CGFloat }
    let format: String
    let version: Int
    let createdAt: String
    let revision: Int
    let boardSize: Size
    let view: BoardView
    let inkFile: String
    let previewFile: String
    let references: [BackupReference]
}

final class AgentBridge {
    struct Command: Codable {
        let id: String
        let kind: String
        let title: String
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
        let height: CGFloat
        let imageFile: String?
        let scene: DiagramScene?
        let expiresAt: Double?
        let expectedRevision: Int?
        let restoreFolder: String?
        let protocolVersion: Int?
        // v2: `write` source and format, `remove`/replace target, write placement.
        let sourceFile: String?
        let format: String?
        let target: String?
        let below: String?
        let rightOf: String?
        let positioned: Bool?
    }
    struct Snapshot: Codable {
        let id: String
        let imageFile: String
        let inkFile: String
        let createdAt: String
        let viewport: CGRect
        let pixelWidth: Int
        let pixelHeight: Int
        let strokeCount: Int
        let artifactIDs: [String]
        let revision: Int
    }
    struct Receipt: Codable {
        let id: String
        let status: String
        let message: String
        let code: String?
        let imageFile: String?
        let backupFolder: String?
        let revision: Int
        let reference: CanvasArtifact?
    }

    let root: URL
    let store: DrawingStore
    /// Write renders finish asynchronously; the command stays in the inbox until its outcome is here.
    private var rendering: Set<String> = []
    private var renders: [String: Result<(png: Data, height: CGFloat, width: CGFloat), Error>] = [:]
    var renderer: (String, String, CGFloat, @escaping (Result<(png: Data, height: CGFloat), Error>) -> Void) -> Void = WriteRenderer.render
    var artifacts: [CanvasArtifact] { store.state.artifacts }
    private let encoder: JSONEncoder = {
        let value = JSONEncoder(); value.outputFormatting = [.prettyPrinted, .sortedKeys]; return value
    }()

    init(store: DrawingStore, rootDirectory: URL? = nil) throws {
        self.store = store
        root = rootDirectory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AgentBridgePrototype", isDirectory: true)
        for name in ["inbox", "assets", "outbox", "restore"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
    }

    func image(for artifact: CanvasArtifact) -> UIImage? { store.image(for: artifact) }

    /// `changed(resetInk, focus)`: clear/restore reset the ink; a new placement may need bringing into view.
    func poll(view: BoardView, visibleRect: CGRect, changed: (Bool, CGRect?) -> Void,
              render: (CGRect) throws -> UIImage) {
        store.updateView(view)
        let inbox = root.appendingPathComponent("inbox")
        guard let urls = try? FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil) else { return }
        var processed = false
        for url in urls.filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            if processed { break }
            guard let data = try? Data(contentsOf: url),
                  let command = try? JSONDecoder().decode(Command.self, from: data),
                  UUID(uuidString: command.id) != nil, url.lastPathComponent == "\(command.id).json" else { continue }
            processed = true
            let ack = root.appendingPathComponent("outbox/ack-\(command.id).json")
            if FileManager.default.fileExists(atPath: ack.path) {
                try? FileManager.default.removeItem(at: url); continue
            }
            do {
                if let version = command.protocolVersion, !(1...2).contains(version) {
                    throw BridgeFailure("Unsupported command protocol version")
                }
                // Recover a committed mutation if receipt publication was interrupted.
                if let revision = store.state.appliedCommands[command.id] {
                    try receipt(command.id, message: "Already applied", revision: revision,
                                reference: artifacts.first(where: { $0.id == command.id }))
                    try FileManager.default.removeItem(at: url); continue
                }
                let exported = (command.kind == "capture" && FileManager.default.fileExists(atPath: root.appendingPathComponent("outbox/snapshot-\(command.id).json").path))
                    || (command.kind == "backup" && FileManager.default.fileExists(atPath: root.appendingPathComponent("outbox/backup-\(command.id)/manifest.json").path))
                if let expiry = command.expiresAt, expiry <= Date().timeIntervalSince1970, !exported {
                    throw BridgeFailure("Command expired before application", code: "expired")
                }
                if ["clear", "restore"].contains(command.kind) {
                    guard command.expiresAt != nil else { throw BridgeFailure("Destructive command requires expiry") }
                    guard command.expectedRevision == store.state.revision else {
                        throw BridgeFailure("Board changed; capture again before \(command.kind)", code: "revision_conflict")
                    }
                }
                switch command.kind {
                case "status":
                    try receipt(command.id, message: "App responsive")
                case "capture":
                    let metadata = root.appendingPathComponent("outbox/snapshot-\(command.id).json")
                    let snapshot: Snapshot
                    if FileManager.default.fileExists(atPath: metadata.path) {
                        snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: metadata))
                    } else {
                        try store.flush()
                        snapshot = try export(id: command.id, image: render(visibleRect), viewport: visibleRect)
                    }
                    try receipt(command.id, message: "Captured current view", imageFile: snapshot.imageFile, revision: snapshot.revision)
                case "backup":
                    let name = "backup-\(command.id)"
                    let metadata = root.appendingPathComponent("outbox/\(name)/manifest.json")
                    if !FileManager.default.fileExists(atPath: metadata.path) {
                        try store.flush()
                        _ = try backup(id: command.id, preview: render(CGRect(x: 0, y: 0, width: 3000, height: 3000)))
                    }
                    let manifest = try JSONDecoder().decode(BackupManifest.self, from: Data(contentsOf: metadata))
                    try receipt(command.id, message: "Full board staged", backupFolder: name, revision: manifest.revision)
                case "clear":
                    try store.commit(artifacts: [], drawing: PKDrawing(), view: BoardView(), commandID: command.id)
                    changed(true, nil)
                    try receipt(command.id, message: "Board cleared")
                case "restore":
                    try restore(command)
                    changed(true, nil)
                    try receipt(command.id, message: "Board restored")
                case "remove":
                    guard let id = command.target, let old = artifacts.first(where: { $0.id == id }) else {
                        throw BridgeFailure("No reference with that id is on the board", code: "unknown_reference")
                    }
                    try store.commit(artifacts: artifacts.filter { $0.id != id }, drawing: store.drawing, view: view, commandID: command.id)
                    try? FileManager.default.removeItem(at: store.root.appendingPathComponent("assets/" + old.imageFile))
                    changed(false, nil)
                    try receipt(command.id, message: "Reference removed")
                case "write":
                    guard let rendered = try renderedWrite(command) else { return }
                    try place(command, png: rendered.png, size: CGSize(width: rendered.width, height: rendered.height),
                              visibleRect: visibleRect, view: view, changed: changed)
                case "image" where command.target != nil:
                    let data = try uploadedImage(command)
                    guard let old = artifacts.first(where: { $0.id == command.target }) else {
                        throw BridgeFailure("No reference with that id is on the board", code: "unknown_reference")
                    }
                    let pixels = UIImage(data: data)!.size
                    let width = command.width > 0 ? command.width : old.width
                    try place(command, png: data, size: CGSize(width: width, height: width * pixels.height / pixels.width),
                              visibleRect: visibleRect, view: view, changed: changed)
                case "image", "scene":
                    guard artifacts.count < 64 else { throw BridgeFailure("Board reference limit reached") }
                    let image: UIImage
                    let frame: CGRect
                    if command.kind == "scene", let scene = command.scene {
                        frame = CGRect(x: command.x, y: command.y, width: command.width, height: command.height)
                        try validateFrame(frame)
                        image = try scene.image(size: frame.size)
                    } else {
                        guard let file = command.imageFile, file == (file as NSString).lastPathComponent else {
                            throw BridgeFailure("Missing image")
                        }
                        let data = try Data(contentsOf: root.appendingPathComponent("assets/" + file))
                        guard data.count <= 100 * 1024 * 1024, let loaded = UIImage(data: data),
                              loaded.size.width * loaded.size.height * loaded.scale * loaded.scale <= 20_000_000
                        else { throw BridgeFailure("Invalid or oversized image") }
                        image = loaded
                        if command.width == 0 && command.height == 0 {
                            let scale = min((visibleRect.width - 80) / image.size.width,
                                            (visibleRect.height - 80) / image.size.height)
                            let size = CGSize(width: image.size.width * max(0.01, scale), height: image.size.height * max(0.01, scale))
                            frame = CGRect(x: max(0, visibleRect.midX - size.width / 2),
                                           y: max(0, visibleRect.midY - size.height / 2), width: size.width, height: size.height)
                        } else {
                            frame = CGRect(x: command.x, y: command.y, width: command.width, height: command.height)
                        }
                        try validateFrame(frame)
                    }
                    let file = "\(command.id).png"
                    guard let png = image.pngData() else { throw BridgeFailure("Could not encode image") }
                    try png.write(to: store.root.appendingPathComponent("assets/" + file), options: .atomic)
                    let artifact = CanvasArtifact(id: command.id, title: command.title, imageFile: file,
                        x: frame.minX, y: frame.minY, width: frame.width, height: frame.height, adaptive: false)
                    try store.commit(artifacts: artifacts + [artifact], drawing: store.drawing,
                                     view: view, commandID: command.id)
                    changed(false, artifact.frame)
                    try receipt(command.id, message: "Reference placed", reference: artifact)
                default: throw BridgeFailure("Unknown operation")
                }
                try FileManager.default.removeItem(at: url)
            } catch {
                // If a mutation committed, keep its inbox entry until a success receipt can be written.
                if store.state.appliedCommands[command.id] != nil { continue }
                do {
                    try receipt(command.id, message: error.localizedDescription, status: "error",
                                code: (error as? BridgeFailure)?.code ?? "io_error")
                    try FileManager.default.removeItem(at: url)
                } catch { /* Retry publication on the next poll. */ }
            }
        }
    }

    private func uploadedImage(_ command: Command) throws -> Data {
        guard let file = command.imageFile, file == (file as NSString).lastPathComponent else { throw BridgeFailure("Missing image") }
        let data = try Data(contentsOf: root.appendingPathComponent("assets/" + file))
        guard data.count <= 100 * 1024 * 1024, let image = UIImage(data: data),
              image.size.width * image.size.height * image.scale * image.scale <= 20_000_000
        else { throw BridgeFailure("Invalid or oversized image") }
        return data
    }

    /// The finished render for a write, nil while it is still rendering. A replace keeps the old width unless one is given.
    private func renderedWrite(_ command: Command) throws -> (png: Data, height: CGFloat, width: CGFloat)? {
        if let outcome = renders.removeValue(forKey: command.id) { return try outcome.get() }
        if rendering.contains(command.id) { return nil }
        guard let file = command.sourceFile, file == (file as NSString).lastPathComponent,
              let format = command.format, ["md", "html", "svg"].contains(format) else { throw BridgeFailure("Missing write source") }
        let data = try Data(contentsOf: root.appendingPathComponent("assets/" + file))
        guard data.count <= 1024 * 1024, let source = String(data: data, encoding: .utf8) else { throw BridgeFailure("Write source must be UTF-8, at most 1 MB") }
        var width = command.width
        if width <= 0, let target = command.target {
            guard let old = artifacts.first(where: { $0.id == target }) else {
                throw BridgeFailure("No reference with that id is on the board", code: "unknown_reference")
            }
            width = old.width
        }
        if width <= 0 { width = 640 }
        guard (40...3000).contains(width) else { throw BridgeFailure("Write width must be 40-3000 points") }
        rendering.insert(command.id)
        let id = command.id
        renderer(source, format, width) { [weak self] result in
            self?.rendering.remove(id)
            self?.renders[id] = result.map { (png: $0.png, height: $0.height, width: width) }
        }
        return nil
    }

    /// Places a write or replaces a reference. Replace keeps the id and origin; a write goes where asked or centered in view.
    private func place(_ command: Command, png: Data, size: CGSize, visibleRect: CGRect, view: BoardView,
                       changed: (Bool, CGRect?) -> Void) throws {
        let old = try command.target.map { id in
            guard let old = artifacts.first(where: { $0.id == id }) else {
                throw BridgeFailure("No reference with that id is on the board", code: "unknown_reference")
            }
            return old
        }
        if old == nil { guard artifacts.count < 64 else { throw BridgeFailure("Board reference limit reached") } }
        func anchor(_ id: String) throws -> CGRect {
            guard let frame = artifacts.first(where: { $0.id == id })?.frame else {
                throw BridgeFailure("No reference with that id is on the board", code: "unknown_reference")
            }
            return frame
        }
        var origin: CGPoint
        if let old { origin = old.frame.origin }
        else if let id = command.below { let a = try anchor(id); origin = CGPoint(x: a.minX, y: a.maxY + 40) }
        else if let id = command.rightOf { let a = try anchor(id); origin = CGPoint(x: a.maxX + 40, y: a.minY) }
        else if command.positioned == true { origin = CGPoint(x: command.x, y: command.y) }
        else { origin = freeSpot(size: size, in: visibleRect, ignoring: old?.id) }
        // Nudge onto the board rather than fail when only the position overflows.
        origin.x = max(0, min(3000 - size.width, origin.x))
        origin.y = max(0, min(3000 - size.height, origin.y))
        let frame = CGRect(origin: origin, size: size)
        try validateFrame(frame)
        let file = "\(command.id).png"
        try png.write(to: store.root.appendingPathComponent("assets/" + file), options: .atomic)
        let title = command.title == "Reference" ? (old?.title ?? command.title) : command.title
        let artifact = CanvasArtifact(id: old?.id ?? command.id, title: title, imageFile: file,
            x: frame.minX, y: frame.minY, width: frame.width, height: frame.height,
            adaptive: command.kind == "write")
        var next = artifacts
        if let old, let index = next.firstIndex(where: { $0.id == old.id }) { next[index] = artifact } else { next.append(artifact) }
        try store.commit(artifacts: next, drawing: store.drawing, view: view, commandID: command.id)
        if let old { try? FileManager.default.removeItem(at: store.root.appendingPathComponent("assets/" + old.imageFile)) }
        changed(false, old == nil ? frame : nil)
        try receipt(command.id, message: old == nil ? "Reference placed" : "Reference replaced", reference: artifact)
    }

    /// Centered in view unless that covers ink or another reference; then just below whatever it would cover.
    private func freeSpot(size: CGSize, in view: CGRect, ignoring id: String?) -> CGPoint {
        let taken = store.drawing.strokes.map(\.renderBounds) + artifacts.filter { $0.id != id }.map(\.frame)
        var frame = CGRect(x: view.midX - size.width / 2, y: view.midY - size.height / 2, width: size.width, height: size.height)
        for _ in 0..<50 {
            let hits = taken.filter { $0.intersects(frame.insetBy(dx: -24, dy: -24)) }
            guard let bottom = hits.map(\.maxY).max() else { break }
            frame.origin.y = bottom + 24
        }
        return frame.origin
    }

    private func validateFrame(_ frame: CGRect) throws {
        guard [frame.minX, frame.minY, frame.width, frame.height].allSatisfy({ $0.isFinite }),
              frame.width >= 10, frame.height >= 10,
              CGRect(x: 0, y: 0, width: 3000, height: 3000).contains(frame)
        else { throw BridgeFailure("Reference must fit the 3000 × 3000 board") }
    }

    private func backup(id: String, preview: UIImage) throws -> String {
        let name = "backup-\(id)"
        let folder = root.appendingPathComponent("outbox/" + name)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("assets"), withIntermediateDirectories: true)
        let refs = try artifacts.map { artifact -> BackupReference in
            let path = "assets/\(artifact.id).png"
            try Data(contentsOf: store.root.appendingPathComponent("assets/" + artifact.imageFile))
                .write(to: folder.appendingPathComponent(path), options: .atomic)
            return BackupReference(id: artifact.id, title: artifact.title, file: path,
                frame: .init(x: artifact.x, y: artifact.y, width: artifact.width, height: artifact.height),
                adaptive: artifact.adaptive)
        }
        try store.drawing.dataRepresentation().write(to: folder.appendingPathComponent("ink.drawing"), options: .atomic)
        guard let png = preview.pngData() else { throw BridgeFailure("Could not encode preview") }
        try png.write(to: folder.appendingPathComponent("preview.png"), options: .atomic)
        let manifest = BackupManifest(format: "mypad-board", version: 1,
            createdAt: ISO8601DateFormatter().string(from: Date()), revision: store.state.revision, boardSize: .init(width: 3000, height: 3000),
            view: store.state.view, inkFile: "ink.drawing", previewFile: "preview.png", references: refs)
        try encoder.encode(manifest).write(to: folder.appendingPathComponent("manifest.json"), options: .atomic)
        return name
    }

    private func restore(_ command: Command) throws {
        guard command.restoreFolder == command.id else { throw BridgeFailure("Invalid restore folder") }
        let folder = root.appendingPathComponent("restore/" + command.id)
        let manifest = try JSONDecoder().decode(BackupManifest.self, from: Data(contentsOf: folder.appendingPathComponent("manifest.json")))
        guard manifest.format == "mypad-board", manifest.version == 1,
              manifest.boardSize.width == 3000, manifest.boardSize.height == 3000,
              manifest.inkFile == "ink.drawing", manifest.previewFile == "preview.png",
              manifest.references.count <= 64,
              Set(manifest.references.map(\.id)).count == manifest.references.count,
              [manifest.view.centerX, manifest.view.centerY, manifest.view.zoomScale].allSatisfy({ $0.isFinite }),
              (0.25...4).contains(manifest.view.zoomScale)
        else { throw BridgeFailure("Unsupported or invalid backup") }
        let ink = try Data(contentsOf: folder.appendingPathComponent("ink.drawing"))
        guard ink.count <= 100 * 1024 * 1024 else { throw BridgeFailure("Ink file is too large") }
        let drawing = try PKDrawing(data: ink)
        var restored: [CanvasArtifact] = []
        for ref in manifest.references {
            guard UUID(uuidString: ref.id) != nil, ref.file == "assets/\(ref.id).png" else { throw BridgeFailure("Invalid reference path") }
            let frame = CGRect(x: ref.frame.x, y: ref.frame.y, width: ref.frame.width, height: ref.frame.height)
            try validateFrame(frame)
            let data = try Data(contentsOf: folder.appendingPathComponent(ref.file))
            guard data.count <= 100 * 1024 * 1024, let image = UIImage(data: data),
                  image.size.width * image.size.height * image.scale * image.scale <= 20_000_000
            else { throw BridgeFailure("Invalid backup image") }
            let file = "\(UUID().uuidString.lowercased()).png"
            try data.write(to: store.root.appendingPathComponent("assets/" + file), options: .atomic)
            restored.append(CanvasArtifact(id: ref.id, title: ref.title, imageFile: file,
                x: frame.minX, y: frame.minY, width: frame.width, height: frame.height, adaptive: ref.adaptive))
        }
        try store.commit(artifacts: restored, drawing: drawing, view: manifest.view, commandID: command.id)
    }

    private func export(id: String, image: UIImage, viewport: CGRect) throws -> Snapshot {
        let outbox = root.appendingPathComponent("outbox")
        let snapshot = Snapshot(id: id, imageFile: "snapshot-\(id).png", inkFile: "ink-\(id).drawing",
            createdAt: ISO8601DateFormatter().string(from: Date()), viewport: viewport,
            pixelWidth: image.cgImage?.width ?? 0, pixelHeight: image.cgImage?.height ?? 0,
            strokeCount: store.drawing.strokes.count, artifactIDs: artifacts.map(\.id), revision: store.state.revision)
        guard let png = image.pngData() else { throw BridgeFailure("Could not encode canvas") }
        try png.write(to: outbox.appendingPathComponent(snapshot.imageFile), options: .atomic)
        try store.drawing.dataRepresentation().write(to: outbox.appendingPathComponent(snapshot.inkFile), options: .atomic)
        let metadata = try encoder.encode(snapshot)
        try metadata.write(to: outbox.appendingPathComponent("snapshot-\(id).json"), options: .atomic)
        try metadata.write(to: outbox.appendingPathComponent("latest.json"), options: .atomic)
        return snapshot
    }

    private func receipt(_ id: String, message: String, status: String = "ok", code: String? = nil,
                         imageFile: String? = nil, backupFolder: String? = nil, revision: Int? = nil,
                         reference: CanvasArtifact? = nil) throws {
        let value = Receipt(id: id, status: status, message: message, code: code,
            imageFile: imageFile, backupFolder: backupFolder, revision: revision ?? store.state.revision, reference: reference)
        try encoder.encode(value).write(to: root.appendingPathComponent("outbox/ack-\(id).json"), options: .atomic)
    }
}
