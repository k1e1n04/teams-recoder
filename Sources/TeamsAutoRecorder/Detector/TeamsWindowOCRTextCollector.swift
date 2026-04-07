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
            guard Self.shouldProcessWindowInfo(info, processIDs: processIDs) else {
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

        guard let rawObservations = request.results, !rawObservations.isEmpty else {
            return []
        }
        let observations = Array(rawObservations)
        var texts: [String] = []
        texts.reserveCapacity(observations.count)
        for observation in observations {
            if let text = observation.topCandidates(1).first?.string {
                texts.append(text)
            }
        }
        return texts
    }

    static func shouldProcessWindowInfo(
        _ info: [String: Any],
        processIDs: Set<pid_t>
    ) -> Bool {
        let ownerPID: pid_t
        if let pid = info[kCGWindowOwnerPID as String] as? pid_t {
            ownerPID = pid
        } else if let number = info[kCGWindowOwnerPID as String] as? NSNumber {
            ownerPID = pid_t(number.int32Value)
        } else if let integer = info[kCGWindowOwnerPID as String] as? Int {
            ownerPID = pid_t(integer)
        } else {
            return false
        }

        guard processIDs.contains(ownerPID) else {
            return false
        }

        if let alpha = info[kCGWindowAlpha as String] as? Double, alpha <= 0 {
            return false
        }

        if let bounds = info[kCGWindowBounds as String] as? [String: Any],
           let width = bounds["Width"] as? Double,
           let height = bounds["Height"] as? Double,
           width < 200 || height < 120 {
            return false
        }

        return true
    }
}
