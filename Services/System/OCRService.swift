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

        let token = BufferPerformanceDiagnostics.begin(.ocr)
        let state = OCRRequestState(token: token)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let request = VNRecognizeTextRequest { request, error in
                    if let error {
                        if !state.wasCancelled {
                            BufferLogger.clipboard.error(
                                "OCR recognition error: \(error.localizedDescription, privacy: .public)")
                        }
                        state.finish(with: nil)
                        return
                    }

                    guard let observations = request.results as? [VNRecognizedTextObservation] else {
                        state.finish(with: nil)
                        return
                    }

                    let recognizedStrings = observations.compactMap { observation in
                        observation.topCandidates(1).first?.string
                    }

                    state.finish(
                        with: recognizedStrings.isEmpty
                            ? nil
                            : recognizedStrings.joined(separator: "\n")
                    )
                }

                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true

                guard state.install(continuation: continuation, request: request) else {
                    return
                }

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                Task.detached(priority: .userInitiated) {
                    do {
                        try handler.perform([request])
                    } catch {
                        if !state.wasCancelled {
                            BufferLogger.clipboard.error(
                                "OCR request failed: \(error.localizedDescription, privacy: .public)")
                        }
                        state.finish(with: nil)
                    }
                }
            }
        } onCancel: {
            state.cancel()
        }
    }
}

private final class OCRRequestState: @unchecked Sendable {
    private let lock = NSLock()
    private let token: BufferPerformanceDiagnostics.Token
    private var continuation: CheckedContinuation<String?, Never>?
    private var request: VNRequest?
    private var cancelled = false
    private var finished = false

    init(token: BufferPerformanceDiagnostics.Token) {
        self.token = token
    }

    var wasCancelled: Bool {
        lock.lock()
        let value = cancelled
        lock.unlock()
        return value
    }

    func install(
        continuation: CheckedContinuation<String?, Never>,
        request: VNRequest
    ) -> Bool {
        lock.lock()
        let shouldStart = !cancelled && !finished
        if shouldStart {
            self.continuation = continuation
            self.request = request
        }
        lock.unlock()

        guard shouldStart else {
            request.cancel()
            finishUninstalled(continuation: continuation)
            return false
        }

        return true
    }

    func cancel() {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }

        cancelled = true
        let pendingRequest = request
        let pendingContinuation = continuation
        if pendingContinuation != nil {
            finished = true
            self.request = nil
            self.continuation = nil
        }
        lock.unlock()

        pendingRequest?.cancel()
        if let pendingContinuation {
            BufferPerformanceDiagnostics.end(token)
            pendingContinuation.resume(returning: nil)
        }
    }

    func finish(with result: String?) {
        lock.lock()
        let pendingContinuation = continuation
        let shouldFinish = !finished && pendingContinuation != nil
        if shouldFinish {
            finished = true
            self.request = nil
            self.continuation = nil
        }
        lock.unlock()

        guard shouldFinish,
            let pendingContinuation
        else {
            return
        }

        BufferPerformanceDiagnostics.end(token)
        pendingContinuation.resume(returning: result)
    }

    private func finishUninstalled(continuation: CheckedContinuation<String?, Never>) {
        lock.lock()
        let shouldFinish = !finished
        if shouldFinish {
            finished = true
        }
        lock.unlock()

        guard shouldFinish else {
            return
        }

        BufferPerformanceDiagnostics.end(token)
        continuation.resume(returning: nil)
    }
}
