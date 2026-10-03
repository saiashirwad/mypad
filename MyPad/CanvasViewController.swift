import UIKit
import PencilKit

final class CanvasViewController: UIViewController, PKCanvasViewDelegate, UIGestureRecognizerDelegate {
    private let canvas = PKCanvasView()
    private let scroll = UIScrollView()
    private let workspace = UIView(frame: CGRect(x: 0, y: 0, width: 3000, height: 3000))
    private var bridge: AgentBridge?
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
    private let paperSize = CGSize(width: 3000, height: 3000)
    private var store: DrawingStore?
    private var pendingSave: DispatchWorkItem?
    private var toolsVisible = false
    private var applyingBoard = false
    private var drawingActive = false
    private var initialLayout = true
    private var loadError: Error?

    private lazy var undoButton = makeButton("arrow.uturn.backward", label: "Undo", action: #selector(undo))
    private lazy var redoButton = makeButton("arrow.uturn.forward", label: "Redo", action: #selector(redo))
    private lazy var toolsButton = makeButton("pencil.tip", label: "Drawing tools", action: #selector(toggleTools))
    override var prefersStatusBarHidden: Bool { true }

    private func makeButton(_ symbol: String, label: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)), for: .normal)
        button.tintColor = UIColor(red: 0.22, green: 0.36, blue: 0.28, alpha: 1)
        button.accessibilityLabel = label
        button.addTarget(self, action: action, for: .touchUpInside)
        NSLayoutConstraint.activate([button.widthAnchor.constraint(equalToConstant: 44), button.heightAnchor.constraint(equalToConstant: 44)])
        return button
    }

