import UIKit
import PencilKit

// PROTOTYPE: a local file mailbox transported by devicectl, with no network server.
struct CanvasArtifact: Codable {
    let id: String
    let title: String
    let imageFile: String
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
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
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

final class AgentBridgePrototype {
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
    }
    struct Receipt: Codable {
        let id: String
        let status: String
        let message: String
        let imageFile: String?
    }

    let root: URL
    private(set) var artifacts: [CanvasArtifact] = []
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() throws {
        root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AgentBridgePrototype", isDirectory: true)
        for name in ["inbox", "assets", "outbox"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifest = root.appendingPathComponent("board.json")
        if FileManager.default.fileExists(atPath: manifest.path) {
            artifacts = try decoder.decode([CanvasArtifact].self, from: Data(contentsOf: manifest))
        }
    }

    func image(for artifact: CanvasArtifact) -> UIImage? {
        UIImage(contentsOfFile: root.appendingPathComponent("assets").appendingPathComponent(artifact.imageFile).path)
    }

    func poll(add: (CanvasArtifact, UIImage) -> Void, capture: () throws -> Snapshot) {
        let inbox = root.appendingPathComponent("inbox")
        guard let urls = try? FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil) else { return }
        for url in urls.filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            // Files are decoded only after the complete command is present.
            guard let data = try? Data(contentsOf: url), let command = try? decoder.decode(Command.self, from: data) else { continue }
            guard UUID(uuidString: command.id) != nil, url.lastPathComponent == "\(command.id).json" else { continue }
            do {
                if command.kind == "capture" {
                    let snapshot = try capture()
                    try receipt(command.id, message: "Captured visible canvas", imageFile: snapshot.imageFile)
                } else {
                    guard command.kind == "image" || command.kind == "scene" else { throw BridgeFailure("Unknown command kind") }
                    guard command.width >= 10, command.height >= 10,
                          CGRect(x: 0, y: 0, width: 3000, height: 3000).contains(
                            CGRect(x: command.x, y: command.y, width: command.width, height: command.height))
                    else { throw BridgeFailure("Artifact must fit the 3000 × 3000 canvas") }
                    if !artifacts.contains(where: { $0.id == command.id }) {
                        let image: UIImage
                        if command.kind == "scene", let scene = command.scene {
                            image = try scene.image(size: CGSize(width: command.width, height: command.height))
                        } else if let file = command.imageFile, file == (file as NSString).lastPathComponent,
                                  let loaded = UIImage(contentsOfFile: root.appendingPathComponent("assets").appendingPathComponent(file).path) {
                            image = loaded
                        } else { throw BridgeFailure("Missing image or scene") }
                        let file = "\(command.id).png"
                        guard let png = image.pngData() else { throw BridgeFailure("Could not encode image") }
                        try png.write(to: root.appendingPathComponent("assets").appendingPathComponent(file), options: .atomic)
                        let artifact = CanvasArtifact(id: command.id, title: command.title, imageFile: file,
                                                      x: command.x, y: command.y, width: command.width, height: command.height)
                        let updated = artifacts + [artifact]
                        try encoder.encode(updated).write(to: root.appendingPathComponent("board.json"), options: .atomic)
                        artifacts = updated
                        add(artifact, image)
                    }
                    try receipt(command.id, message: "Placed \(command.title)")
                }
                try FileManager.default.removeItem(at: url)
            } catch {
                try? receipt(command.id, message: error.localizedDescription, status: "error")
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    func export(image: UIImage, drawing: PKDrawing, viewport: CGRect) throws -> Snapshot {
        let id = UUID().uuidString.lowercased()
        let outbox = root.appendingPathComponent("outbox")
        let snapshot = Snapshot(id: id, imageFile: "snapshot-\(id).png", inkFile: "ink-\(id).drawing",
                                createdAt: ISO8601DateFormatter().string(from: Date()), viewport: viewport,
                                pixelWidth: image.cgImage?.width ?? Int(image.size.width * image.scale),
                                pixelHeight: image.cgImage?.height ?? Int(image.size.height * image.scale),
                                strokeCount: drawing.strokes.count, artifactIDs: artifacts.map(\.id))
        guard let png = image.pngData() else { throw BridgeFailure("Could not encode canvas") }
        try png.write(to: outbox.appendingPathComponent(snapshot.imageFile), options: .atomic)
        try drawing.dataRepresentation().write(to: outbox.appendingPathComponent(snapshot.inkFile), options: .atomic)
        let metadata = try encoder.encode(snapshot)
        try metadata.write(to: outbox.appendingPathComponent("snapshot-\(id).json"), options: .atomic)
        // Publish the pointer last, so readers see only complete exports.
        try metadata.write(to: outbox.appendingPathComponent("latest.json"), options: .atomic)
        return snapshot
    }

    private func receipt(_ id: String, message: String, status: String = "ok", imageFile: String? = nil) throws {
        let response = Receipt(id: id, status: status, message: message, imageFile: imageFile)
        try encoder.encode(response).write(to: root.appendingPathComponent("outbox/ack-\(id).json"), options: .atomic)
    }
}
