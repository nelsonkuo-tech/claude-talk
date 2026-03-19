import AppKit
import AVFoundation
import Foundation

class RecordingOrchestrator: HotkeyManagerDelegate, AudioEngineDelegate {
    private let audioEngine = AudioEngine()
    private let hotkeyManager: HotkeyManager
    private let notchOverlay = NotchOverlay()
    private let postProcessor = PostProcessor()
    private let terminalDetector: TerminalDetector
    private let settings = Settings.shared
    private var whisper: WhisperWrapper?
    private var transcriptionService: TranscriptionService?
    private let modelManager = ModelManager()
    private var isTranscribing = false
    private var isToggleRecording = false  // tracks toggle mode state

    init() {
        hotkeyManager = HotkeyManager(hotkey: settings.hotkey)
        terminalDetector = TerminalDetector(whitelist: settings.terminalWhitelist)
        audioEngine.delegate = self
        hotkeyManager.delegate = self
    }

    // MARK: - Lifecycle

    func start() {
        // Try faster-whisper daemon first (better accuracy)
        let service = TranscriptionService(language: settings.language)
        if service.isAvailable {
            NSLog("[ClaudeTalk] Starting faster-whisper daemon...")
            if service.start() {
                transcriptionService = service
                NSLog("[ClaudeTalk] faster-whisper daemon: YES")
            } else {
                NSLog("[ClaudeTalk] faster-whisper daemon failed, falling back to whisper.cpp")
                loadWhisperCpp()
            }
        } else {
            NSLog("[ClaudeTalk] faster-whisper not available, using whisper.cpp")
            loadWhisperCpp()
        }

        notchOverlay.model.glassStyle = settings.glassStyle

        let started = hotkeyManager.start()
        NSLog("[ClaudeTalk] Hotkey manager started: %@", started ? "YES" : "NO")
        NSLog("[ClaudeTalk] Accessibility trusted: %@", AXIsProcessTrusted() ? "YES" : "NO")
    }

    func stop() {
        hotkeyManager.stop()
        transcriptionService?.stop()
    }

    func reloadSettings() {
        hotkeyManager.updateHotkey(settings.hotkey)
        notchOverlay.model.glassStyle = settings.glassStyle
    }

    // MARK: - HotkeyManagerDelegate

    func hotkeyDidPress() {
        NSLog("[ClaudeTalk] Hotkey pressed!")

        if settings.recordingMode == "toggle" {
            // Toggle mode: press once to start, press again to stop
            if isToggleRecording {
                // Second press: stop recording
                isToggleRecording = false
                stopAndTranscribe()
                return
            }

            // First press: start recording
            guard !isTranscribing else { NSLog("[ClaudeTalk] Skipped: still transcribing"); return }
            let focused = NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown"
            NSLog("[ClaudeTalk] Focused app: %@", focused)
            guard terminalDetector.isFocusedAppTerminal() else { NSLog("[ClaudeTalk] Skipped: %@ not in terminal whitelist", focused); return }

            do {
                try audioEngine.startRecording()
                isToggleRecording = true
            } catch {
                NSLog("[ClaudeTalk] Recording failed: %@", error.localizedDescription)
                notchOverlay.state = .error
                return
            }
            notchOverlay.state = .recording
            return
        }

        // Hold mode: press to start
        guard !isTranscribing else { NSLog("[ClaudeTalk] Skipped: still transcribing"); return }
        let focused = NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown"
        NSLog("[ClaudeTalk] Focused app: %@", focused)
        guard terminalDetector.isFocusedAppTerminal() else { NSLog("[ClaudeTalk] Skipped: %@ not in terminal whitelist", focused); return }

        do {
            try audioEngine.startRecording()
        } catch {
            NSLog("[ClaudeTalk] Recording failed: %@", error.localizedDescription)
            notchOverlay.state = .error
            return
        }

        notchOverlay.state = .recording
    }

    func hotkeyDidRelease() {
        // Toggle mode ignores release
        if settings.recordingMode == "toggle" { return }

        NSLog("[ClaudeTalk] Hotkey released!")
        stopAndTranscribe()
    }

    private func stopAndTranscribe() {
        guard let result = audioEngine.stopRecording() else {
            notchOverlay.state = .discarded
            return
        }

        let samples = result.samples
        let duration = result.duration
        let recordedSampleRate = result.sampleRate

        NSLog("[ClaudeTalk] Recorded: %.2fs, %d samples @ %.0f Hz", duration, samples.count, recordedSampleRate)

        guard duration >= 0.3 else {
            notchOverlay.state = .discarded
            return
        }

        let rms = AudioEngine.calculateRMS(samples)
        guard rms > 0.01 else {
            notchOverlay.state = .discarded
            return
        }

        notchOverlay.state = .transcribing
        isTranscribing = true

        let removeFillers = settings.removeFillerWords
        let dictionary = PostProcessor.loadDictionary()

        if transcriptionService != nil {
            transcribeWithFasterWhisper(samples: samples, sampleRate: recordedSampleRate, removeFillers: removeFillers, dictionary: dictionary)
        } else {
            transcribeWithWhisperCpp(samples: samples, removeFillers: removeFillers, dictionary: dictionary)
        }
    }

    // MARK: - AudioEngineDelegate

