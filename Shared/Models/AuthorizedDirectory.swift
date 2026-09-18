import Foundation

nonisolated struct AuthorizedDirectory: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let path: String
    let bookmark: Data
    let isAvailable: Bool

    init(
        id: UUID = UUID(),
        path: String,
        bookmark: Data,
        isAvailable: Bool = true
    ) {
        self.id = id
        self.path = path
        self.bookmark = bookmark
        self.isAvailable = isAvailable
    }

    var url: URL {
        URL(fileURLWithPath: path, isDirectory: true)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case path
        case bookmark
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        path = try container.decode(String.self, forKey: .path)
        bookmark = try container.decode(Data.self, forKey: .bookmark)
        isAvailable = true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(path, forKey: .path)
        try container.encode(bookmark, forKey: .bookmark)
    }
}
