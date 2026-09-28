import Foundation
import Photos
import UIKit
import WebKit

/// Saves a frame of the running stream to Photos.
///
/// The frame comes from the video element itself, at whatever resolution is
/// being streamed — 1920×1080 for a normal session — rather than from a
/// snapshot of the web view. A view snapshot is the phone's screen: the frame
/// scaled down to the size of the display, with the touch controls and the
/// site's own HUD drawn over it. This is the picture, and only the picture.
///
/// It cannot be better than what arrived. A cloud stream is compressed before
/// it is sent, and no capture can recover detail the encoder discarded. What
/// it can do is add nothing further: full resolution, no rescaling, no
/// overlay, and a lossless PNG rather than a second round of JPEG.
@MainActor
enum StreamCapture {
    enum Outcome {
        case saved(width: Int, height: Int)
        case denied
        case failed(String)

        var message: String {
            switch self {
            case .saved(let width, let height):
                return "Saved to Photos at \(width)×\(height)."
            case .denied:
                return "GameStream cannot add to Photos. Allow it in iOS Settings."
            case .failed(let reason):
                return "Screenshot failed: \(reason)"
            }
        }
    }

    static func capture() async -> Outcome {
        guard XboxWebView.Registry.shared.streamView != nil else {
            return .failed("no stream is running")
        }

        guard let payload = await XboxWebView.Registry.shared
            .evaluateAsync("return await window.__gsCapture();") as? [String: Any] else {
            return .failed("the page did not return a frame")
        }
        if let error = payload["error"] as? String { return .failed(error) }

        guard let dataURL = payload["data"] as? String,
              let comma = dataURL.firstIndex(of: ","),
              let data = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...])),
              let image = UIImage(data: data) else {
            return .failed("the frame could not be read")
        }

        let status = await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { continuation.resume(returning: $0) }
        }
        guard status == .authorized || status == .limited else { return .denied }

        let width = payload["width"] as? Int ?? Int(image.size.width)
        let height = payload["height"] as? Int ?? Int(image.size.height)

        do {
            try await PHPhotoLibrary.shared().performChanges {
                // The PNG data is saved as it came out of the canvas. Going
                // through UIImage again would re-encode it for nothing.
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            }
            AppLog.shared.info("capture", "saved a \(width)×\(height) frame")
            return .saved(width: width, height: height)
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
