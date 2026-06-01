import AppKit
import Foundation
@preconcurrency import Vision

@MainActor
protocol OCRServicing {
    func recognizeText(from image: NSImage) async -> String?
}

@MainActor
final class OCRService: OCRServicing {
    func recognizeText(from image: NSImage) async -> String? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            BufferLogger.clipboard.error("Failed to create CGImage for OCR")
            return nil
        }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    BufferLogger.clipboard.error("OCR recognition error: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(returning: nil)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: nil)
                    return
                }

                let recognizedStrings = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }

                continuation.resume(returning: recognizedStrings.isEmpty ? nil : recognizedStrings.joined(separator: "\n"))
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            Task.detached(priority: .userInitiated) {
                do {
                    try handler.perform([request])
                } catch {
                    BufferLogger.clipboard.error("OCR request failed: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
