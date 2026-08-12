import AppKit

enum PastePayload: Equatable {
    case string(String)
    case fileURLs([URL])
    case tiff(Data)
}

struct PasteStep: Equatable {
    let payload: PastePayload
    let delayBeforeExecution: TimeInterval
}

struct PastePlan: Equatable {
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

struct PasteboardPayloadPreparation: Equatable {
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
            "No clipboard item is selected."
        case .unavailableContent:
            "The selected clipboard content is no longer available."
        case .imageExportFailed:
            "Buffer could not prepare one or more images for pasting."
        }
    }
}

@MainActor
protocol PasteImageExporting {
    func saveImageToTemp(_ image: NSImage, sessionID: UUID, fileName: String) -> URL?
    func removePasteSession(_ sessionID: UUID)
    func removeStalePasteSessions()
    func saveImageToDisk(_ image: NSImage)
}

@MainActor
struct PastePayloadBuilder {
    private let store: ClipboardStoreReading
    private let imageExporter: PasteImageExporting

    init(store: ClipboardStoreReading, imageExporter: PasteImageExporting) {
        self.store = store
        self.imageExporter = imageExporter
    }

    func prepareCopyPayload(for items: [ClipboardItem]) throws -> PasteboardPayloadPreparation {
        guard !items.isEmpty else { throw PastePreparationError.emptySelection }
        guard items.count > 1 else {
            return PasteboardPayloadPreparation(
                payload: try copyPayload(for: items[0]),
                temporaryAssetSessionID: nil
            )
        }

        let textItems = items.compactMap {
            ClipboardItemTypeRegistry.pastedText(for: $0, store: store)
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
                payload: .fileURLs(try imageFileURLs(for: items, sessionID: sessionID)),
                temporaryAssetSessionID: sessionID
            )
        } catch {
            imageExporter.removePasteSession(sessionID)
            throw error
        }
    }

    private func copyPayload(for item: ClipboardItem) throws -> PastePayload {
        if let text = ClipboardItemTypeRegistry.pastedText(for: item, store: store) {
            return .string(text)
        }

        guard ClipboardItemTypeRegistry.supportsImageAssets(for: item),
            let image = store.image(for: item),
            let tiffData = image.tiffRepresentation
        else {
            throw PastePreparationError.unavailableContent
        }

        return .tiff(tiffData)
    }

    func makePastePlan(for items: [ClipboardItem]) throws -> PastePlan {
        guard !items.isEmpty else { throw PastePreparationError.emptySelection }

        if items.count == 1 {
            return try singleItemPlan(for: items[0])
        }

        let text =
            items
            .compactMap { ClipboardItemTypeRegistry.pastedText(for: $0, store: store) }
            .joined(separator: "\n")
        let imageItems = items.filter { ClipboardItemTypeRegistry.supportsImageAssets(for: $0) }
        let sessionID = imageItems.isEmpty ? nil : UUID()

        var steps: [PasteStep] = []
        if !text.isEmpty {
            steps.append(PasteStep(payload: .string(text), delayBeforeExecution: 0))
        }

        if let sessionID {
            do {
                let urls = try imageFileURLs(for: imageItems, sessionID: sessionID)
                steps.append(
                    PasteStep(
                        payload: .fileURLs(urls),
                        delayBeforeExecution: steps.isEmpty ? 0 : 0.4
                    )
                )
            } catch {
                imageExporter.removePasteSession(sessionID)
                throw error
            }
        }

        guard !steps.isEmpty else { throw PastePreparationError.unavailableContent }
        return PastePlan(id: UUID(), steps: steps, temporaryAssetSessionID: sessionID)
    }

    private func singleItemPlan(for item: ClipboardItem) throws -> PastePlan {
        if let text = ClipboardItemTypeRegistry.pastedText(for: item, store: store) {
            return PastePlan(
                id: UUID(),
                steps: [PasteStep(payload: .string(text), delayBeforeExecution: 0)],
                temporaryAssetSessionID: nil
            )
        }

        guard ClipboardItemTypeRegistry.supportsImageAssets(for: item),
            let image = store.image(for: item)
        else {
            throw PastePreparationError.unavailableContent
        }

        let sessionID = UUID()
        if let fileURL = imageExporter.saveImageToTemp(
            image,
            sessionID: sessionID,
            fileName: "image-0001.png"
        ) {
            return PastePlan(
                id: UUID(),
                steps: [PasteStep(payload: .fileURLs([fileURL]), delayBeforeExecution: 0)],
                temporaryAssetSessionID: sessionID
            )
        }

        imageExporter.removePasteSession(sessionID)
        guard let tiffData = image.tiffRepresentation else {
            throw PastePreparationError.imageExportFailed
        }
        return PastePlan(
            id: UUID(),
            steps: [PasteStep(payload: .tiff(tiffData), delayBeforeExecution: 0)],
            temporaryAssetSessionID: nil
        )
    }

    private func imageFileURLs(for items: [ClipboardItem], sessionID: UUID) throws -> [URL] {
        var urls: [URL] = []
        urls.reserveCapacity(items.count)

        for (index, item) in items.enumerated() {
            guard let image = store.image(for: item) else {
                throw PastePreparationError.unavailableContent
            }
            let paddedNumber = String(format: "%04d", index + 1)
            guard
                let url = imageExporter.saveImageToTemp(
                    image,
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
