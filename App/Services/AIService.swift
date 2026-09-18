import Foundation
import Security

struct AdviceResponse: Codable { var extracted: [String]; var advice: [String]; var cautions: [String]; var questions: [String] }

final class KeychainStore {
    static let shared = KeychainStore()
    func save(_ value: String, account: String) throws {
        let data = Data(value.utf8); let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: account, kSecValueData as String: data]
        SecItemDelete(query as CFDictionary); let status = SecItemAdd(query as CFDictionary, nil); guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
    func read(account: String) -> String? { let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]; var result: AnyObject?; guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }; return String(data: data, encoding: .utf8) }
}

final class AIService {
    func chat(messages: [HealthChatMessage], baseURL: String, model: String, apiKey: String) async throws -> String {
        guard let url = URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions"), url.scheme == "https" else {
            throw NSError(domain: "MrCalender", code: 20, userInfo: [NSLocalizedDescriptionKey: "只允许 HTTPS 服务地址"])
        }
        var request = URLRequest(url: url); request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payloadMessages: [[String: String]] = [["role": "system", "content": "你是健康问诊生活方式助手。只提供一般性的作息、饮食、饮水和运动建议，不做诊断、不处方。信息不足时先提问；遇到急症或危险信号建议立即联系当地急救或医生。使用中文，回答简洁、可执行。"]]
        payloadMessages.append(contentsOf: messages.map { ["role": $0.role == .user ? "user" : "assistant", "content": $0.content] })
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "messages": payloadMessages])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "MrCalender", code: 21, userInfo: [NSLocalizedDescriptionKey: "Agent 服务返回错误"])
        }
        guard let outer = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = outer["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw NSError(domain: "MrCalender", code: 22, userInfo: [NSLocalizedDescriptionKey: "Agent 返回格式无法识别"])
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func analyze(text: String, baseURL: String, model: String, apiKey: String) async throws -> AdviceResponse {
        guard let url = URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions"), url.scheme == "https" else { throw NSError(domain: "MrCalender", code: 20, userInfo: [NSLocalizedDescriptionKey: "只允许 HTTPS 服务地址"]) }
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let system = "你是生活方式规划助手。只给日常管理建议，不诊断、不处方。用中文返回 JSON，字段为 extracted(array), advice(array), cautions(array), questions(array)。没有依据的数值写入 questions。"
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "messages": [["role": "system", "content": system], ["role": "user", "content": text]], "response_format": ["type": "json_object"]])
        let (data, response) = try await URLSession.shared.data(for: request); guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw NSError(domain: "MrCalender", code: 21, userInfo: [NSLocalizedDescriptionKey: "Agent 服务返回错误"]) }
        guard let outer = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = outer["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String,
              let json = content.data(using: .utf8) else {
            throw NSError(domain: "MrCalender", code: 22, userInfo: [NSLocalizedDescriptionKey: "Agent 返回格式无法识别"])
        }
        return try JSONDecoder().decode(AdviceResponse.self, from: json)
    }
}
