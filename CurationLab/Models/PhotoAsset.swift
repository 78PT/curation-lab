import Foundation
import Photos
import CoreLocation

public struct VisionTag: Identifiable, Hashable, Comparable {
    public var id: String { name }
    public let name: String
    public let confidence: Float
    
    public static func < (lhs: VisionTag, rhs: VisionTag) -> Bool {
        lhs.confidence > rhs.confidence // Sort descending by confidence
    }
}

public struct PhotoAsset: Identifiable, Hashable {
    public var id: String { localIdentifier }
    public let localIdentifier: String
    public let phAsset: PHAsset
    public let creationDate: Date?
    public let location: CLLocation?
    public let isFavorite: Bool
    
    public var isUtility: Bool = false
    public var aestheticScore: Float = 0.0
    public var tags: [VisionTag] = []
    
    public var isClassified: Bool = false
    public var isAestheticAnalyzed: Bool = false
    public var exifMetadata: [String: String] = [:]
    
    // Additional Apple Vision properties
    public var faceCount: Int = 0
    public var humanCount: Int = 0
    public var recognizedText: [String] = []
    public var isFullyAnalyzed: Bool = false
    
    public var width: Int {
        phAsset.pixelWidth
    }
    
    public var height: Int {
        phAsset.pixelHeight
    }
    
    public init(phAsset: PHAsset) {
        self.localIdentifier = phAsset.localIdentifier
        self.phAsset = phAsset
        self.creationDate = phAsset.creationDate
        self.location = phAsset.location
        self.isFavorite = phAsset.isFavorite
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(localIdentifier)
    }
    
    public static func == (lhs: PhotoAsset, rhs: PhotoAsset) -> Bool {
        lhs.localIdentifier == rhs.localIdentifier
    }
}
