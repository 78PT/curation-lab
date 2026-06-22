import Foundation
import Photos
import UIKit
import ImageIO
import CoreLocation

public class PhotoLibraryService: ObservableObject {
    @Published public var permissionStatus: PHAuthorizationStatus = .notDetermined
    @Published public var loadedAssets: [PhotoAsset] = []
    @Published public var eventClusters: [EventCluster] = []
    @Published public var isLoading: Bool = false
    
    @Published public var albums: [PhotoAlbum] = []
    @Published public var selectedAlbumId: String? = nil {
        didSet {
            // Re-initialize fetch result when the user switches albums
            initializeFetchResult()
        }
    }
    
    // Clustering configurations (retained for backward compatibility)
    @Published public var timeGapHours: Double = 4.0
    @Published public var distanceGapMeters: Double = 1000.0
    
    // Internal cache of analyzed PhotoAssets to avoid re-running Vision/EXIF extraction
    private var analysisCache: [String: PhotoAsset] = [:]
    
    // Persistent LLM Cache
    private var persistentLLMRecords: [String: LLMAnalysisRecord] = [:]
    
    // PHFetchResult storing reference to all device photos lazily
    private var allPHAssets: PHFetchResult<PHAsset>? = nil
    private let imageManager = PHCachingImageManager()
    
    public init() {
        loadPersistentLLMRecords()
        checkPermission()
    }
    
    private func loadPersistentLLMRecords() {
        if let data = UserDefaults.standard.data(forKey: "llm_analysis_cache"),
           let decoded = try? JSONDecoder().decode([String: LLMAnalysisRecord].self, from: data) {
            self.persistentLLMRecords = decoded
        }
    }
    
