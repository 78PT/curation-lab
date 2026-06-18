import Foundation
import Photos
import UIKit
import ImageIO
import CoreLocation

public class PhotoLibraryService: ObservableObject {
    @Published public var permissionStatus: PHAuthorizationStatus = .notDetermined
    @Published public var rawAssets: [PhotoAsset] = []
    @Published public var eventClusters: [EventCluster] = []
    @Published public var isLoading: Bool = false
    
    // Clustering configurations (adjustable via Settings)
    @Published public var timeGapHours: Double = 4.0
    @Published public var distanceGapMeters: Double = 1000.0 // 1 km
    
    private let imageManager = PHCachingImageManager()
    
    public init() {
        checkPermission()
    }
    
    public func checkPermission() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        DispatchQueue.main.async {
            self.permissionStatus = status
            if status == .authorized || status == .limited {
                self.fetchPhotosAndCluster()
            }
        }
    }
    
    public func requestPermission() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async {
                self.permissionStatus = status
                if status == .authorized || status == .limited {
                    self.fetchPhotosAndCluster()
                }
            }
        }
    }
    
    /// Fetches assets, extracts basic info, and clusters them.
    public func fetchPhotosAndCluster() {
        DispatchQueue.main.async {
            self.isLoading = true
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            fetchOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
            
            let fetchResult = PHAsset.fetchAssets(with: fetchOptions)
            var assets: [PhotoAsset] = []
            
            fetchResult.enumerateObjects { phAsset, _, _ in
                assets.append(PhotoAsset(phAsset: phAsset))
            }
            
            DispatchQueue.main.async {
                self.rawAssets = assets
                self.rebuildClusters()
            }
        }
    }
    
    /// Re-runs the event clustering algorithm based on current parameters.
    public func rebuildClusters() {
        guard !rawAssets.isEmpty else {
            DispatchQueue.main.async {
                self.eventClusters = []
                self.isLoading = false
            }
            return
        }
        
        let assets = self.rawAssets
        let timeGap = self.timeGapHours * 60 * 60
        let distanceGap = self.distanceGapMeters
        
        DispatchQueue.global(qos: .userInteractive).async {
            // Sort assets ascending by date for chronological group iteration
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
                        // Check distance proximity if both photos have GPS logs
                        if let currentLoc = asset.location, let lastLoc = lastAsset.location {
                            let distance = currentLoc.distance(from: lastLoc)
                            if distance <= distanceGap {
                                shouldGroup = true
                            }
                        } else {
                            // If either lacks GPS, fall back to time clustering only
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
            
            // Sort clusters chronologically descending (newest events first)
            let finalClusters = clusters.sorted { $0.startDate > $1.startDate }
            
            DispatchQueue.main.async {
                self.eventClusters = finalClusters
                self.isLoading = false
            }
        }
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
            // Use reverse geocoder in real apps, but coordinates are solid for a tester
            let lat = locations.first!.coordinate.latitude
            let lon = locations.first!.coordinate.longitude
            locationText = String(format: "📍 Lat: %.3f, Lon: %.3f", lat, lon)
        }
        
        let name = "Event on \(dateString)"
        return EventCluster(assets: assets, name: name, locationName: locationText)
    }
    
    /// Requests thumbnail image for grid display.
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
    
    /// Asynchronously extracts comprehensive EXIF parameters from the asset's binary data.
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
            
            // Format size
            let bytes = Double(data.count)
            exif["File Size"] = bytes > 1024 * 1024 ? String(format: "%.2f MB", bytes / (1024 * 1024)) : String(format: "%.1f KB", bytes / 1024)
            exif["Dimensions"] = "\(asset.width) × \(asset.height)"
            
            // Camera
            if let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
                if let make = tiff[kCGImagePropertyTIFFMake] as? String { exif["Manufacturer"] = make }
                if let model = tiff[kCGImagePropertyTIFFModel] as? String { exif["Camera Model"] = model }
            }
            
            // Exposure specs
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
            
            // GPS coords
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
