import AppKit

enum PastePayload: Equatable, Sendable {
    case string(String)
    case fileURLs([URL])
    case tiff(Data)
}

struct PasteStep: Equatable, Sendable {
    let payload: PastePayload
    let delayBeforeExecution: TimeInterval
}

struct PastePlan: Equatable, Sendable {
    let id: UUID
    let steps: [PasteStep]
    let temporaryAssetSessionID: UUID?
    let completedStepCount: Int

    init(
        id: UUID,
        steps: [PasteStep],
        temporaryAssetSessionID: UUID?,
        completedStepCount: Int = 0
    ) {
        self.id = id
        self.steps = steps
        self.temporaryAssetSessionID = temporaryAssetSessionID
        self.completedStepCount = completedStepCount
    }

    var hasContent: Bool { !steps.isEmpty }

    func remainingSteps(startingAt index: Int) -> PastePlan? {
        guard steps.indices.contains(index) else { return nil }
        return PastePlan(
            id: id,
            steps: Array(steps[index...]),
            temporaryAssetSessionID: temporaryAssetSessionID,
            completedStepCount: completedStepCount + index
        )
    }
}

struct PasteboardPayloadPreparation: Equatable, Sendable {
    let payload: PastePayload
    let temporaryAssetSessionID: UUID?
}

enum PastePreparationError: LocalizedError, Equatable {
    case emptySelection
    case unavailableContent
    case imageExportFailed

    var errorDescription: String? {
        switch self {
        case .emptySelection:
            String(localized: "No clipboard item is selected.")
        case .unavailableContent:
            String(localized: "The selected clipboard content is no longer available.")
        case .imageExportFailed:
            String(localized: "Buffer could not prepare one or more images for pasting.")
        }
    }
}

protocol ClipboardPasteContentReading: Sendable {
    func pasteText(for item: ClipboardItem) async -> String?
    func pasteImageData(for item: ClipboardItem) async -> Data?
}

protocol PasteTemporaryAssetExporting: Sendable {
    func saveImageDataToTemp(_ data: Data, sessionID: UUID, fileName: String) async -> URL?
    func removePasteSession(_ sessionID: UUID) async
    func removeStalePasteSessions() async
}

actor PastePayloadBuilder {
    private let contentReader: any ClipboardPasteContentReading
    private let imageExporter: any PasteTemporaryAssetExporting

    init(
        contentReader: any ClipboardPasteContentReading,
        imageExporter: any PasteTemporaryAssetExporting
    ) {
        self.contentReader = contentReader
        self.imageExporter = imageExporter
    }

    func prepareCopyPayload(for items: [ClipboardItem]) async throws -> PasteboardPayloadPreparation {
        guard !items.isEmpty else { throw PastePreparationError.emptySelection }
        guard items.count > 1 else {
            return PasteboardPayloadPreparation(
                payload: try await copyPayload(for: items[0]),
                temporaryAssetSessionID: nil
            )
        }

        var textItems: [String] = []
        for item in items {
            if let text = await contentReader.pasteText(for: item) {
                textItems.append(text)
            }
        }
        if !textItems.isEmpty {
            return PasteboardPayloadPreparation(
                payload: .string(textItems.joined(separator: "\n")),
                temporaryAssetSessionID: nil
            )
        }

        let sessionID = UUID()
        do {
            return PasteboardPayloadPreparation(
                payload: .fileURLs(try await imageFileURLs(for: items, sessionID: sessionID)),
                temporaryAssetSessionID: sessionID
            )
        } catch {
            await imageExporter.removePasteSession(sessionID)
            throw error
        }
    }

    private func copyPayload(for item: ClipboardItem) async throws -> PastePayload {
        if let text = await contentReader.pasteText(for: item) {
            return .string(text)
        }

        guard ClipboardItemTypeRegistry.supportsImageAssets(for: item),
            let imageData = await contentReader.pasteImageData(for: item),
            let tiffData = PasteImageDataEncoder.tiffData(from: imageData)
        else {
            throw PastePreparationError.unavailableContent
        }

        return .tiff(tiffData)
    }

    func makePastePlan(for items: [ClipboardItem]) async throws -> PastePlan {
        guard !items.isEmpty else { throw PastePreparationError.emptySelection }

        if items.count == 1 {
            return try await singleItemPlan(for: items[0])
        }

        var textItems: [String] = []
        for item in items {
            if let text = await contentReader.pasteText(for: item) {
                textItems.append(text)
            }
        }
        let text = textItems.joined(separator: "\n")
        let imageItems = items.filter { ClipboardItemTypeRegistry.supportsImageAssets(for: $0) }
        let sessionID = imageItems.isEmpty ? nil : UUID()

        var steps: [PasteStep] = []
        if !text.isEmpty {
            steps.append(PasteStep(payload: .string(text), delayBeforeExecution: 0))
        }

        if let sessionID {
            do {
                let urls = try await imageFileURLs(for: imageItems, sessionID: sessionID)
                steps.append(
                    PasteStep(
                        payload: .fileURLs(urls),
                        delayBeforeExecution: steps.isEmpty ? 0 : 0.4
                    )
                )
            } catch {
                await imageExporter.removePasteSession(sessionID)
                throw error
            }
        }

        guard !steps.isEmpty else { throw PastePreparationError.unavailableContent }
        return PastePlan(id: UUID(), steps: steps, temporaryAssetSessionID: sessionID)
    }

    private func singleItemPlan(for item: ClipboardItem) async throws -> PastePlan {
        if let text = await contentReader.pasteText(for: item) {
            return PastePlan(
                id: UUID(),
                steps: [PasteStep(payload: .string(text), delayBeforeExecution: 0)],
                temporaryAssetSessionID: nil
            )
        }

        guard ClipboardItemTypeRegistry.supportsImageAssets(for: item),
            let imageData = await contentReader.pasteImageData(for: item)
        else {
            throw PastePreparationError.unavailableContent
        }

        let sessionID = UUID()
        if let fileURL = await imageExporter.saveImageDataToTemp(
            imageData,
            sessionID: sessionID,
            fileName: "image-0001.png"
        ) {
            return PastePlan(
                id: UUID(),
                steps: [PasteStep(payload: .fileURLs([fileURL]), delayBeforeExecution: 0)],
                temporaryAssetSessionID: sessionID
            )
        }

        await imageExporter.removePasteSession(sessionID)
        guard let tiffData = PasteImageDataEncoder.tiffData(from: imageData) else {
            throw PastePreparationError.imageExportFailed
        }
        return PastePlan(
            id: UUID(),
            steps: [PasteStep(payload: .tiff(tiffData), delayBeforeExecution: 0)],
            temporaryAssetSessionID: nil
        )
    }

    private func imageFileURLs(for items: [ClipboardItem], sessionID: UUID) async throws -> [URL] {
        var urls: [URL] = []
        urls.reserveCapacity(items.count)

        for (index, item) in items.enumerated() {
            guard let imageData = await contentReader.pasteImageData(for: item) else {
                throw PastePreparationError.unavailableContent
            }
            let paddedNumber = String(format: "%04d", index + 1)
            guard
                let url = await imageExporter.saveImageDataToTemp(
                    imageData,
                    sessionID: sessionID,
                    fileName: "image-\(paddedNumber).png"
                )
            else {
                throw PastePreparationError.imageExportFailed
            }
            urls.append(url)
        }

        return urls
    }
}
