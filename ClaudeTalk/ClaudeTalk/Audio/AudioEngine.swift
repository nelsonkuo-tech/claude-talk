import AVFoundation
import Foundation

protocol AudioEngineDelegate: AnyObject {
    func audioEngine(_ engine: AudioEngine, didUpdateRMS rms: Float)
}

class AudioEngine {
    weak var delegate: AudioEngineDelegate?
    private let engine = AVAudioEngine()
    private var buffer = [Float]()
    private let lock = NSLock()
    private(set) var nativeSampleRate: Double = 48000
    var isRecording: Bool { engine.isRunning }

    func startRecording() throws {
        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        nativeSampleRate = inputFormat.sampleRate

        NSLog("[ClaudeTalk] AudioEngine: native format = %@ Hz, %d ch",
              String(format: "%.0f", nativeSampleRate), inputFormat.channelCount)

        // Record in mono float32 at native sample rate (no conversion = no data loss)
        guard let monoFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: nativeSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioEngineError.formatCreationFailed
        }

        lock.lock()
        buffer.removeAll()
        lock.unlock()

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: monoFormat) { [weak self] pcmBuffer, _ in
            guard let self = self else { return }

            let frameCount = Int(pcmBuffer.frameLength)
            guard frameCount > 0,
                  let channelData = pcmBuffer.floatChannelData?[0] else { return }

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

    func stopRecording() -> (samples: [Float], duration: Double, sampleRate: Double)? {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        lock.lock()
        let captured = buffer
        buffer.removeAll()
        lock.unlock()

        guard !captured.isEmpty else { return nil }

        let duration = Double(captured.count) / nativeSampleRate
        return (samples: captured, duration: duration, sampleRate: nativeSampleRate)
    }

    static func calculateRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumOfSquares = samples.reduce(0) { $0 + $1 * $1 }
        return sqrt(sumOfSquares / Float(samples.count))
    }
}

enum AudioEngineError: Error, LocalizedError {
    case formatCreationFailed

    var errorDescription: String? {
        switch self {
        case .formatCreationFailed:
            return "Failed to create audio format"
        }
    }
}
