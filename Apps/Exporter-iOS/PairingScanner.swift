#if os(iOS)
import AVFoundation
import SwiftUI
import VisionKit

struct PairingScanner: UIViewControllerRepresentable {
    var onPayload: (String) -> Void
    var onFailure: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(onPayload: onPayload, onFailure: onFailure, dismiss: dismiss)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .fast,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        context.coordinator.scanner = scanner
        Task { @MainActor in
            do {
                try scanner.startScanning()
            } catch {
                onFailure(error.localizedDescription)
                dismiss()
            }
        }
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onPayload: (String) -> Void
        let onFailure: (String) -> Void
        let dismiss: DismissAction
        weak var scanner: DataScannerViewController?
        private var finished = false

        init(onPayload: @escaping (String) -> Void, onFailure: @escaping (String) -> Void, dismiss: DismissAction) {
            self.onPayload = onPayload
            self.onFailure = onFailure
            self.dismiss = dismiss
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard !finished else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item, let text = barcode.payloadStringValue, !text.isEmpty {
                    finished = true
                    dataScanner.stopScanning()
                    onPayload(text)
                    dismiss()
                    return
                }
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            guard !finished else { return }
            finished = true
            dataScanner.stopScanning()
            onFailure(String(describing: error))
            dismiss()
        }
    }
}

@MainActor
enum PairingCamera {
    static var canPresentScanner: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    static var unavailableReason: String {
        if !DataScannerViewController.isSupported {
            return "This device cannot scan a QR. Paste the pairing payload from the Mac."
        }
        return "The camera is not available. Allow camera access, or paste the pairing payload."
    }

    static func requestAccess() async -> Bool {
        let current = AVCaptureDevice.authorizationStatus(for: .video)
        switch current {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }
}
#endif
