import Foundation
import UIKit
import Photos

public enum ModelProvider: String, CaseIterable, Identifiable {
    case gemini = "Gemini 2.5 Flash"
    case groq = "Groq Llama 3.2 Vision"
    
    public var id: String { self.rawValue }
}

public class LLMService {
    public static let shared = LLMService()
    
    private init() {}
    
    /// Sends selected photos and a custom prompt to either Gemini or Groq.
    /// - Parameters:
    ///   - provider: The LLM model provider (Gemini or Groq).
    ///   - apiKey: User's API key.
    ///   - prompt: The custom text instruction.
    ///   - assets: The list of photo assets selected.
    ///   - libraryService: PhotoLibraryService reference to load image binaries.
    ///   - completion: Callback returning the model's text response.
    public func runPrompt(
        provider: ModelProvider,
        apiKey: String,
        prompt: String,
        assets: [PhotoAsset],
        libraryService: PhotoLibraryService,
        completion: @escaping (String) -> Void
    ) {
        guard !apiKey.isEmpty else {
            completion("Error: API key is missing. Set it in Settings.")
            return
        }
        
        // 1. Gather EXIF descriptions of selected assets to add to prompt context
        var metadataContext = "\n\n[Selected Photo Metadata Context]:\n"
        for (index, asset) in assets.enumerated() {
            let latLon = asset.location != nil ? "lat: \(asset.location!.coordinate.latitude), lon: \(asset.location!.coordinate.longitude)" : "no GPS"
            let tagsList = asset.tags.map { "\($0.name) (\(Int($0.confidence * 100))%)" }.joined(separator: ", ")
            
            metadataContext += """
            Image #\(index + 1) (ID: \(asset.localIdentifier))
              Dimensions: \(asset.width)x\(asset.height)
              Date: \(asset.creationDate?.description ?? "unknown")
              Location: \(latLon)
              Camera: \(asset.exifMetadata.description)
              Apple Aesthetic Score: \(String(format: "%.3f", asset.aestheticScore))
              On-Device Scene Tags: [\(tagsList)]
            
            """
        }
        
        let fullPrompt = prompt + metadataContext
        
        // 2. Fetch resized base64 images
        let group = DispatchGroup()
        var base64Images: [String] = []
        
        // Sort assets by date to keep order chronological
        let sortedAssets = assets.sorted { (a, b) -> Bool in
            guard let ad = a.creationDate, let bd = b.creationDate else { return true }
            return ad < bd
        }
        
        for asset in sortedAssets {
            group.enter()
            // We fetch a 400x400 size to keep payloads small, avoiding rate limits/timeouts on free tiers
            libraryService.fetchThumbnail(for: asset, size: CGSize(width: 400, height: 400)) { image in
                defer { group.leave() }
                guard let image = image,
                      let jpegData = image.jpegData(compressionQuality: 0.5) else {
                    return
                }
                base64Images.append(jpegData.base64EncodedString())
            }
        }
        
        group.notify(queue: .global(qos: .userInitiated)) {
            switch provider {
            case .gemini:
                self.sendToGemini(apiKey: apiKey, prompt: fullPrompt, images: base64Images, completion: completion)
            case .groq:
                self.sendToGroq(apiKey: apiKey, prompt: fullPrompt, images: base64Images, completion: completion)
            }
        }
    }
    
    // MARK: - Gemini API Call
    private func sendToGemini(apiKey: String, prompt: String, images: [String], completion: @escaping (String) -> Void) {
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            completion("Error: Invalid Gemini API URL.")
            return
        }
        
        var parts: [[String: Any]] = []
        
        // Add images first
        for base64 in images {
            parts.append([
                "inlineData": [
                    "mimeType": "image/jpeg",
                    "data": base64
                ]
            ])
        }
        
        // Add text prompt
        parts.append(["text": prompt])
        
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": parts
                ]
            ]
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])
        } catch {
            completion("Error: Failed to serialize request JSON.")
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion("Network Error: \(error.localizedDescription)") }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async { completion("Error: Empty response from Gemini.") }
                return
            }
            
            do {
                if let rawJSON = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let candidates = rawJSON["candidates"] as? [[String: Any]],
                   let firstCandidate = candidates.first,
                   let content = firstCandidate["content"] as? [String: Any],
                   let candidateParts = content["parts"] as? [[String: Any]],
                   let firstPart = candidateParts.first,
                   let textResponse = firstPart["text"] as? String {
                    
                    DispatchQueue.main.async {
                        completion(textResponse)
                    }
                } else {
                    let rawResponse = String(data: data, encoding: .utf8) ?? "Unreadable"
                    DispatchQueue.main.async {
                        completion("Failed to parse Gemini structure.\n\nResponse:\n\(rawResponse)")
                    }
                }
            } catch {
                let rawResponse = String(data: data, encoding: .utf8) ?? "Unreadable"
                DispatchQueue.main.async {
                    completion("JSON Decode Error: \(error.localizedDescription).\n\nResponse:\n\(rawResponse)")
                }
            }
        }.resume()
    }
    
    // MARK: - Groq API Call (OpenAI Chat Completions Schema)
    private func sendToGroq(apiKey: String, prompt: String, images: [String], completion: @escaping (String) -> Void) {
        let urlString = "https://api.groq.com/openai/v1/chat/completions"
        guard let url = URL(string: urlString) else {
            completion("Error: Invalid Groq API URL.")
            return
        }
        
        var contentArray: [[String: Any]] = []
        
        // Add prompt text
        contentArray.append([
            "type": "text",
            "text": prompt
        ])
        
        // Add images in OpenAI Vision format
        for base64 in images {
            contentArray.append([
                "type": "image_url",
                "image_url": [
                    "url": "data:image/jpeg;base64,\(base64)"
                ]
            ])
        }
        
        let requestBody: [String: Any] = [
            "model": "llama-3.2-11b-vision-preview",
            "messages": [
                [
                    "role": "user",
                    "content": contentArray
                ]
            ]
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody, options: [])
        } catch {
            completion("Error: Failed to serialize request JSON.")
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { completion("Network Error: \(error.localizedDescription)") }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async { completion("Error: Empty response from Groq.") }
                return
            }
            
            do {
                if let rawJSON = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let choices = rawJSON["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let message = firstChoice["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    
                    DispatchQueue.main.async {
                        completion(content)
                    }
                } else {
                    let rawResponse = String(data: data, encoding: .utf8) ?? "Unreadable"
                    DispatchQueue.main.async {
                        completion("Failed to parse Groq response structure.\n\nResponse:\n\(rawResponse)")
                    }
                }
            } catch {
                let rawResponse = String(data: data, encoding: .utf8) ?? "Unreadable"
                DispatchQueue.main.async {
                    completion("JSON Decode Error: \(error.localizedDescription).\n\nResponse:\n\(rawResponse)")
                }
            }
        }.resume()
    }
}
