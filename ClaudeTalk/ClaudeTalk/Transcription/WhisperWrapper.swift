import Foundation

class WhisperWrapper {
    private var context: OpaquePointer?
    private var vadModelPath: String?

    init(modelPath: String, vadModelPath: String? = nil) throws {
        var params = whisper_context_default_params()
        context = whisper_init_from_file_with_params(modelPath, params)
        guard context != nil else { throw WhisperError.modelLoadFailed }
        self.vadModelPath = vadModelPath
    }

    deinit {
        if let ctx = context { whisper_free(ctx) }
    }

    func transcribe(samples: [Float], language: String? = nil, beamSize: Int32 = 5, promptHint: String? = nil) -> String {
        // Greedy sampling for speed — beam search too slow for real-time
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.n_threads = Int32(max(1, ProcessInfo.processInfo.activeProcessorCount - 1))
        params.greedy.best_of = 1
        params.print_progress = false
        params.print_timestamps = false
        params.single_segment = true   // Don't split into multiple segments
        params.no_context = true       // Don't use previous context (each recording is independent)

        // Enable VAD if model path is available
        if let vadPath = vadModelPath {
            params.vad = true
        }

        // Suppress non-speech tokens to reduce hallucination
        params.no_speech_thold = 0.6
        params.entropy_thold = 2.4

        // Nest withCString calls so pointers are valid when whisper_full runs
        let runTranscription = { [self] (langPtr: UnsafePointer<CChar>?, promptPtr: UnsafePointer<CChar>?, vadPtr: UnsafePointer<CChar>?) -> Int32 in
            var p = params
            p.language = langPtr
            p.initial_prompt = promptPtr
            p.vad_model_path = vadPtr
            return samples.withUnsafeBufferPointer { buf in
                whisper_full(self.context, p, buf.baseAddress, Int32(samples.count))
            }
        }

        let callWithVAD = { (langPtr: UnsafePointer<CChar>?, promptPtr: UnsafePointer<CChar>?) -> Int32 in
            if let vadPath = self.vadModelPath {
                return vadPath.withCString { vadPtr in runTranscription(langPtr, promptPtr, vadPtr) }
            } else {
                return runTranscription(langPtr, promptPtr, nil)
            }
        }

        let callWithPrompt = { (promptPtr: UnsafePointer<CChar>?) -> Int32 in
            if let lang = language {
                return lang.withCString { langPtr in callWithVAD(langPtr, promptPtr) }
            } else {
                return callWithVAD(nil, promptPtr)
            }
        }

        let result: Int32
        if let prompt = promptHint, !prompt.isEmpty {
            result = prompt.withCString { promptPtr in callWithPrompt(promptPtr) }
        } else {
            result = callWithPrompt(nil)
        }

        guard result == 0 else { return "" }

        let nSegments = whisper_full_n_segments(context)
        var text = ""
        for i in 0..<nSegments {
            if let cStr = whisper_full_get_segment_text(context, i) {
                text += String(cString: cStr)
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum WhisperError: Error {
    case modelLoadFailed
}
