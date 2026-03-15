import Foundation

enum ModelError: Error {
    case downloadFailed
}

class ModelManager {
    static let baseURL = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main"

    private var progressObservation: NSKeyValueObservation?

    var modelsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Claude Talk/models")
    }

    func filename(for model: String) -> String {
        "ggml-\(model).bin"
    }

    func modelPath(for model: String) -> URL {
        modelsDirectory.appendingPathComponent(filename(for: model))
    }

    func isDownloaded(_ model: String) -> Bool {
        FileManager.default.fileExists(atPath: modelPath(for: model).path)
    }

    func download(_ model: String, progress: @escaping (Double) -> Void, completion: @escaping (Result<URL, Error>) -> Void) {
        // Ensure models directory exists
        do {
            try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            completion(.failure(error))
            return
        }

        let urlString = "\(ModelManager.baseURL)/\(filename(for: model))"
        guard let url = URL(string: urlString) else {
            completion(.failure(ModelError.downloadFailed))
            return
        }

        let destination = modelPath(for: model)
        let session = URLSession.shared
        let task = session.downloadTask(with: url) { [weak self] tempURL, response, error in
            self?.progressObservation?.invalidate()
            self?.progressObservation = nil

            if let error = error {
                completion(.failure(error))
                return
            }

            guard let tempURL = tempURL else {
                completion(.failure(ModelError.downloadFailed))
                return
            }

            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: tempURL, to: destination)
                completion(.success(destination))
            } catch {
                completion(.failure(error))
            }
        }

        // Store observation as instance property to prevent deallocation
        progressObservation = task.progress.observe(\.fractionCompleted) { taskProgress, _ in
            progress(taskProgress.fractionCompleted)
        }

        task.resume()
    }
}
