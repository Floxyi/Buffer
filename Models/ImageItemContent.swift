import Foundation

struct ImageItemContent: Codable, Equatable, Sendable {
    let filename: String
    let ocrText: String?

    init(filename: String, ocrText: String? = nil) {
        self.filename = filename
        self.ocrText = ocrText
    }

    func updatingOCRText(_ text: String) -> ImageItemContent {
        ImageItemContent(filename: filename, ocrText: text)
    }
}
