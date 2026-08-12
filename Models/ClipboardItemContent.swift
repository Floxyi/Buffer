import Foundation

enum ClipboardItemContent: Codable, Equatable, Sendable {
    case text(TextItemContent)
    case image(ImageItemContent)
    case color(ColorItemContent)
    case link(LinkItemContent)
    case email(EmailItemContent)

    enum CodingKeys: String, CodingKey {
        case kind, text, image, color, link, email
    }

    var kind: ClipboardItemKind {
        switch self {
        case .text:
            return .text
        case .image:
            return .image
        case .color:
            return .color
        case .link:
            return .link
        case .email:
            return .email
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(ClipboardItemKind.self, forKey: .kind)

        switch kind {
        case .text:
            self = .text(try container.decode(TextItemContent.self, forKey: .text))
        case .image:
            self = .image(try container.decode(ImageItemContent.self, forKey: .image))
        case .color:
            self = .color(try container.decode(ColorItemContent.self, forKey: .color))
        case .link:
            self = .link(try container.decode(LinkItemContent.self, forKey: .link))
        case .email:
            self = .email(try container.decode(EmailItemContent.self, forKey: .email))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)

        switch self {
        case .text(let payload):
            try container.encode(payload, forKey: .text)
        case .image(let payload):
            try container.encode(payload, forKey: .image)
        case .color(let payload):
            try container.encode(payload, forKey: .color)
        case .link(let payload):
            try container.encode(payload, forKey: .link)
        case .email(let payload):
            try container.encode(payload, forKey: .email)
        }
    }
}