    func audioEngine(_ engine: AudioEngine, didUpdateRMS rms: Float) {
        notchOverlay.updateRMS(rms)
    }

    func audioEngine(_ engine: AudioEngine, didUpdateSpectrum bands: [Float]) {
        notchOverlay.model.updateSpectrum(bands)
    }

    // MARK: - Transcription

    private func transcribeWithFasterWhisper(samples: [Float], sampleRate: Double, removeFillers: Bool, dictionary: [String: String]) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, let service = self.transcriptionService else {
                DispatchQueue.main.async {
                    self?.isTranscribing = false
                    self?.notchOverlay.state = .error
                }
                return
            }

            // Write samples to temp WAV file at native sample rate
            let wavPath = self.writeTempWAV(samples: samples, sampleRate: sampleRate)
            guard let path = wavPath else {
                DispatchQueue.main.async {
                    self.isTranscribing = false
                    self.notchOverlay.state = .error
                }
                return
            }

            let rawText = service.transcribe(wavPath: path) ?? ""

            // Clean up temp file
            try? FileManager.default.removeItem(atPath: path)

            let processedText = self.postProcessor.process(rawText, enabled: removeFillers, dictionary: dictionary)

            DispatchQueue.main.async {
                self.isTranscribing = false
                self.finishTranscription(processedText)
            }
        }
    }

    private func transcribeWithWhisperCpp(samples: [Float], removeFillers: Bool, dictionary: [String: String]) {
        let language = settings.language
        let promptHint = settings.promptHint

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, let whisper = self.whisper else {
                DispatchQueue.main.async {
                    self?.isTranscribing = false
                    self?.notchOverlay.state = .error
                }
                return
            }

            let rawText = whisper.transcribe(
                samples: samples,
                language: language,
                beamSize: 5,
                promptHint: promptHint.isEmpty ? nil : promptHint
            )

            let processedText = self.postProcessor.process(rawText, enabled: removeFillers, dictionary: dictionary)

            DispatchQueue.main.async {
                self.isTranscribing = false
                self.finishTranscription(processedText)
            }
        }
    }

    private func finishTranscription(_ text: String) {
        guard !text.isEmpty else {
            notchOverlay.state = .error
            return
        }

        guard terminalDetector.isFocusedAppTerminal() else {
            notchOverlay.state = .error
            return
        }

        InputSimulator.paste(text)
        notchOverlay.state = .success
    }

    // MARK: - WAV Writing

    private func writeTempWAV(samples: [Float], sampleRate: Double) -> String? {
        let tempDir = FileManager.default.temporaryDirectory
        let path = tempDir.appendingPathComponent("claude-talk-\(UUID().uuidString).wav").path

        // Convert float samples to int16
        var int16Samples = [Int16](repeating: 0, count: samples.count)
        for i in 0..<samples.count {
            let clamped = max(-1.0, min(1.0, samples[i]))
            int16Samples[i] = Int16(clamped * 32767)
        }

        // Write raw WAV file (16-bit PCM mono)
        let dataSize = UInt32(samples.count * 2)
        let sampleRateU32 = UInt32(sampleRate)
        let byteRate = sampleRateU32 * 2  // 16-bit mono = 2 bytes per sample
        var header = Data()

        // RIFF header
        header.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        var chunkSize = dataSize + 36
        header.append(Data(bytes: &chunkSize, count: 4))
        header.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"

        // fmt subchunk
        header.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        var subchunk1Size: UInt32 = 16
        header.append(Data(bytes: &subchunk1Size, count: 4))
        var audioFormat: UInt16 = 1  // PCM
        header.append(Data(bytes: &audioFormat, count: 2))
        var numChannels: UInt16 = 1
        header.append(Data(bytes: &numChannels, count: 2))
        var sr = sampleRateU32
        header.append(Data(bytes: &sr, count: 4))
        var br = byteRate
        header.append(Data(bytes: &br, count: 4))
        var blockAlign: UInt16 = 2
        header.append(Data(bytes: &blockAlign, count: 2))
        var bitsPerSample: UInt16 = 16
        header.append(Data(bytes: &bitsPerSample, count: 2))

        // data subchunk
        header.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        var ds = dataSize
        header.append(Data(bytes: &ds, count: 4))

        // Write file
        var fileData = header
        int16Samples.withUnsafeBufferPointer { buf in
            fileData.append(UnsafeBufferPointer(start: UnsafeRawPointer(buf.baseAddress!)
                .assumingMemoryBound(to: UInt8.self), count: samples.count * 2))
        }

        return FileManager.default.createFile(atPath: path, contents: fileData) ? path : nil
    }

    // MARK: - Model Loading

    private func loadWhisperCpp() {
        let modelSize = settings.modelSize
        guard modelManager.isDownloaded(modelSize) else { return }

        let path = modelManager.modelPath(for: modelSize).path
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let vadPath = appSupport.appendingPathComponent("Claude Talk/models/silero-vad.bin").path
        let resolvedVadPath = FileManager.default.fileExists(atPath: vadPath) ? vadPath : nil

        do {
            whisper = try WhisperWrapper(modelPath: path, vadModelPath: resolvedVadPath)
            NSLog("[ClaudeTalk] whisper.cpp loaded: YES")
        } catch {
            whisper = nil
            NSLog("[ClaudeTalk] whisper.cpp loaded: NO")
        }
    }
}