    public func checkPermission() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        DispatchQueue.main.async {
            self.permissionStatus = status
            if status == .authorized || status == .limited {
                self.initializeFetchResult()
                self.fetchAlbums()
            }
        }
    }
    
    public func requestPermission() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async {
                self.permissionStatus = status
                if status == .authorized || status == .limited {
                    self.initializeFetchResult()
                    self.fetchAlbums()
                }
            }
        }
    }
    
    public func fetchAlbums() {
        DispatchQueue.global(qos: .userInitiated).async {
            var loadedAlbums: [PhotoAlbum] = []
            
            // 1. Fetch iCloud Shared Albums
            let sharedResult = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumCloudShared, options: nil)
            sharedResult.enumerateObjects { collection, _, _ in
                let fetchOptions = PHFetchOptions()
                fetchOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
                let assetCount = PHAsset.fetchAssets(in: collection, options: fetchOptions).count
                if assetCount > 0 {
                    loadedAlbums.append(PhotoAlbum(
                        localIdentifier: collection.localIdentifier,
                        title: collection.localizedTitle ?? "Shared Album",
                        count: assetCount,
                        isShared: true
                    ))
                }
            }
            
            // 2. Fetch Regular User Albums
            let regularResult = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
            regularResult.enumerateObjects { collection, _, _ in
                let fetchOptions = PHFetchOptions()
                fetchOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
                let assetCount = PHAsset.fetchAssets(in: collection, options: fetchOptions).count
                if assetCount > 0 {
                    loadedAlbums.append(PhotoAlbum(
                        localIdentifier: collection.localIdentifier,
                        title: collection.localizedTitle ?? "Album",
                        count: assetCount,
                        isShared: false
                    ))
                }
            }
            
            DispatchQueue.main.async {
                self.albums = loadedAlbums
            }
        }
    }
    
    /// Initializes the PHFetchResult lazily and loads the first batch of photos.
    public func initializeFetchResult() {
        DispatchQueue.main.async {
            self.isLoading = true
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            fetchOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
            
            let fetchResult: PHFetchResult<PHAsset>
            if let albumId = self.selectedAlbumId,
               let collection = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumId], options: nil).firstObject {
                fetchResult = PHAsset.fetchAssets(in: collection, options: fetchOptions)
            } else {
                fetchResult = PHAsset.fetchAssets(with: fetchOptions)
            }
            
            DispatchQueue.main.async {
                self.allPHAssets = fetchResult
                self.loadedAssets = []
                self.loadNextBatch(limit: 80)
            }
        }
    }
    
    /// Loads the next batch of assets lazily, integrating cached vision analysis if available.
    public func loadNextBatch(limit: Int = 80) {
        guard let fetchResult = allPHAssets else {
            self.isLoading = false
            return
        }
        
        let currentCount = loadedAssets.count
        guard currentCount < fetchResult.count else {
            self.isLoading = false
            return
        }
        
        self.isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let startIndex = currentCount
            let endIndex = min(startIndex + limit, fetchResult.count)
            var newAssets: [PhotoAsset] = []
            
            for index in startIndex..<endIndex {
                let phAsset = fetchResult.object(at: index)
                var asset = PhotoAsset(phAsset: phAsset)
                
                // Inject cached analysis results if we already computed them in this session
                if let cached = self.analysisCache[phAsset.localIdentifier] {
                    asset.aestheticScore = cached.aestheticScore
                    asset.isUtility = cached.isUtility
                    asset.tags = cached.tags
                    asset.isClassified = cached.isClassified
                    asset.isAestheticAnalyzed = cached.isAestheticAnalyzed
                    asset.exifMetadata = cached.exifMetadata
                    asset.llmTags = cached.llmTags
                    asset.llmDescription = cached.llmDescription
                    asset.isLlmAnalyzed = cached.isLlmAnalyzed
                } else {
                    // Check persistent cache
                    if let record = self.persistentLLMRecords[phAsset.localIdentifier] {
                        asset.llmTags = record.tags
                        asset.llmDescription = record.description
                        asset.isLlmAnalyzed = true
                    }
                }
                newAssets.append(asset)
            }
            
            DispatchQueue.main.async {
                self.loadedAssets.append(contentsOf: newAssets)
                self.isLoading = false
                
                // For backward compatibility, trigger a lazy rebuild of event clusters if needed
                self.rebuildClustersLazy()
            }
        }
    }
    
    /// Caches an asset that has undergone Vision analysis and updates it in the loadedAssets list.
    public func cacheAnalyzedAsset(_ asset: PhotoAsset) {
        DispatchQueue.main.async {
            self.analysisCache[asset.localIdentifier] = asset
            if asset.isLlmAnalyzed {
                let record = LLMAnalysisRecord(tags: asset.llmTags, description: asset.llmDescription)
                self.persistentLLMRecords[asset.localIdentifier] = record
                
                // Save to UserDefaults
                if let data = try? JSONEncoder().encode(self.persistentLLMRecords) {
                    UserDefaults.standard.set(data, forKey: "llm_analysis_cache")
                }
            }
            if let index = self.loadedAssets.firstIndex(where: { $0.localIdentifier == asset.localIdentifier }) {
                self.loadedAssets[index] = asset
            }
        }
    }
    
    public func saveLLMAnalysis(for assetId: String, tags: [String], description: String) {
        DispatchQueue.main.async {
            let record = LLMAnalysisRecord(tags: tags, description: description)
            self.persistentLLMRecords[assetId] = record
            
            // Save to UserDefaults
            if let data = try? JSONEncoder().encode(self.persistentLLMRecords) {
                UserDefaults.standard.set(data, forKey: "llm_analysis_cache")
            }
            
            // Update in loadedAssets if present
            if let index = self.loadedAssets.firstIndex(where: { $0.localIdentifier == assetId }) {
                var asset = self.loadedAssets[index]
                asset.llmTags = tags
                asset.llmDescription = description
                asset.isLlmAnalyzed = true
                self.loadedAssets[index] = asset
                self.analysisCache[assetId] = asset
            } else if var cached = self.analysisCache[assetId] {
                cached.llmTags = tags
                cached.llmDescription = description
                cached.isLlmAnalyzed = true
                self.analysisCache[assetId] = cached
            }
        }
    }
    
    public func clearLLMAnalysis(for assetId: String) {
        DispatchQueue.main.async {
            self.persistentLLMRecords.removeValue(forKey: assetId)
            
            // Save to UserDefaults
            if let data = try? JSONEncoder().encode(self.persistentLLMRecords) {
                UserDefaults.standard.set(data, forKey: "llm_analysis_cache")
            }
            
            // Update in loadedAssets if present
            if let index = self.loadedAssets.firstIndex(where: { $0.localIdentifier == assetId }) {
                var asset = self.loadedAssets[index]
                asset.llmTags = []
                asset.llmDescription = ""
                asset.isLlmAnalyzed = false
                self.loadedAssets[index] = asset
                self.analysisCache[assetId] = asset
            } else if var cached = self.analysisCache[assetId] {
                cached.llmTags = []
                cached.llmDescription = ""
                cached.isLlmAnalyzed = false
                self.analysisCache[assetId] = cached
            }
        }
    }
    
    /// Forces re-fetching all photos (e.g. from developer options)
    public func fetchPhotosAndCluster() {
        initializeFetchResult()
    }
    
    /// Re-runs the event clustering algorithm based on current parameters lazily.
    public func rebuildClustersLazy() {
        guard !loadedAssets.isEmpty else {
            self.eventClusters = []
            return
        }
        
        let assets = self.loadedAssets
        let timeGap = self.timeGapHours * 60 * 60
        let distanceGap = self.distanceGapMeters
        
        DispatchQueue.global(qos: .utility).async {
            let sortedAssets = assets.sorted { (lhs, rhs) -> Bool in
                guard let lDate = lhs.creationDate else { return false }
                guard let rDate = rhs.creationDate else { return true }
                return lDate < rDate
            }
            
            var clusters: [EventCluster] = []
            var currentGroup: [PhotoAsset] = []
            
            for asset in sortedAssets {
                if currentGroup.isEmpty {
                    currentGroup.append(asset)
                    continue
                }
                
                let lastAsset = currentGroup.last!
                var shouldGroup = false
                
                if let currentDate = asset.creationDate, let lastDate = lastAsset.creationDate {
                    let timeDiff = currentDate.timeIntervalSince(lastDate)
                    if timeDiff <= timeGap {
                        if let currentLoc = asset.location, let lastLoc = lastAsset.location {
                            let distance = currentLoc.distance(from: lastLoc)
                            if distance <= distanceGap {
                                shouldGroup = true
                            }
                        } else {
                            shouldGroup = true
                        }
                    }
                }
                
                if shouldGroup {
                    currentGroup.append(asset)
                } else {
                    clusters.append(self.createCluster(from: currentGroup))
                    currentGroup = [asset]
                }
            }
            
            if !currentGroup.isEmpty {
                clusters.append(self.createCluster(from: currentGroup))
            }
            
            let finalClusters = clusters.sorted { $0.startDate > $1.startDate }
            
            DispatchQueue.main.async {
                self.eventClusters = finalClusters
            }
        }
    }
    
    public func rebuildClusters() {
        rebuildClustersLazy()
    }
    
    private func createCluster(from assets: [PhotoAsset]) -> EventCluster {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        
        let minDate = assets.compactMap { $0.creationDate }.min() ?? Date()
        let dateString = formatter.string(from: minDate)
        
        var locationText = "No Location Logs"
        let locations = assets.compactMap { $0.location }
        if !locations.isEmpty {
            let lat = locations.first!.coordinate.latitude
            let lon = locations.first!.coordinate.longitude
            locationText = String(format: "📍 Lat: %.3f, Lon: %.3f", lat, lon)
        }
        
        let name = "Event on \(dateString)"
        return EventCluster(assets: assets, name: name, locationName: locationText)
    }
    
    /// Requests thumbnail image for grid display (could deliver multiple times for performance).
    @discardableResult
    public func fetchThumbnail(for asset: PhotoAsset, size: CGSize, completion: @escaping (UIImage?) -> Void) -> PHImageRequestID {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        
        return imageManager.requestImage(
            for: asset.phAsset,
            targetSize: size,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            completion(image)
        }
    }
    
    /// Requests thumbnail image with high quality delivery (exactly one callback).
    @discardableResult
    public func fetchSingleThumbnail(for asset: PhotoAsset, size: CGSize, completion: @escaping (UIImage?) -> Void) -> PHImageRequestID {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        
        return imageManager.requestImage(
            for: asset.phAsset,
            targetSize: size,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            completion(image)
        }
    }
    
    /// Fetches high-quality image.
    public func fetchFullImage(for asset: PhotoAsset, completion: @escaping (UIImage?) -> Void) {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        
        imageManager.requestImage(
            for: asset.phAsset,
            targetSize: PHImageManagerMaximumSize,
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            completion(image)
        }
    }
    
    /// Asynchronously extracts EXIF parameters.
    public func fetchExifMetadata(for asset: PhotoAsset, completion: @escaping ([String: String]) -> Void) {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .fastFormat
        
        PHImageManager.default().requestImageDataAndOrientation(for: asset.phAsset, options: options) { data, _, _, _ in
            var exif: [String: String] = [:]
            guard let data = data,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
                completion([:])
                return
            }
            
            let bytes = Double(data.count)
            exif["File Size"] = bytes > 1024 * 1024 ? String(format: "%.2f MB", bytes / (1024 * 1024)) : String(format: "%.1f KB", bytes / 1024)
            exif["Dimensions"] = "\(asset.width) × \(asset.height)"
            
            if let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
                if let make = tiff[kCGImagePropertyTIFFMake] as? String { exif["Manufacturer"] = make }
                if let model = tiff[kCGImagePropertyTIFFModel] as? String { exif["Camera Model"] = model }
            }
            
            if let exifDict = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
                if let iso = exifDict[kCGImagePropertyExifISOSpeedRatings] as? [Int], let first = iso.first {
                    exif["ISO"] = "\(first)"
                }
                if let fNumber = exifDict[kCGImagePropertyExifFNumber] as? Double {
                    exif["Aperture"] = String(format: "f/%.1f", fNumber)
                }
                if let expTime = exifDict[kCGImagePropertyExifExposureTime] as? Double {
                    exif["Exposure Time"] = expTime < 1.0 ? "1/\(Int(round(1.0 / expTime)))s" : String(format: "%.1fs", expTime)
                }
                if let focal = exifDict[kCGImagePropertyExifFocalLength] as? Double {
                    exif["Focal Length"] = "\(Int(focal))mm"
                }
                if let lens = exifDict[kCGImagePropertyExifLensModel] as? String {
                    exif["Lens"] = lens
                }
            }
            
            if let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any] {
                if let lat = gps[kCGImagePropertyGPSLatitude] as? Double, let latRef = gps[kCGImagePropertyGPSLatitudeRef] as? String {
                    exif["Latitude"] = String(format: "%.4f° %@", lat, latRef)
                }
                if let lon = gps[kCGImagePropertyGPSLongitude] as? Double, let lonRef = gps[kCGImagePropertyGPSLongitudeRef] as? String {
                    exif["Longitude"] = String(format: "%.4f° %@", lon, lonRef)
                }
            }
            
            completion(exif)
        }
    }
}

public struct LLMAnalysisRecord: Codable {
    public let tags: [String]
    public let description: String
    
    public init(tags: [String], description: String) {
        self.tags = tags
        self.description = description
    }
}

public struct PhotoAlbum: Identifiable, Hashable {
    public var id: String { localIdentifier }
    public let localIdentifier: String
    public let title: String
    public let count: Int
    public let isShared: Bool
    
    public init(localIdentifier: String, title: String, count: Int, isShared: Bool) {
        self.localIdentifier = localIdentifier
        self.title = title
        self.count = count
        self.isShared = isShared
    }
}
