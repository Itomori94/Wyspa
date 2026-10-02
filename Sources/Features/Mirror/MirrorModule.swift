import AVFoundation
import AppKit
import SwiftUI
import WyspaCore

/// Lusterko: podgląd z kamery w wyspie. Kamera działa tylko, gdy zakładka jest widoczna.
@MainActor
@Observable
public final class MirrorModule: IslandModule {
    public static let descriptor = ModuleDescriptor(
        id: "mirror",
        name: "Lusterko",
        summary: "Podgląd z kamery przed rozmową wideo. Kamera włącza się tylko, gdy zakładka jest widoczna; obraz nie jest zapisywany.",
        symbol: "camera.fill",
        permissions: [.camera],
        widgetMinWidth: 110
    )

    public required init(context: ModuleContext) {}
    public func activate() async throws {}
    public func deactivate() {}
    public var liveActivity: LiveActivity? { nil }

    public func makeWidgetView() -> AnyView? {
        AnyView(
            CameraPreview()
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
    }

    public func makeExpandedView() -> AnyView? {
        AnyView(
            CameraPreview()
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
    }
}

/// Podgląd kamery: sesja startuje przy pojawieniu się widoku i zatrzymuje przy zniknięciu.
private struct CameraPreview: NSViewRepresentable {
    func makeNSView(context: Context) -> CameraPreviewView { CameraPreviewView() }
    func updateNSView(_ nsView: CameraPreviewView, context: Context) {}
    static func dismantleNSView(_ nsView: CameraPreviewView, coordinator: ()) { nsView.stop() }
}

final class CameraPreviewView: NSView {
    private let session = AVCaptureSession()
    private let previewLayer: AVCaptureVideoPreviewLayer
    private let queue = DispatchQueue(label: "pl.net.kurant.wyspa.camera")
    private let log = Log.logger("mirror")

    override init(frame: NSRect) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.08, alpha: 1).cgColor
        previewLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(previewLayer)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.frame = bounds
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window == nil ? stop() : start()
    }

    func stop() {
        let box = SessionBox(session: session)
        queue.async { if box.session.isRunning { box.session.stopRunning() } }
    }

    private func start() {
        let box = SessionBox(session: session)
        // startRunning blokuje, więc poza głównym wątkiem.
        queue.async { if !box.session.isRunning { box.session.startRunning() } }
    }

    private func configure() {
        guard let device = AVCaptureDevice.default(for: .video) else {
            log.error("Brak kamery")
            return
        }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            session.beginConfiguration()
            session.sessionPreset = .high
            if session.canAddInput(input) { session.addInput(input) }
            session.commitConfiguration()
            if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
        } catch {
            log.error("Nie udało się otworzyć kamery: \(error.localizedDescription)")
        }
    }
}

/// Apple zaleca startRunning/stopRunning na kolejce w tle; sesja jest używana tylko przez jedną kolejkę szeregową.
private struct SessionBox: @unchecked Sendable {
    let session: AVCaptureSession
}