    private func floatingControls(_ buttons: [UIButton]) -> UIView {
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialLight))
        blur.translatesAutoresizingMaskIntoConstraints = false
        blur.layer.cornerRadius = 18
        blur.clipsToBounds = true
        blur.layer.borderWidth = 0.5
        blur.layer.borderColor = UIColor.black.withAlphaComponent(0.08).cgColor
        let stack = UIStackView(arrangedSubviews: buttons)
        stack.translatesAutoresizingMaskIntoConstraints = false
        blur.contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: blur.contentView.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: blur.contentView.bottomAnchor, constant: -4),
            stack.leadingAnchor.constraint(equalTo: blur.contentView.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: blur.contentView.trailingAnchor, constant: -4)
        ])
        return blur
    }

    override func viewDidLoad() {
        super.viewDidLoad()
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
        scroll.panGestureRecognizer.minimumNumberOfTouches = 1
        scroll.panGestureRecognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        workspace.backgroundColor = paper
        workspace.clipsToBounds = true
        scroll.addSubview(workspace)
        canvas.frame = workspace.bounds
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.contentSize = paperSize
        canvas.isScrollEnabled = false
        canvas.drawingPolicy = .pencilOnly
        canvas.tool = PKInkingTool(.monoline, color: Self.ballpointColor, width: Self.ballpointWidth)
        workspace.addSubview(canvas)
        view.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        let undoControls = floatingControls([undoButton, redoButton])
        let toolControls = floatingControls([toolsButton])
        view.addSubview(undoControls)
        view.addSubview(toolControls)
        NSLayoutConstraint.activate([
            undoControls.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 18),
            undoControls.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            toolControls.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -18),
            toolControls.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])
        do {
            let store = try DrawingStore()
            canvas.drawing = store.drawing
            self.store = store
            let bridge = try AgentBridge(store: store)
            self.bridge = bridge
            refreshBoard(focus: false)
        } catch { loadError = error }
        canvas.delegate = self
        let dismissTools = UITapGestureRecognizer(target: self, action: #selector(dismissTools))
        dismissTools.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        dismissTools.cancelsTouchesInView = false
        dismissTools.delegate = self
        view.addGestureRecognizer(dismissTools)
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
        toolPicker.setVisible(toolsVisible, forFirstResponder: canvas)
        bridgeTimer?.invalidate()
        bridgeTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard !self.drawingActive else { return }
            self.bridge?.poll(view: self.boardView, visibleRect: self.visibleRect,
                changed: { self.refreshBoard(focus: $0) }, render: { try self.renderBoard(rect: $0) })
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
        }
    }

    private var visibleRect: CGRect {
        let zoom = scroll.zoomScale
        return CGRect(x: scroll.contentOffset.x / zoom, y: scroll.contentOffset.y / zoom,
            width: scroll.bounds.width / zoom, height: scroll.bounds.height / zoom)
            .intersection(CGRect(origin: .zero, size: paperSize))
    }

    private var boardView: BoardView {
        BoardView(centerX: (scroll.contentOffset.x + scroll.bounds.width / 2) / scroll.zoomScale,
                  centerY: (scroll.contentOffset.y + scroll.bounds.height / 2) / scroll.zoomScale,
                  zoomScale: scroll.zoomScale)
    }

    private func refreshBoard(focus: Bool) {
        guard let store else { return }
        applyingBoard = true
        if !focus {
            canvas.drawing = store.drawing
            canvas.undoManager?.removeAllActions()
        }
        for view in artifactViews.values { view.removeFromSuperview() }
        artifactViews.removeAll()
        for artifact in store.state.artifacts {
            if let image = store.image(for: artifact) { addArtifact(artifact, image: image, focus: false) }
        }
        if focus, let artifact = store.state.artifacts.last {
            scroll.zoom(to: artifact.frame.insetBy(dx: -40, dy: -40), animated: false)
        } else { applyView(store.state.view) }
        applyingBoard = false
        updateUndoButtons()
    }

    private func applyView(_ saved: BoardView) {
        scroll.setZoomScale(saved.zoomScale, animated: false)
        let scaled = CGSize(width: paperSize.width * scroll.zoomScale, height: paperSize.height * scroll.zoomScale)
        scroll.setContentOffset(CGPoint(
            x: max(0, min(scaled.width - scroll.bounds.width, saved.centerX * scroll.zoomScale - scroll.bounds.width / 2)),
            y: max(0, min(scaled.height - scroll.bounds.height, saved.centerY * scroll.zoomScale - scroll.bounds.height / 2))), animated: false)
    }

    private func renderBoard(rect: CGRect) throws -> UIImage {
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
                for artifact in store?.state.artifacts ?? [] {
                    if let image = artifactViews[artifact.id]?.image {
                        image.draw(in: artifact.frame.offsetBy(dx: -rect.minX, dy: -rect.minY))
                    }
                }
                canvas.drawing.image(from: rect, scale: format.scale).draw(in: CGRect(origin: .zero, size: rect.size))
            }
        }
        return image
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if initialLayout && scroll.bounds.width > 0 {
            initialLayout = false
            if let saved = store?.state.view { applyView(saved) } else { resetView() }
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

    @objc private func toggleTools() {
        toolsVisible.toggle()
        canvas.becomeFirstResponder()
        toolPicker.setVisible(toolsVisible, forFirstResponder: canvas)
        toolsButton.accessibilityValue = toolsVisible ? "Expanded" : "Collapsed"
    }

    @objc private func dismissTools() {
        guard toolsVisible else { return }
        toggleTools()
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard toolsVisible else { return false }
        var touched = touch.view
        while let current = touched {
            if current is UIControl { return false }
            touched = current.superview
        }
        return true
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
        guard let store, !applyingBoard else { return }
        store.updateDrawing(canvas.drawing)
        scheduleSave()
        DispatchQueue.main.async { [weak self] in self?.updateUndoButtons() }
    }

    func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) { drawingActive = true }

    func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
        drawingActive = false
        updateUndoButtons()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { scheduleSave() }
    }
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { scheduleSave() }
    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) { scheduleSave() }

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func save() {
        store?.updateView(boardView)
        store?.save { [weak self] error in
            if let error { self?.showError(error) }
        }
    }

    private func showError(_ error: Error) {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: "Couldn't save your board", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    @objc private func flushSave() {
        pendingSave?.cancel()
        store?.updateView(boardView)
        do { try store?.flush() } catch { showError(error) }
    }

    deinit {
        bridgeTimer?.invalidate()
        pendingSave?.cancel()
        NotificationCenter.default.removeObserver(self)
    }
}
