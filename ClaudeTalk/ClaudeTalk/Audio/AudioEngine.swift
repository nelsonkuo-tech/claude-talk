import Accelerate
import AVFoundation
import Foundation

protocol AudioEngineDelegate: AnyObject {
    func audioEngine(_ engine: AudioEngine, didUpdateRMS rms: Float)
    func audioEngine(_ engine: AudioEngine, didUpdateSpectrum bands: [Float])
}

class AudioEngine {
    weak var delegate: AudioEngineDelegate?
    private let engine = AVAudioEngine()
    private var buffer = [Float]()
    private let lock = NSLock()
    private(set) var nativeSampleRate: Double = 48000
    var isRecording: Bool { engine.isRunning }

    // FFT setup
    private let fftSize = 1024
    private var fftSetup: vDSP_DFT_Setup?
    private let bandCount = 7

    init() {
        fftSetup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(fftSize), .FORWARD)
    }

    deinit {
        if let setup = fftSetup {
            vDSP_DFT_DestroySetup(setup)
        }
    }

    func startRecording() throws {
        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        nativeSampleRate = inputFormat.sampleRate

        NSLog("[ClaudeTalk] AudioEngine: native format = %@ Hz, %d ch",
              String(format: "%.0f", nativeSampleRate), inputFormat.channelCount)

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

        inputNode.installTap(onBus: 0, bufferSize: UInt32(fftSize), format: monoFormat) { [weak self] pcmBuffer, _ in
            guard let self = self else { return }

            let frameCount = Int(pcmBuffer.frameLength)
            guard frameCount > 0,
                  let channelData = pcmBuffer.floatChannelData?[0] else { return }

            let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))

            self.lock.lock()
            self.buffer.append(contentsOf: samples)
            self.lock.unlock()

            let rms = AudioEngine.calculateRMS(samples)
            let bands = self.computeSpectrum(samples)

            DispatchQueue.main.async {
                self.delegate?.audioEngine(self, didUpdateRMS: rms)
                self.delegate?.audioEngine(self, didUpdateSpectrum: bands)
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

    // MARK: - FFT Spectrum

    private func computeSpectrum(_ samples: [Float]) -> [Float] {
        guard let setup = fftSetup else {
            return [Float](repeating: 0, count: bandCount)
        }

        // Prepare input: pad or truncate to fftSize
        var input = [Float](repeating: 0, count: fftSize)
        let count = min(samples.count, fftSize)
        for i in 0..<count {
            input[i] = samples[i]
        }

        // Apply Hann window
        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        vDSP_vmul(input, 1, window, 1, &input, 1, vDSP_Length(fftSize))

        // Run FFT
        var realIn = input
        var imagIn = [Float](repeating: 0, count: fftSize)
        var realOut = [Float](repeating: 0, count: fftSize)
        var imagOut = [Float](repeating: 0, count: fftSize)

        vDSP_DFT_Execute(setup, &realIn, &imagIn, &realOut, &imagOut)

        // Compute magnitudes (only first half is useful)
        let halfSize = fftSize / 2
        var magnitudes = [Float](repeating: 0, count: halfSize)
        for i in 0..<halfSize {
            magnitudes[i] = sqrt(realOut[i] * realOut[i] + imagOut[i] * imagOut[i])
        }

        // Map frequency bins to bands focused on voice range
        // Voice: ~85Hz - 4000Hz
        // At 48kHz sample rate, bin resolution = 48000/1024 ≈ 46.9 Hz per bin
        // bin 2 ≈ 94Hz, bin 85 ≈ 4000Hz
        let binPerHz = Float(nativeSampleRate) / Float(fftSize)
        let voiceBands: [(low: Float, high: Float)] = [
            (80, 200),     // Low fundamentals
            (200, 400),    // Low-mid voice body
            (400, 800),    // Mid voice (main energy)
            (800, 1500),   // Upper-mid voice
            (1500, 2500),  // Presence / clarity
            (2500, 4000),  // Sibilance
            (4000, 8000),  // Air / breath
        ]

        var bands = [Float](repeating: 0, count: bandCount)
        for (idx, range) in voiceBands.enumerated() {
            let startBin = max(1, Int(range.low / binPerHz))
            let endBin = min(halfSize - 1, Int(range.high / binPerHz))
            guard endBin > startBin else { continue }

            var sum: Float = 0
            for bin in startBin...endBin {
                sum += magnitudes[bin]
            }
            let avg = sum / Float(endBin - startBin + 1)

            // Convert to dB-like scale, normalize to 0-1
            let db = 20 * log10(max(avg, 1e-10))
            let normalized = max(0, min(1, (db + 40) / 50))  // -40dB to +10dB → 0 to 1
            bands[idx] = normalized
        }

        return bands
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
