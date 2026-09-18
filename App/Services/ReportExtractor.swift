import Foundation
import PDFKit
import Vision
import UIKit

enum ReportExtractor {
    static func text(from url: URL) async throws -> String {
        guard url.startAccessingSecurityScopedResource() else { throw NSError(domain: "MrCalender", code: 30, userInfo: [NSLocalizedDescriptionKey: "无法读取所选文件"]) }
        defer { url.stopAccessingSecurityScopedResource() }
        if url.pathExtension.lowercased() == "pdf" {
            guard let document = PDFDocument(url: url) else { throw NSError(domain: "MrCalender", code: 31, userInfo: [NSLocalizedDescriptionKey: "PDF 无法打开"]) }
            let text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw NSError(domain: "MrCalender", code: 32, userInfo: [NSLocalizedDescriptionKey: "PDF 没有可提取的文字，请复制文字或使用截图 OCR"]) }
            return text
        }
        guard let image = UIImage(contentsOfFile: url.path)?.cgImage else { throw NSError(domain: "MrCalender", code: 33, userInfo: [NSLocalizedDescriptionKey: "图片无法打开"]) }
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error { continuation.resume(throwing: error); return }
                let lines = (request.results as? [VNRecognizedTextObservation])?.compactMap { $0.topCandidates(1).first?.string } ?? []
                guard !lines.isEmpty else { continuation.resume(throwing: NSError(domain: "MrCalender", code: 34, userInfo: [NSLocalizedDescriptionKey: "图片中没有识别到文字"])); return }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate; request.recognitionLanguages = ["zh-Hans", "en-US"]; request.usesLanguageCorrection = true
            DispatchQueue.global(qos: .userInitiated).async { do { try VNImageRequestHandler(cgImage: image, options: [:]).perform([request]) } catch { continuation.resume(throwing: error) } }
        }
    }
}
