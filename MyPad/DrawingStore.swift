import Foundation
import PencilKit
import UIKit

struct BoardView: Codable {
    var centerX: CGFloat = 1500
    var centerY: CGFloat = 1500
    var zoomScale: CGFloat = 1
}

struct BoardState: Codable {
    var revision: Int = 0
    var inkFile: String = ""
    var artifacts: [CanvasArtifact] = []
    var view = BoardView()
    // Mutation IDs survive the gap between committing a board and writing its receipt.
    var appliedCommands: [String: Int] = [:]
}

/// Immutable ink/assets and one atomic manifest commit keep board components together.
/// All mutable state is owned by the main thread; disk writes run in order.
final class DrawingStore {
    let root: URL
    private let queue = DispatchQueue(label: "in.texoport.mypad.saving", qos: .utility)
    private let encoder: JSONEncoder = {
        let value = JSONEncoder(); value.outputFormatting = [.prettyPrinted, .sortedKeys]; return value
    }()
    private(set) var state = BoardState()
    private(set) var drawing = PKDrawing()

    init(supportDirectory: URL? = nil, documentsDirectory: URL? = nil) throws {
        let support = try supportDirectory ?? FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
        root = support.appendingPathComponent("Board", isDirectory: true)
        for name in ["ink", "assets"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        let manifest = root.appendingPathComponent("current.json")
        if FileManager.default.fileExists(atPath: manifest.path) {
            state = try JSONDecoder().decode(BoardState.self, from: Data(contentsOf: manifest))
            drawing = try PKDrawing(data: Data(contentsOf: root.appendingPathComponent(state.inkFile)))
            for artifact in state.artifacts {
                guard UIImage(contentsOfFile: root.appendingPathComponent("assets/" + artifact.imageFile).path) != nil
                else { throw BridgeFailure("Saved reference is missing: \(artifact.title)") }
            }
        } else {
            let legacyInk = support.appendingPathComponent("Canvas.drawing")
            if FileManager.default.fileExists(atPath: legacyInk.path) {
                drawing = try PKDrawing(data: Data(contentsOf: legacyInk))
            }
            let legacyRoot = (documentsDirectory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0])
                .appendingPathComponent("AgentBridgePrototype")
            let legacyBoard = legacyRoot.appendingPathComponent("board.json")
            if FileManager.default.fileExists(atPath: legacyBoard.path) {
                state.artifacts = try JSONDecoder().decode([CanvasArtifact].self, from: Data(contentsOf: legacyBoard))
                for artifact in state.artifacts {
                    let source = legacyRoot.appendingPathComponent("assets/" + artifact.imageFile)
                    let data = try Data(contentsOf: source)
                    guard UIImage(data: data) != nil else { throw BridgeFailure("Could not migrate reference") }
                    try data.write(to: root.appendingPathComponent("assets/" + artifact.imageFile), options: .atomic)
                }
            }
            try flush()
        }
    }

    func image(for artifact: CanvasArtifact) -> UIImage? {
        UIImage(contentsOfFile: root.appendingPathComponent("assets/" + artifact.imageFile).path)
    }

    func updateDrawing(_ drawing: PKDrawing) {
        self.drawing = drawing
        state.revision += 1
    }

    func updateView(_ view: BoardView) { state.view = view }

    func commit(artifacts: [CanvasArtifact], drawing: PKDrawing, view: BoardView,
                commandID: String) throws {
        var next = state
        next.revision += 1
        next.artifacts = artifacts
        next.view = view
        next.appliedCommands[commandID] = next.revision
        let data = drawing.dataRepresentation()
        let committed = try queue.sync { try write(next, ink: data) }
        state = committed
        self.drawing = drawing
    }

    func save(completion: @escaping (Error?) -> Void) {
        let snapshot = state, ink = drawing.dataRepresentation()
        queue.async {
            do { _ = try self.write(snapshot, ink: ink); DispatchQueue.main.async { completion(nil) } }
            catch { DispatchQueue.main.async { completion(error) } }
        }
    }

    func flush() throws {
        let snapshot = state, ink = drawing.dataRepresentation()
        state = try queue.sync { try write(snapshot, ink: ink) }
    }

    private func write(_ state: BoardState, ink: Data) throws -> BoardState {
        let manifestURL = root.appendingPathComponent("current.json")
        let previous = (try? Data(contentsOf: manifestURL)).flatMap { try? JSONDecoder().decode(BoardState.self, from: $0) }
        var next = state
        next.inkFile = "ink/\(UUID().uuidString.lowercased()).drawing"
        try ink.write(to: root.appendingPathComponent(next.inkFile), options: .atomic)
        try encoder.encode(next).write(to: manifestURL, options: .atomic)
        // Retain current and preceding ink generations; exports/backups have their own copies.
        let retained = Set([next.inkFile, previous?.inkFile ?? ""])
        if let files = try? FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("ink"), includingPropertiesForKeys: nil) {
            for file in files where !retained.contains("ink/" + file.lastPathComponent) {
                try? FileManager.default.removeItem(at: file)
            }
        }
        return next
    }
}
