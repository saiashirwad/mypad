import Foundation
import PencilKit

/// One local drawing, written atomically. A serial queue keeps saves in order.
final class DrawingStore {
    private let queue = DispatchQueue(label: "in.texoport.mypad.saving", qos: .utility)
    private let url: URL

    init() throws {
        let folder = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        url = folder.appendingPathComponent("Canvas.drawing")
    }

    func load() throws -> PKDrawing {
        guard FileManager.default.fileExists(atPath: url.path) else { return PKDrawing() }
        return try PKDrawing(data: Data(contentsOf: url))
    }

    func save(_ data: Data, completion: @escaping (Error?) -> Void) {
        queue.async {
            let error: Error?
            do {
                try data.write(to: self.url, options: .atomic)
                error = nil
            } catch let failure {
                error = failure
            }
            DispatchQueue.main.async { completion(error) }
        }
    }

    /// Finish pending writes before the app moves into the background.
    func flush(_ data: Data) throws {
        try queue.sync { try data.write(to: url, options: .atomic) }
    }
}
