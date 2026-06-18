import SwiftUI

public struct SettingsView: View {
    @ObservedObject var libraryService: PhotoLibraryService
    
    // Store API key and settings globally via AppStorage
    @AppStorage("gemini_api_key") private var geminiApiKey: String = ""
    @AppStorage("groq_api_key") private var groqApiKey: String = ""
    @AppStorage("gemini_use_visual_data") private var useVisualData: Bool = true
    
    @Environment(\.dismiss) var dismiss
    
    public init(libraryService: PhotoLibraryService) {
        self.libraryService = libraryService
    }
    
    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Gemini API Key", text: $geminiApiKey)
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
                    SecureField("Groq API Key", text: $groqApiKey)
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
                        .onChange(of: libraryService.timeGapHours) { _ in
                            libraryService.rebuildClusters()
                        }
                    
                    HStack {
                        Text("Distance Limit")
                        Spacer()
                        Text("\(Int(libraryService.distanceGapMeters)) Meters")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $libraryService.distanceGapMeters, in: 100...5000, step: 100)
                        .onChange(of: libraryService.distanceGapMeters) { _ in
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
            .navigationTitle("CurationLab Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
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
