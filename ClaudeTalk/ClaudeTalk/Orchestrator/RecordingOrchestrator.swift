import AppKit
import Foundation

class RecordingOrchestrator: HotkeyManagerDelegate, AudioEngineDelegate {
    private let audioEngine = AudioEngine()
    private let hotkeyManager: HotkeyManager
    private let notchOverlay = NotchOverlay()
    private let postProcessor = PostProcessor()
    private let terminalDetector: TerminalDetector
    private let settings = Settings.shared
    private var whisper: WhisperWrapper?
    private let modelManager = ModelManager()
    private var isTranscribing = false

    init() {
        hotkeyManager = HotkeyManager(hotkey: settings.hotkey)
        terminalDetector = TerminalDetector(whitelist: settings.terminalWhitelist)
        audioEngine.delegate = self
        hotkeyManager.delegate = self
    }

    // MARK: - Lifecycle

    func start() {
        loadModel()
        hotkeyManager.start()
    }

    func stop() {
        hotkeyManager.stop()
    }

    func reloadSettings() {
        hotkeyManager.updateHotkey(settings.hotkey)

        // Reload model if model size setting changed
        if let currentWhisper = whisper {
            let expectedPath = modelManager.modelPath(for: settings.modelSize).path
            // Reload by nulling out and reloading
            _ = currentWhisper
            whisper = nil
        }
        loadModel()

        // Update notch appearance
        notchOverlay.configure(
            waveformStyle: settings.waveformStyle,
            accentColor: accentNSColor(from: settings.accentColor),
            pillStyle: settings.pillStyle
        )
    }

    // MARK: - HotkeyManagerDelegate

    func hotkeyDidPress() {
        guard !isTranscribing else { return }
        guard terminalDetector.isFocusedAppTerminal() else { return }

        // Update notch appearance from current settings
        notchOverlay.configure(
            waveformStyle: settings.waveformStyle,
            accentColor: accentNSColor(from: settings.accentColor),
            pillStyle: settings.pillStyle
        )

        do {
            try audioEngine.startRecording()
        } catch {
            notchOverlay.state = .error
            return
        }

        notchOverlay.state = .recording
    }

    func hotkeyDidRelease() {
        guard let result = audioEngine.stopRecording() else {
            notchOverlay.state = .discarded
            return
        }

        let samples = result.samples
        let duration = result.duration

        // Discard if too short
        guard duration >= 0.3 else {
            notchOverlay.state = .discarded
            return
        }

        // Discard if too quiet
        let rms = AudioEngine.calculateRMS(samples)
        guard rms > 0.01 else {
            notchOverlay.state = .discarded
            return
        }

        notchOverlay.state = .transcribing
        isTranscribing = true

        #if arch(arm64)
        let beamSize: Int32 = 5
        #else
        let beamSize: Int32 = 3
        #endif

        let language = settings.language
        let promptHint = settings.promptHint
        let removeFillers = settings.removeFillerWords
        let dictionary = PostProcessor.loadDictionary()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            guard let whisper = self.whisper else {
                DispatchQueue.main.async {
                    self.isTranscribing = false
                    self.notchOverlay.state = .error
                }
                return
            }

            let rawText = whisper.transcribe(
                samples: samples,
                language: language,
                beamSize: beamSize,
                promptHint: promptHint.isEmpty ? nil : promptHint
            )

            let processedText = self.postProcessor.process(rawText, enabled: removeFillers, dictionary: dictionary)

            DispatchQueue.main.async {
                self.isTranscribing = false

                guard !processedText.isEmpty else {
                    self.notchOverlay.state = .error
                    return
                }

                // Re-check terminal focus before pasting
                guard self.terminalDetector.isFocusedAppTerminal() else {
                    self.notchOverlay.state = .error
                    return
                }

                InputSimulator.paste(processedText)
                self.notchOverlay.state = .success
            }
        }
    }

    // MARK: - AudioEngineDelegate

    func audioEngine(_ engine: AudioEngine, didUpdateRMS rms: Float) {
        notchOverlay.updateRMS(rms)
    }

    // MARK: - Private Helpers

    private func loadModel() {
        let modelSize = settings.modelSize
        guard modelManager.isDownloaded(modelSize) else { return }

        let path = modelManager.modelPath(for: modelSize).path
        do {
            whisper = try WhisperWrapper(modelPath: path)
        } catch {
            whisper = nil
        }
    }

    private func accentNSColor(from name: String) -> NSColor {
        switch name {
        case "purple": return NSColor(red: 0.66, green: 0.33, blue: 0.97, alpha: 1)
        case "cyan":   return NSColor(red: 0.02, green: 0.71, blue: 0.83, alpha: 1)
        case "green":  return NSColor(red: 0.13, green: 0.77, blue: 0.37, alpha: 1)
        case "orange": return NSColor(red: 0.98, green: 0.45, blue: 0.09, alpha: 1)
        case "pink":   return NSColor(red: 0.93, green: 0.30, blue: 0.60, alpha: 1)
        default:       return .white
        }
    }
}
