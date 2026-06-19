import SwiftUI

@main
struct CurationLabApp: App {
    @StateObject private var libraryService = PhotoLibraryService()
    
    public init() {
        loadKeysIfAvailable()
    }
    
    private func loadKeysIfAvailable() {
        guard let path = Bundle.main.path(forResource: "Keys", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) as? [String: Any] else {
            return
        }
        
        let defaults = UserDefaults.standard
        
        if let geminiKey = dict["GeminiAPIKey"] as? String, !geminiKey.isEmpty {
            if defaults.string(forKey: "gemini_api_key") == nil || defaults.string(forKey: "gemini_api_key") == "" {
                defaults.set(geminiKey, forKey: "gemini_api_key")
            }
        }
        
        if let groqKey = dict["GroqAPIKey"] as? String, !groqKey.isEmpty {
            if defaults.string(forKey: "groq_api_key") == nil || defaults.string(forKey: "groq_api_key") == "" {
                defaults.set(groqKey, forKey: "groq_api_key")
            }
        }
    }
    
    public var body: some Scene {
        WindowGroup {
            Group {
                if libraryService.permissionStatus == .authorized || libraryService.permissionStatus == .limited {
                    MainTabView(libraryService: libraryService)
                } else {
                    OnboardingView(libraryService: libraryService)
                }
            }
        }
    }
}
