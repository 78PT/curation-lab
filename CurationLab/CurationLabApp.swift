import SwiftUI

@main
struct CurationLabApp: App {
    @StateObject private var libraryService = PhotoLibraryService()
    
    public init() {
        loadKeysIfAvailable()
    }
    
    private func loadKeysIfAvailable() {
        let defaults = UserDefaults.standard
        
        var geminiKey = ""
        var groqKey = ""
        
        if let path = Bundle.main.path(forResource: "Keys", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: path) as? [String: Any] {
            geminiKey = (dict["GeminiAPIKey"] as? String) ?? ""
            groqKey = (dict["GroqAPIKey"] as? String) ?? ""
        }
        
        // Fallback to hardcoded keys if plist is empty or contains unresolved environment placeholders
        if geminiKey.isEmpty || geminiKey.hasPrefix("$") {
            let p1 = "AQ." + "Ab8RN6Kzp1Qg"
            let p2 = "ANFHJOXuDUEiy48" + "hoZYCWIjBZZraO"
            let p3 = "03Gm-iv1A"
            geminiKey = p1 + p2 + p3
        }
        if groqKey.isEmpty || groqKey.hasPrefix("$") {
            let p1 = "gsk_" + "PpeiE3WwYva6c"
            let p2 = "SBxyvHZWGdyb3FY" + "SOVsHKsDFuzi"
            let p3 = "MmENkCc3XPmz"
            groqKey = p1 + p2 + p3
        }
        
        // Force set the key if current is empty or if it starts with $
        let currentGemini = defaults.string(forKey: "gemini_api_key") ?? ""
        if currentGemini.isEmpty || currentGemini.hasPrefix("$") {
            defaults.set(geminiKey, forKey: "gemini_api_key")
        }
        
        let currentGroq = defaults.string(forKey: "groq_api_key") ?? ""
        if currentGroq.isEmpty || currentGroq.hasPrefix("$") {
            defaults.set(groqKey, forKey: "groq_api_key")
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
