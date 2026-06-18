import Foundation
import Vision
import UIKit
import Photos

public class VisionAnalysisService {
    public static let shared = VisionAnalysisService()
    
    private init() {}
    
    /// Analyzes a photo asset to calculate both Apple's aesthetic scores and scene classification tags.
    /// - Parameters:
    ///   - asset: The PhotoAsset model to analyze.
    ///   - libraryService: Reference to the PhotoLibraryService to fetch the image bytes.
    ///   - completion: Callback with the fully populated PhotoAsset.
    public func analyzeAsset(_ asset: PhotoAsset, libraryService: PhotoLibraryService, completion: @escaping (PhotoAsset) -> Void) {
        var updatedAsset = asset
        
        libraryService.fetchThumbnail(for: asset, size: CGSize(width: 512, height: 512)) { image in
            guard let image = image, let cgImage = image.cgImage else {
                completion(updatedAsset)
                return
            }
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            // 1. Aesthetics request
            let aestheticsRequest = VNCalculateImageAestheticsScoresRequest { request, error in
                if let error = error {
                    print("Aesthetics score request failed: \(error.localizedDescription)")
                    return
                }
                
                if let results = request.results as? [VNImageAestheticsScoresObservation], let first = results.first {
                    updatedAsset.aestheticScore = first.overallScore
                    updatedAsset.isUtility = first.isUtility
                    updatedAsset.isAestheticAnalyzed = true
                }
            }
            
            // 2. Scene classification request
            let classificationRequest = VNClassifyImageRequest { request, error in
                if let error = error {
                    print("Classification request failed: \(error.localizedDescription)")
                    return
                }
                
                if let results = request.results as? [VNClassificationObservation] {
                    let tags = results
                        .filter { $0.confidence >= 0.10 }
                        .map { observation -> VisionTag in
                            let cleanName = observation.identifier
                                .split(separator: ",")
                                .first?
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .capitalized ?? observation.identifier.capitalized
                            return VisionTag(name: cleanName, confidence: observation.confidence)
                        }
                    
                    updatedAsset.tags = Array(tags.sorted().prefix(6))
                    updatedAsset.isClassified = true
                }
            }
            
            // Execute both requests on a background utility queue
            DispatchQueue.global(qos: .utility).async {
                do {
                    try handler.perform([aestheticsRequest, classificationRequest])
                    DispatchQueue.main.async {
                        completion(updatedAsset)
                    }
                } catch {
                    print("Failed to run Vision analysis on asset: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        completion(updatedAsset)
                    }
                }
            }
        }
    }
}
