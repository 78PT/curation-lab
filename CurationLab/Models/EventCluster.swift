import Foundation

public struct EventCluster: Identifiable, Hashable {
    public let id: UUID
    public var assets: [PhotoAsset]
    public var name: String
    public var locationName: String
    
    // Gemini curation results
    public var geminiSelectedIds: [String] = []
    public var geminiReasoning: String? = nil
    public var isGeminiCuring: Bool = false
    
    public var startDate: Date {
        assets.compactMap { $0.creationDate }.min() ?? Date()
    }
    
    public var endDate: Date {
        assets.compactMap { $0.creationDate }.max() ?? Date()
    }
    
    public init(id: UUID = UUID(), assets: [PhotoAsset], name: String, locationName: String = "Unknown Location") {
        self.id = id
        self.assets = assets
        self.name = name
        self.locationName = locationName
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: EventCluster, rhs: EventCluster) -> Bool {
        lhs.id == rhs.id
    }
    
    /// Returns the top assets sorted by Apple's aesthetic score, excluding utility images.
    public func appleTopAssets(limit: Int = 3) -> [PhotoAsset] {
        let sorted = assets
            .filter { !$0.isUtility }
            .sorted { $0.aestheticScore > $1.aestheticScore }
        return Array(sorted.prefix(limit))
    }
}
