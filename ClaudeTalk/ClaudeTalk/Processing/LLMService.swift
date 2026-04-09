import Foundation

class LLMService {
    private let settings = Settings.shared

    /// Polish raw transcription text using LLM.
    /// Calls completion on the calling queue (background).
    func polish(_ text: String, completion: @escaping (Result<String, Error>) -> Void) {
        let apiKey = settings.llmApiKey
        guard !apiKey.isEmpty else {
            completion(.failure(LLMError.noApiKey))
            return
        }

        let prompt = buildPrompt(text)
        let provider = settings.llmProvider

        if provider == "anthropic" {
            callAnthropic(prompt: prompt, apiKey: apiKey, completion: completion)
        } else {
            callOpenAICompatible(prompt: prompt, apiKey: apiKey, completion: completion)
        }
    }

    // MARK: - Prompt

    private func buildPrompt(_ text: String) -> String {
        let targetLang = settings.llmTargetLanguage
        let langLine: String
        if let lang = targetLang, !lang.isEmpty {
            langLine = "\n6. 整理后翻译为\(lang)"
        } else {
            langLine = ""
        }

        return """
        你是语音转文字的后处理助手。以下文本来自语音识别（Whisper），由于语速、音量等因素，经常产生同音字或近音字错误。

        请进行整理：
        1. 根据上下文推断并修正语音识别错误（例如：「语数据」→「语音输出」、「視別」→「识别」、「出發」→「触发」）。即使某个词看似合理，如果放在上下文中不通顺，也要修正
        2. 修正不通顺的语句，使其更有条理
        3. 保留原意，不要添加内容
        4. 去除口语化的赘词和重复
        5. 正确使用标点符号（逗号、句号、问号、冒号等）
        6. 当提到多个要点、步骤或项目时，用 bullet point（- ）列出，每点一行
        7. 根据语意分段，每个段落聚焦一个主题\(langLine)

        直接输出整理后的文字，不要加任何说明或前缀。

        原文：
        \(text)
        """
    }

    // MARK: - Anthropic Messages API

    private func callAnthropic(prompt: String, apiKey: String, completion: @escaping (Result<String, Error>) -> Void) {
        let baseURL = settings.llmBaseURL
        guard let url = URL(string: "\(baseURL)/v1/messages") else {
            completion(.failure(LLMError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model": settings.llmModel,
            "max_tokens": 4096,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            completion(.failure(LLMError.serializationFailed))
            return
        }
        request.httpBody = httpBody

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                NSLog("[ClaudeTalk] LLM request failed: %@", error.localizedDescription)
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.failure(LLMError.noData))
                return
            }

            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let content = json["content"] as? [[String: Any]],
                      let first = content.first,
                      let text = first["text"] as? String else {
                    NSLog("[ClaudeTalk] LLM unexpected response: %@", String(data: data, encoding: .utf8) ?? "nil")
                    completion(.failure(LLMError.unexpectedResponse))
                    return
                }
                completion(.success(text.trimmingCharacters(in: .whitespacesAndNewlines)))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    // MARK: - OpenAI-Compatible Chat Completions API

    private func callOpenAICompatible(prompt: String, apiKey: String, completion: @escaping (Result<String, Error>) -> Void) {
        let baseURL = settings.llmBaseURL
        guard let url = URL(string: "\(baseURL)/v1/chat/completions") else {
            completion(.failure(LLMError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "model": settings.llmModel,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        guard let httpBody = try? JSONSerialization.data(withJSONObject: body) else {
            completion(.failure(LLMError.serializationFailed))
            return
        }
        request.httpBody = httpBody

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                NSLog("[ClaudeTalk] LLM request failed: %@", error.localizedDescription)
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.failure(LLMError.noData))
                return
            }

            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choices = json["choices"] as? [[String: Any]],
                      let first = choices.first,
                      let message = first["message"] as? [String: Any],
                      let text = message["content"] as? String else {
                    NSLog("[ClaudeTalk] LLM unexpected response: %@", String(data: data, encoding: .utf8) ?? "nil")
                    completion(.failure(LLMError.unexpectedResponse))
                    return
                }
                completion(.success(text.trimmingCharacters(in: .whitespacesAndNewlines)))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}

// MARK: - Errors

enum LLMError: LocalizedError {
    case noApiKey
    case invalidURL
    case serializationFailed
    case noData
    case unexpectedResponse

    var errorDescription: String? {
        switch self {
        case .noApiKey: return "No LLM API key configured"
        case .invalidURL: return "Invalid LLM base URL"
        case .serializationFailed: return "Failed to serialize request"
        case .noData: return "No data in LLM response"
        case .unexpectedResponse: return "Unexpected LLM response format"
        }
    }
}
