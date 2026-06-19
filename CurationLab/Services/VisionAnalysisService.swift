import Foundation
import Vision
import UIKit
import Photos

public class VisionAnalysisService {
    public static let shared = VisionAnalysisService()
    
    private init() {}
    
    /// Analyzes a photo asset using multiple on-device Apple Vision tools.
    /// Run on a background thread, cached, and returned via callback.
    /// - Parameters:
    ///   - asset: The PhotoAsset model to analyze.
    ///   - libraryService: Reference to the PhotoLibraryService to fetch and cache the image.
    ///   - completion: Callback with the fully analyzed PhotoAsset.
    public func analyzeAsset(_ asset: PhotoAsset, libraryService: PhotoLibraryService, completion: @escaping (PhotoAsset) -> Void) {
        // Return cached immediately if already fully analyzed
        if asset.isFullyAnalyzed {
            completion(asset)
            return
        }
        
        var updatedAsset = asset
        
        // Fetch a single high-quality thumbnail (width: 512) to avoid multiple opportunistic callbacks
        libraryService.fetchSingleThumbnail(for: asset, size: CGSize(width: 512, height: 512)) { image in
            guard let image = image, let cgImage = image.cgImage else {
                completion(updatedAsset)
                return
            }
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            // 1. Aesthetics quality evaluation request
            let aestheticsRequest = VNCalculateImageAestheticsScoresRequest { request, error in
                if let error = error {
                    print("Aesthetics request failed: \(error.localizedDescription)")
                    return
                }
                if let results = request.results as? [VNImageAestheticsScoresObservation], let first = results.first {
                    updatedAsset.aestheticScore = first.overallScore
                    updatedAsset.isUtility = first.isUtility
                    updatedAsset.isAestheticAnalyzed = true
                }
            }
            
            // 2. Scene classification labels request
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
                    updatedAsset.tags = Array(tags.sorted().prefix(8))
                    updatedAsset.isClassified = true
                }
            }
            
            // 3. Face detection request
            let faceRequest = VNDetectFaceRectanglesRequest { request, error in
                if let error = error {
                    print("Face detection failed: \(error.localizedDescription)")
                    return
                }
                if let results = request.results as? [VNFaceObservation] {
                    updatedAsset.faceCount = results.count
                }
            }
            
            // 4. Human figure detection request
            let humanRequest = VNDetectHumanRectanglesRequest { request, error in
                if let error = error {
                    print("Human detection failed: \(error.localizedDescription)")
                    return
                }
                if let results = request.results as? [VNHumanObservation] {
                    updatedAsset.humanCount = results.count
                }
            }
            
            // 5. OCR Text recognition request
            let textRequest = VNRecognizeTextRequest { request, error in
                if let error = error {
                    print("Text recognition failed: \(error.localizedDescription)")
                    return
                }
                if let results = request.results as? [VNRecognizedTextObservation] {
                    let recognized = results.compactMap { observation -> String? in
                        observation.topCandidates(1).first?.string
                    }
                    updatedAsset.recognizedText = recognized
                }
            }
            textRequest.recognitionLevel = .accurate
            
            // Execute all requests concurrently on a utility thread
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([
                        aestheticsRequest,
                        classificationRequest,
                        faceRequest,
                        humanRequest,
                        textRequest
                    ])
                    
                    updatedAsset.isFullyAnalyzed = true
                    
                    // Save to the cache in PhotoLibraryService
                    libraryService.cacheAnalyzedAsset(updatedAsset)
                    
                    DispatchQueue.main.async {
                        completion(updatedAsset)
                    }
                } catch {
                    print("Failed to run Vision analysis batch on asset: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        completion(updatedAsset)
                    }
                }
            }
        }
    }
}
