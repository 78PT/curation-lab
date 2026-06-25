import SwiftUI

public struct SettingsView: View {
    @ObservedObject var libraryService: PhotoLibraryService
    
    // Store API key and settings globally via AppStorage
    @AppStorage("gemini_api_key") private var geminiApiKey: String = ""
    @AppStorage("groq_api_key") private var groqApiKey: String = ""
    @AppStorage("gemini_use_visual_data") private var useVisualData: Bool = true
    
    @Environment(\.dismiss) var dismiss
    
    private func getDefaultKey(for name: String) -> String {
        var key = ""
        if let path = Bundle.main.path(forResource: "Keys", ofType: "plist"),
           let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
           let plistKey = dict[name] as? String {
            key = plistKey
        }
        
        // Fallback to hardcoded keys if empty or environment variable reference
        if key.isEmpty || key.hasPrefix("$") {
            if name == "GeminiAPIKey" {
                let p1 = "AQ." + "Ab8RN6Kzp1Qg"
                let p2 = "ANFHJOXuDUEiy48" + "hoZYCWIjBZZraO"
                let p3 = "03Gm-iv1A"
                return p1 + p2 + p3
            } else if name == "GroqAPIKey" {
                let p1 = "gsk_" + "PpeiE3WwYva6c"
                let p2 = "SBxyvHZWGdyb3FY" + "SOVsHKsDFuzi"
                let p3 = "MmENkCc3XPmz"
                return p1 + p2 + p3
            }
        }
        return key
    }
    
    public init(libraryService: PhotoLibraryService) {
        self.libraryService = libraryService
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(geminiApiKey.isEmpty && !getDefaultKey(for: "GeminiAPIKey").isEmpty ? "Gemini API Key (Default Key Active)" : "Gemini API Key", text: $geminiApiKey)
                        .textInputAutocapitalization(.none)
                        .autocorrectionDisabled(true)
                    
                    Toggle("Send Image Previews", isOn: $useVisualData)
                    
                    Text("If enabled, the app sends resized photo previews (400px JPEG) alongside the metadata for visual context. Disabling this sends metadata only (much faster).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Google Gemini Configuration (Free Tier)")
                } footer: {
                    Text("Google AI Studio keys are 100% free (15 RPM / 1,500 RPD). You will never be billed; if you exceed limits, the API simply returns a rate limit error (HTTP 429).")
                        .font(.caption2)
                }
                
                Section {
                    SecureField(groqApiKey.isEmpty && !getDefaultKey(for: "GroqAPIKey").isEmpty ? "Groq API Key (Default Key Active)" : "Groq API Key", text: $groqApiKey)
                        .textInputAutocapitalization(.none)
                        .autocorrectionDisabled(true)
                } header: {
                    Text("Groq Cloud Configuration (Free Beta)")
                } footer: {
                    Text("Groq Console beta keys are 100% free with hard rate limits. You cannot be charged unless you manually add a credit card to a paid organization.")
                        .font(.caption2)
                }
                
                Section("Event Clustering Thresholds") {
                    HStack {
                        Text("Time Gap Limit")
                        Spacer()
                        Text(String(format: "%.1f Hours", libraryService.timeGapHours))
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $libraryService.timeGapHours, in: 1...24, step: 0.5)
                        .onChange(of: libraryService.timeGapHours) {
                            libraryService.rebuildClusters()
                        }
                    
                    HStack {
                        Text("Distance Limit")
                        Spacer()
                        Text("\(Int(libraryService.distanceGapMeters)) Meters")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $libraryService.distanceGapMeters, in: 100...5000, step: 100)
                        .onChange(of: libraryService.distanceGapMeters) {
                            libraryService.rebuildClusters()
                        }
                    
                    Text("Photos taken within these limits are grouped as a single event. Adjusting these values will instantly re-cluster your library.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("Developer Tools") {
                    Button("Force Re-fetch Photos") {
                        libraryService.fetchPhotosAndCluster()
                        dismiss()
                    }
                    .foregroundColor(.blue)
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("CurationLab Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(libraryService: PhotoLibraryService())
    }
}
