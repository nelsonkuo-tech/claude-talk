import AVFoundation
import Foundation

protocol AudioEngineDelegate: AnyObject {
    func audioEngine(_ engine: AudioEngine, didUpdateRMS rms: Float)
}

class AudioEngine {
    weak var delegate: AudioEngineDelegate?
    private let engine = AVAudioEngine()
    private var buffer = [Float]()
    private let sampleRate: Double = 16000
    private let lock = NSLock()
    var isRecording: Bool { engine.isRunning }

    func startRecording() throws {
        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioEngineError.formatCreationFailed
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioEngineError.converterCreationFailed
        }

        lock.lock()
        buffer.removeAll()
        lock.unlock()

        let outputFrameCapacity: AVAudioFrameCount = 1024
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] inputBuffer, _ in
            guard let self = self else { return }

            guard let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: outputFrameCapacity
            ) else { return }

            var error: NSError?
            var inputConsumed = false

            let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                if inputConsumed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                inputConsumed = true
                outStatus.pointee = .haveData
                return inputBuffer
            }

            guard status != .error, error == nil else { return }

            let frameCount = Int(outputBuffer.frameLength)
            guard frameCount > 0,
                  let channelData = outputBuffer.floatChannelData?[0] else { return }

            let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))

            self.lock.lock()
            self.buffer.append(contentsOf: samples)
            self.lock.unlock()

            let rms = AudioEngine.calculateRMS(samples)
            DispatchQueue.main.async {
                self.delegate?.audioEngine(self, didUpdateRMS: rms)
            }
        }

        engine.prepare()
        try engine.start()
    }

    func stopRecording() -> (samples: [Float], duration: Double)? {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        lock.lock()
        let captured = buffer
        buffer.removeAll()
        lock.unlock()

        guard !captured.isEmpty else { return nil }

        let duration = Double(captured.count) / sampleRate
        return (samples: captured, duration: duration)
    }

    static func calculateRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumOfSquares = samples.reduce(0) { $0 + $1 * $1 }
        return sqrt(sumOfSquares / Float(samples.count))
    }
}

enum AudioEngineError: Error, LocalizedError {
    case formatCreationFailed
    case converterCreationFailed

    var errorDescription: String? {
        switch self {
        case .formatCreationFailed:
            return "Failed to create 16kHz mono float32 audio format"
        case .converterCreationFailed:
            return "Failed to create audio format converter"
        }
    }
}
