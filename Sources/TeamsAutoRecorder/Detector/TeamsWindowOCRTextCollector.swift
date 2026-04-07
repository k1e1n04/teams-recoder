import Foundation
import CoreGraphics
import Vision

public final class TeamsWindowOCRTextCollector {
    private let minInterval: TimeInterval
    private var lastCollectedAt: Date = .distantPast
    private var lastTexts: [String] = []

    public init(minInterval: TimeInterval = 2.0) {
        self.minInterval = minInterval
    }

    public func collectTexts(for processIDs: Set<pid_t>, at date: Date = Date()) -> [String] {
        guard !processIDs.isEmpty else { return [] }
        guard date.timeIntervalSince(lastCollectedAt) >= minInterval else {
            return lastTexts
        }
        lastCollectedAt = date

        guard let windowInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else {
            lastTexts = []
            return []
        }

        var texts: [String] = []
        for info in windowInfo {
            guard
                let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                processIDs.contains(ownerPID),
                let layer = info[kCGWindowLayer as String] as? Int,
                layer == 0
            else {
                continue
            }

            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha <= 0 {
                continue
            }

            if let bounds = info[kCGWindowBounds as String] as? [String: Any],
               let width = bounds["Width"] as? Double,
               let height = bounds["Height"] as? Double,
               width < 200 || height < 120 {
                continue
            }

            guard let windowNumber = info[kCGWindowNumber as String] as? NSNumber else {
                continue
            }
            let windowID = CGWindowID(windowNumber.uint32Value)
            guard let image = CGWindowListCreateImage(
                .null,
                .optionIncludingWindow,
                windowID,
                [.boundsIgnoreFraming, .bestResolution]
            ) else {
                continue
            }
            texts.append(contentsOf: recognizeTexts(in: image))
        }

        lastTexts = texts
        return texts
    }

    private func recognizeTexts(in image: CGImage) -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }

        guard let observations = request.results else { return [] }
        return observations.compactMap { $0.topCandidates(1).first?.string }
    }
}
