import AVFoundation
import Foundation

public struct AudioChunkInfo {
    public let samples: [Float]
    public let chunkOffsetSeconds: Double
    public let isFirstChunk: Bool

    public init(samples: [Float], chunkOffsetSeconds: Double, isFirstChunk: Bool) {
        self.samples = samples
        self.chunkOffsetSeconds = chunkOffsetSeconds
        self.isFirstChunk = isFirstChunk
    }
}

public struct AudioChunker {
    public let sampleRate: Double
    public let chunkDurationSeconds: Double
    public let overlapSeconds: Double

    public var chunkSampleCount: Int { Int(chunkDurationSeconds * sampleRate) }
    public var overlapSampleCount: Int { Int(overlapSeconds * sampleRate) }

    public init(
        sampleRate: Double = 16_000,
        chunkDurationSeconds: Double = 5 * 60,
        overlapSeconds: Double = 30
    ) {
        self.sampleRate = sampleRate
        self.chunkDurationSeconds = chunkDurationSeconds
        self.overlapSeconds = overlapSeconds
    }

    /// WAV ファイルを読み込み、チャンクの配列を返す。
    ///
    /// - チャンク 0 はファイル先頭から chunkDurationSeconds 分を読む（オーバーラップなし）。
    /// - チャンク i > 0 はチャンク i-1 の末尾 overlapSeconds 分から読み始め、
    ///   chunkDurationSeconds + overlapSeconds 分（またはファイル末尾まで）を読む。
    /// - `chunkOffsetSeconds` は読み始めのファイル内絶対時刻（秒）。
    public func chunks(from audioURL: URL) throws -> [AudioChunkInfo] {
        let file = try AVAudioFile(forReading: audioURL)
        let totalFrames = Int(file.length)
        guard totalFrames > 0 else { return [] }

        let format = file.processingFormat
        var result: [AudioChunkInfo] = []
        var chunkIndex = 0

        while true {
            // 新しい内容の先頭フレーム（前チャンクが担当した範囲の終端）
            let newContentStartFrame = chunkIndex * chunkSampleCount
            if newContentStartFrame >= totalFrames { break }

            let isFirstChunk = chunkIndex == 0
            let readFromFrame: Int
            let readCount: Int

            if isFirstChunk {
                // チャンク 0: オーバーラップなしで先頭から読む
                readFromFrame = 0
                readCount = min(chunkSampleCount, totalFrames)
            } else {
                // チャンク i: overlapSeconds 分だけ前から読み始める
                readFromFrame = max(0, newContentStartFrame - overlapSampleCount)
                readCount = min(chunkSampleCount + overlapSampleCount, totalFrames - readFromFrame)
            }

            let chunkOffsetSeconds = Double(readFromFrame) / sampleRate

            file.framePosition = AVAudioFramePosition(readFromFrame)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(readCount))!
            try file.read(into: buffer, frameCount: AVAudioFrameCount(readCount))

            let samples = Array(UnsafeBufferPointer(
                start: buffer.floatChannelData!.pointee,
                count: Int(buffer.frameLength)
            ))

            result.append(AudioChunkInfo(
                samples: samples,
                chunkOffsetSeconds: chunkOffsetSeconds,
                isFirstChunk: isFirstChunk
            ))

            chunkIndex += 1
        }

        return result
    }

    /// 各チャンクの推論結果セグメントをマージして単一タイムラインに変換する。
    ///
    /// - 非先頭チャンクのオーバーラップ領域（startTime < overlapSeconds）のセグメントを破棄する。
    /// - 残ったセグメントに chunkOffsetSeconds を加算して絶対時刻に変換する。
    public static func mergeSegments(
        chunks: [(info: AudioChunkInfo, segments: [TranscriptSegment])],
        overlapSeconds: Double
    ) -> [TranscriptSegment] {
        var result: [TranscriptSegment] = []
        for (info, segments) in chunks {
            for segment in segments {
                if !info.isFirstChunk && segment.start < overlapSeconds {
                    continue
                }
                result.append(TranscriptSegment(
                    start: segment.start + info.chunkOffsetSeconds,
                    end: segment.end + info.chunkOffsetSeconds,
                    text: segment.text
                ))
            }
        }
        return result
    }
}
