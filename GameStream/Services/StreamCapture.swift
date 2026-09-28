import Foundation
import Photos
import UIKit
import WebKit

/// Saves a frame of the running stream to Photos.
///
/// `WKWebView.takeSnapshot` renders the page, which is the only capture route
/// an app has for its own video layer without screen recording entitlements.
@MainActor
enum StreamCapture {
    enum Outcome {
        case saved
        case denied
        case failed(String)

        var message: String {
            switch self {
            case .saved: return "Screenshot saved to Photos."
            case .denied: return "GameStream cannot add to Photos. Allow it in iOS Settings."
            case .failed(let reason): return "Screenshot failed: \(reason)"
            }
        }
    }

    static func capture() async -> Outcome {
        guard let view = XboxWebView.Registry.shared.streamView else {
            return .failed("no stream is running")
        }

        let configuration = WKSnapshotConfiguration()
        configuration.afterScreenUpdates = false

        let image: UIImage
        do {
            image = try await view.takeSnapshot(configuration: configuration)
        } catch {
            return .failed(error.localizedDescription)
        }

        let status = await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { continuation.resume(returning: $0) }
        }
        guard status == .authorized || status == .limited else { return .denied }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            AppLog.shared.info("capture", "screenshot saved")
            return .saved
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
