import Foundation

class WhisperWrapper {
    private var context: OpaquePointer?

    init(modelPath: String) throws {
        var params = whisper_context_default_params()
        context = whisper_init_from_file_with_params(modelPath, params)
        guard context != nil else { throw WhisperError.modelLoadFailed }
    }

    deinit {
        if let ctx = context { whisper_free(ctx) }
    }

    func transcribe(samples: [Float], language: String? = nil, beamSize: Int32 = 5, promptHint: String? = nil) -> String {
        // CRITICAL: language and promptHint are C string pointers that must stay alive
        // during the whisper_full call. Use nested withCString closures.

        var params = whisper_full_default_params(WHISPER_SAMPLING_BEAM_SEARCH)
        params.n_threads = Int32(max(1, ProcessInfo.processInfo.activeProcessorCount - 1))
        params.beam_search.beam_size = beamSize
        params.print_progress = false
        params.print_timestamps = false

        // Nest withCString calls so pointers are valid when whisper_full runs
        let runTranscription = { (langPtr: UnsafePointer<CChar>?, promptPtr: UnsafePointer<CChar>?) -> Int32 in
            var p = params
            p.language = langPtr
            p.initial_prompt = promptPtr
            return samples.withUnsafeBufferPointer { buf in
                whisper_full(self.context, p, buf.baseAddress, Int32(samples.count))
            }
        }

        let callWithPrompt = { (promptPtr: UnsafePointer<CChar>?) -> Int32 in
            if let lang = language {
                return lang.withCString { langPtr in runTranscription(langPtr, promptPtr) }
            } else {
                return runTranscription(nil, promptPtr)
            }
        }

        let result: Int32
        if let prompt = promptHint, !prompt.isEmpty {
            result = prompt.withCString { promptPtr in callWithPrompt(promptPtr) }
        } else {
            result = callWithPrompt(nil)
        }

        guard result == 0 else { return "" }

        // Collect segments
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
