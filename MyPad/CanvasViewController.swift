import UIKit
import PencilKit

final class CanvasViewController: UIViewController, PKCanvasViewDelegate {
    private let canvas = PKCanvasView()
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
        navigationItem.rightBarButtonItems = [homeButton, fingerButton]

        canvas.translatesAutoresizingMaskIntoConstraints = false
        canvas.backgroundColor = UIColor(red: 0.99, green: 0.98, blue: 0.95, alpha: 1)
        canvas.isOpaque = true
        canvas.contentSize = paperSize
        canvas.minimumZoomScale = 0.25
        canvas.maximumZoomScale = 4
        canvas.alwaysBounceHorizontal = true
        canvas.alwaysBounceVertical = true
        canvas.drawingPolicy = .anyInput
        canvas.panGestureRecognizer.minimumNumberOfTouches = 2
        canvas.tool = PKInkingTool(.monoline, color: Self.ballpointColor, width: Self.ballpointWidth)
        view.addSubview(canvas)
        NSLayoutConstraint.activate([
            canvas.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            canvas.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            canvas.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: view.trailingAnchor)
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

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if initialLayout && canvas.bounds.width > 0 {
            initialLayout = false
            resetView()
        }
    }

    @objc private func resetView() {
        canvas.setZoomScale(1, animated: false)
        let drawingBounds = canvas.drawing.bounds
        let center = drawingBounds.isNull
            ? CGPoint(x: paperSize.width / 2, y: paperSize.height / 2)
            : CGPoint(x: drawingBounds.midX, y: drawingBounds.midY)
        let offset = CGPoint(
            x: max(0, min(paperSize.width - canvas.bounds.width, center.x - canvas.bounds.width / 2)),
            y: max(0, min(paperSize.height - canvas.bounds.height, center.y - canvas.bounds.height / 2))
        )
        canvas.setContentOffset(offset, animated: false)
    }

    @objc private func toggleFingerDrawing() {
        fingerDrawing.toggle()
        canvas.drawingPolicy = fingerDrawing ? .anyInput : .pencilOnly
        canvas.panGestureRecognizer.minimumNumberOfTouches = fingerDrawing ? 2 : 1
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
        pendingSave?.cancel()
        NotificationCenter.default.removeObserver(self)
    }
}
