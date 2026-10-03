import UIKit
import PencilKit

final class CanvasViewController: UIViewController, PKCanvasViewDelegate {
    private let canvas = PKCanvasView()
    private let scroll = UIScrollView()
    private let workspace = UIView(frame: CGRect(x: 0, y: 0, width: 3000, height: 3000))
    private var bridge: AgentBridgePrototype?
    private var bridgeTimer: Timer?
    private var artifactViews: [String: UIImageView] = [:]
    private static let ballpointColor = UIColor(red: 0.10, green: 0.17, blue: 0.32, alpha: 1)
    private static let ballpointWidth: CGFloat = 1.2
    private lazy var toolPicker: PKToolPicker = {
        if #available(iOS 18.0, *) {
            // A ballpoint has a round tip with a much steadier line than a brush pen.
            let ballpoint = PKToolPickerInkingItem(
                type: .monoline,
                color: Self.ballpointColor,
                width: Self.ballpointWidth,
                identifier: "in.texoport.mypad.ballpoint"
            )
            let picker = PKToolPicker(toolItems: [
                ballpoint,
                PKToolPickerInkingItem(type: .pen),
                PKToolPickerInkingItem(type: .pencil),
                PKToolPickerInkingItem(type: .marker),
                PKToolPickerEraserItem(type: .vector),
                PKToolPickerLassoItem(),
                PKToolPickerRulerItem()
            ])
            // Don't let the old saved palette state replace the new writing preset.
            picker.stateAutosaveName = nil
            picker.selectedToolItem = ballpoint
            return picker
        }
        let picker = PKToolPicker()
        picker.selectedTool = PKInkingTool(.monoline, color: Self.ballpointColor, width: Self.ballpointWidth)
        return picker
    }()
    private let statusLabel = UILabel()
    private let paperSize = CGSize(width: 3000, height: 3000)
    private var store: DrawingStore?
    private var pendingSave: DispatchWorkItem?
    private var revision = 0
    private var fingerDrawing = true
    private var initialLayout = true
    private var loadError: Error?

    private lazy var undoButton = UIBarButtonItem(
        image: UIImage(systemName: "arrow.uturn.backward"),
        style: .plain, target: self, action: #selector(undo)
    )
    private lazy var redoButton = UIBarButtonItem(
        image: UIImage(systemName: "arrow.uturn.forward"),
        style: .plain, target: self, action: #selector(redo)
    )
    private lazy var fingerButton = UIBarButtonItem(
        title: "Finger: On", style: .plain, target: self, action: #selector(toggleFingerDrawing)
    )

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationController?.navigationBar.tintColor = UIColor(red: 0.19, green: 0.35, blue: 0.31, alpha: 1)
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .systemBackground
        navigationController?.navigationBar.standardAppearance = appearance
        navigationController?.navigationBar.scrollEdgeAppearance = appearance

        let titleLabel = UILabel()
        titleLabel.text = "MyPad"
        titleLabel.font = .systemFont(ofSize: 19, weight: .semibold)
        statusLabel.text = "Draw anywhere · two fingers to move"
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabel
        let titleStack = UIStackView(arrangedSubviews: [titleLabel, statusLabel])
        titleStack.axis = .vertical
        titleStack.spacing = 2
        navigationItem.titleView = titleStack
        undoButton.accessibilityLabel = "Undo"
        redoButton.accessibilityLabel = "Redo"
        fingerButton.accessibilityHint = "When off, draw with Apple Pencil and pan with one finger."
        let homeButton = UIBarButtonItem(
            image: UIImage(systemName: "arrow.up.left.and.arrow.down.right"),
            style: .plain, target: self, action: #selector(resetView)
        )
        homeButton.accessibilityLabel = "Reset zoom and position"
        navigationItem.leftBarButtonItems = [undoButton, redoButton]
        let sendButton = UIBarButtonItem(title: "Send to Agent", style: .plain, target: self, action: #selector(sendToAgent))
        sendButton.accessibilityHint = "Export the visible diagram and handwriting for the laptop agent."
        navigationItem.rightBarButtonItems = [sendButton, homeButton, fingerButton]

        let paper = UIColor(red: 0.99, green: 0.98, blue: 0.95, alpha: 1)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.backgroundColor = paper
        scroll.contentSize = paperSize
        scroll.minimumZoomScale = 0.25
        scroll.maximumZoomScale = 4
        scroll.alwaysBounceHorizontal = true
        scroll.alwaysBounceVertical = true
        scroll.delaysContentTouches = false
        scroll.delegate = self
        scroll.panGestureRecognizer.minimumNumberOfTouches = 2
        scroll.panGestureRecognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        workspace.backgroundColor = paper
        workspace.clipsToBounds = true
        scroll.addSubview(workspace)
        canvas.frame = workspace.bounds
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.contentSize = paperSize
        canvas.isScrollEnabled = false
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.monoline, color: Self.ballpointColor, width: Self.ballpointWidth)
        workspace.addSubview(canvas)
        view.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        do {
            let store = try DrawingStore()
            canvas.drawing = try store.load()
            self.store = store
            if !canvas.drawing.strokes.isEmpty { statusLabel.text = "Saved on this iPad" }
        } catch {
            loadError = error
            statusLabel.text = "Could not open saved canvas"
        }
        canvas.delegate = self
        do {
            let bridge = try AgentBridgePrototype()
            self.bridge = bridge
            for artifact in bridge.artifacts {
                if let image = bridge.image(for: artifact) { addArtifact(artifact, image: image, focus: false) }
            }
            navigationItem.prompt = "Agent bridge ready · USB file mailbox"
        } catch {
            navigationItem.prompt = "Agent bridge unavailable: \(error.localizedDescription)"
            sendButton.isEnabled = false
        }
        toolPicker.showsDrawingPolicyControls = false
        toolPicker.addObserver(canvas)
        updateUndoButtons()
        NotificationCenter.default.addObserver(
            self, selector: #selector(flushSave),
            name: UIApplication.willResignActiveNotification, object: nil
        )
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        canvas.becomeFirstResponder()
        toolPicker.setVisible(true, forFirstResponder: canvas)
        bridgeTimer?.invalidate()
        bridgeTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.bridge?.poll(add: { artifact, image in
                self.addArtifact(artifact, image: image, focus: true)
            }, capture: { try self.captureForAgent() })
        }
        if let error = loadError {
            loadError = nil
            let alert = UIAlertController(
                title: "Couldn't open your canvas",
                message: "Your saved file has been preserved. New strokes won't be saved until this is resolved.\n\n\(error.localizedDescription)",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        bridgeTimer?.invalidate()
        bridgeTimer = nil
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        scrollView === scroll ? workspace : nil
    }

    private func addArtifact(_ artifact: CanvasArtifact, image: UIImage, focus: Bool) {
        guard artifactViews[artifact.id] == nil else { return }
        let imageView = UIImageView(image: image)
        imageView.frame = artifact.frame
        imageView.contentMode = .scaleToFill
        imageView.isUserInteractionEnabled = false
        workspace.insertSubview(imageView, belowSubview: canvas)
        artifactViews[artifact.id] = imageView
        if focus {
            scroll.zoom(to: artifact.frame.insetBy(dx: -40, dy: -80), animated: true)
            navigationItem.prompt = "Agent placed: \(artifact.title) · annotate, then Send to Agent"
        }
    }

    @objc private func sendToAgent() {
        do {
            let snapshot = try captureForAgent()
            navigationItem.prompt = "Ready for agent · \(snapshot.strokeCount) strokes · visible canvas exported"
        } catch {
            navigationItem.prompt = "Export failed: \(error.localizedDescription)"
        }
    }

    private func captureForAgent() throws -> AgentBridgePrototype.Snapshot {
        guard let bridge else { throw BridgeFailure("Bridge unavailable") }
        let zoom = scroll.zoomScale
        let rect = CGRect(x: scroll.contentOffset.x / zoom, y: scroll.contentOffset.y / zoom,
                          width: scroll.bounds.width / zoom, height: scroll.bounds.height / zoom)
            .intersection(CGRect(origin: .zero, size: paperSize))
        guard !rect.isNull, rect.width > 0, rect.height > 0 else { throw BridgeFailure("No canvas visible") }
        let format = UIGraphicsImageRendererFormat()
        format.scale = min(2, 2400 / max(rect.width, rect.height))
        var image: UIImage!
        // Offscreen PencilKit rendering uses the current traits, not the window's.
        // Match the light paper shown on the device, including older black strokes.
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = UIGraphicsImageRenderer(size: rect.size, format: format).image { context in
                workspace.backgroundColor?.setFill()
                context.fill(CGRect(origin: .zero, size: rect.size))
                for artifact in bridge.artifacts {
                    if let image = artifactViews[artifact.id]?.image {
                        image.draw(in: artifact.frame.offsetBy(dx: -rect.minX, dy: -rect.minY))
                    }
                }
                canvas.drawing.image(from: rect, scale: format.scale).draw(in: CGRect(origin: .zero, size: rect.size))
            }
        }
        return try bridge.export(image: image, drawing: canvas.drawing, viewport: rect)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if initialLayout && scroll.bounds.width > 0 {
            initialLayout = false
            resetView()
        }
    }

    @objc private func resetView() {
        if let artifact = bridge?.artifacts.last {
            scroll.zoom(to: artifact.frame.insetBy(dx: -40, dy: -80), animated: false)
            return
        }
        scroll.setZoomScale(1, animated: false)
        let drawingBounds = canvas.drawing.bounds
        let center = drawingBounds.isNull
            ? CGPoint(x: paperSize.width / 2, y: paperSize.height / 2)
            : CGPoint(x: drawingBounds.midX, y: drawingBounds.midY)
        let offset = CGPoint(
            x: max(0, min(paperSize.width - scroll.bounds.width, center.x - scroll.bounds.width / 2)),
            y: max(0, min(paperSize.height - scroll.bounds.height, center.y - scroll.bounds.height / 2))
        )
        scroll.setContentOffset(offset, animated: false)
    }

    @objc private func toggleFingerDrawing() {
        fingerDrawing.toggle()
        canvas.drawingPolicy = fingerDrawing ? .anyInput : .pencilOnly
        scroll.panGestureRecognizer.minimumNumberOfTouches = fingerDrawing ? 2 : 1
        fingerButton.title = fingerDrawing ? "Finger: On" : "Pencil Only"
    }

    @objc private func undo() {
        canvas.undoManager?.undo()
        updateUndoButtons()
    }

    @objc private func redo() {
        canvas.undoManager?.redo()
        updateUndoButtons()
    }

    private func updateUndoButtons() {
        undoButton.isEnabled = canvas.undoManager?.canUndo ?? false
        redoButton.isEnabled = canvas.undoManager?.canRedo ?? false
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard store != nil else { return }
        revision += 1
        pendingSave?.cancel()
        statusLabel.text = "Saving…"
        let work = DispatchWorkItem { [weak self] in self?.save() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        DispatchQueue.main.async { [weak self] in self?.updateUndoButtons() }
    }

    func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
        updateUndoButtons()
    }

    private func save() {
        let savedRevision = revision
        store?.save(canvas.drawing.dataRepresentation()) { [weak self] error in
            guard let self, savedRevision == self.revision else { return }
            self.statusLabel.text = error == nil ? "Saved on this iPad" : "Save failed — try again"
            self.statusLabel.accessibilityValue = error?.localizedDescription
        }
    }

    @objc private func flushSave() {
        pendingSave?.cancel()
        guard let store else { return }
        do {
            try store.flush(canvas.drawing.dataRepresentation())
            statusLabel.text = "Saved on this iPad"
        } catch {
            statusLabel.text = "Save failed — try again"
        }
    }

    deinit {
        bridgeTimer?.invalidate()
        pendingSave?.cancel()
        NotificationCenter.default.removeObserver(self)
    }
}
