import SwiftUI

public struct EventDetailView: View {
    @State var cluster: EventCluster
    @ObservedObject var libraryService: PhotoLibraryService
    
    @AppStorage("gemini_api_key") private var apiKey: String = ""
    @AppStorage("groq_api_key") private var groqApiKey: String = ""
    @AppStorage("gemini_use_visual_data") private var useVisualData: Bool = true
    @AppStorage("prompt_history") private var promptHistoryJSON: String = "[]"
    
    @State private var activeTab = 0
    @State private var geminiSelectedAssets: [PhotoAsset] = []
    @State private var geminiError: String? = nil
    
    private var hasApiKey: Bool {
        switch selectedProvider {
        case .gemini:
            return !apiKey.isEmpty
        case .groq:
            return !groqApiKey.isEmpty
        }
    }
    
    // LLM Lab Sandbox States
    @State private var selectedProvider: ModelProvider = .gemini
    @State private var customPrompt = "Analyze these photos and summarize the overall event. Pick the best 2-3 photos to represent this day and explain your choices."
    @State private var selectedAssetIds: Set<String> = []
    @State private var llmResponse: String? = nil
    @State private var isExecutingLLM = false
    @State private var llmError: String? = nil
    
    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 120), spacing: 12)
    ]
    
    public init(cluster: EventCluster, libraryService: PhotoLibraryService) {
        self._cluster = State(initialValue: cluster)
        self.libraryService = libraryService
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Tab Selector (Segmented Control)
            Picker("Curation Views", selection: $activeTab) {
                Text("All Grid").tag(0)
                Text("Apple Local").tag(1)
                Text("Gemini Auto").tag(2)
                Text("LLM Lab").tag(3)
            }
            .pickerStyle(.segmented)
            .padding()
            .background(Color(.systemBackground))
            
            Divider()
            
            // Tab Content
            ScrollView {
                switch activeTab {
                case 0:
                    allPhotosGrid
                case 1:
                    appleCurationView
                case 2:
                    geminiCurationView
                default:
                    llmLabSandboxView
                }
            }
            .background(Color(.systemGroupedBackground))
        }
        .navigationTitle(cluster.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            analyzeMissingAesthetics()
            syncGeminiSelections()
            initializeSandboxSelections()
        }
    }
    
    // MARK: - Tab 1: All Photos Grid
    private var allPhotosGrid: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Photos sorted by Apple's Aesthetic Score")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.horizontal)
                .padding(.top)
            
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(cluster.assets.sorted(by: { $0.aestheticScore > $1.aestheticScore })) { asset in
                    NavigationLink(destination: PhotoInspectorView(asset: asset, libraryService: libraryService)) {
                        GridCell(asset: asset, libraryService: libraryService)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    // MARK: - Tab 2: Apple Curation Selection
    private var appleCurationView: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Apple's Top Selections")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Calculated on-device by Apple's Vision ANE overall aesthetics score, filtering out utility documents or screenshots.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding([.horizontal, .top])
            
            let topAssets = cluster.appleTopAssets(limit: 3)
            
            if topAssets.isEmpty {
                VStack {
                    Text("No high-quality memorable photos found")
                        .foregroundColor(.secondary)
                        .padding()
                }
                .frame(maxWidth: .infinity)
            } else {
                ForEach(topAssets) { asset in
                    CurationCard(asset: asset, label: "Score: \(String(format: "%.3f", asset.aestheticScore))", libraryService: libraryService)
                }
                .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Tab 3: Gemini Curation Selection (Auto)
    private var geminiCurationView: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Gemini Curation Agent")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Sends photo metadata (and previews, if enabled) to the Gemini model to select the best representative photos for this event.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding([.horizontal, .top])
            
            if apiKey.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "key.fill")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    
                    Text("API Key Missing")
                        .font(.headline)
                    
                    Text("Please navigate to Settings (gear icon on Dashboard) and save your Gemini API Key to enable LLM curation.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(16)
                .padding(.horizontal)
            } else if cluster.isGeminiCuring {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Analyzing event data...")
                        .font(.headline)
                    Text(useVisualData ? "Compressing top images & sending base64 payloads to Gemini API..." : "Sending EXIF and aesthetics metadata payload to Gemini...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(16)
                .padding(.horizontal)
            } else if let error = geminiError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                    Text("Curation Failed")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    
                    Button("Retry") {
                        runGeminiCuration()
                    }
                    .font(.subheadline)
                    .foregroundColor(.blue)
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(16)
                .padding(.horizontal)
            } else if geminiSelectedAssets.isEmpty {
                VStack {
                    Button(action: {
                        runGeminiCuration()
                    }) {
                        HStack {
                            Image(systemName: "brain.head.profile")
                            Text("Run Gemini Curation")
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.blue)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                }
            } else {
                // Display Gemini Results
                VStack(alignment: .leading, spacing: 18) {
                    if let summary = cluster.geminiReasoning {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("LLM Curation Reasoning")
                                .font(.headline)
                            
                            Text(summary)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                                .padding()
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(12)
                        }
                        .padding(.horizontal)
                    }
                    
                    Text("Photos Selected by Gemini:")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    ForEach(geminiSelectedAssets) { asset in
                        CurationCard(asset: asset, label: "Apple Score: \(String(format: "%.2f", asset.aestheticScore))", libraryService: libraryService)
                    }
                    .padding(.horizontal)
                    
                    Button("Reset Curation") {
                        clearCuration()
                    }
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .padding()
                }
            }
        }
    }
    
    // MARK: - Tab 4: LLM Lab Sandbox Workspace
    private var llmLabSandboxView: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header Description
            VStack(alignment: .leading, spacing: 6) {
                Text("LLM Lab Sandbox")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Choose your model provider, select exactly which photos to send, write a custom prompt, and inspect the results. Free rate limits apply.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding([.horizontal, .top])
            
            // 1. Model Selection
            VStack(alignment: .leading, spacing: 8) {
                Text("1. Select Model Provider")
                    .font(.headline)
                    .padding(.horizontal)
                
                Picker("Provider", selection: $selectedProvider) {
                    ForEach(ModelProvider.allCases) { prov in
                        Text(prov.rawValue).tag(prov)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                
                // Key Validation Warn
                if !hasApiKey {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Please set your \(selectedProvider.rawValue) API Key in Settings.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal)
                }
            }
            
            // 2. Photo Multi-Selector
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("2. Select Photos (\(selectedAssetIds.count) / \(cluster.assets.count))")
                        .font(.headline)
                    
                    Spacer()
                    
                    Button("All") {
                        selectedAssetIds = Set(cluster.assets.map { $0.localIdentifier })
                    }
                    .font(.caption)
                    
                    Text("|")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button("None") {
                        selectedAssetIds.removeAll()
                    }
                    .font(.caption)
                }
                .padding(.horizontal)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(cluster.assets) { asset in
                            SelectableThumbnail(
                                asset: asset,
                                isSelected: selectedAssetIds.contains(asset.localIdentifier),
                                libraryService: libraryService
                            ) {
                                if selectedAssetIds.contains(asset.localIdentifier) {
                                    selectedAssetIds.remove(asset.localIdentifier)
                                } else {
                                    selectedAssetIds.insert(asset.localIdentifier)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            
            // 3. Prompt Constructor
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("3. Prompt Instruction")
                        .font(.headline)
                    Spacer()
                    
                    // Preset Prompts Dropdown
                    Menu {
                        Section("Preset Templates") {
                            Button("Recommend Representative Pics") {
                                customPrompt = "Pick the top 2 photos that represent this day. Explain your reasoning."
                            }
                            Button("Evaluate Aesthetics & Blur") {
                                customPrompt = "Look closely at these photos. Which one has the best composition, exposure, and sharpness? Detail any defects like blur or bad lighting."
                            }
                            Button("Write Diary Story") {
                                customPrompt = "Write a creative, detailed travel journal entry describing what happened at this event based on the photos and camera metadata."
                            }
                        }
                        
                        let history = getPromptHistory()
                        if !history.isEmpty {
                            Section("Recent Prompts") {
                                ForEach(history, id: \.self) { hist in
                                    Button(hist) {
                                        customPrompt = hist
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "list.bullet.rectangle.portrait")
                            Text("Presets & History")
                        }
                        .font(.caption)
                        .fontWeight(.semibold)
                    }
                }
                .padding(.horizontal)
                
                TextEditor(text: $customPrompt)
                    .font(.subheadline)
                    .frame(height: 100)
                    .padding(8)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
                    .padding(.horizontal)
            }
            
            // Execute Actions
            VStack(spacing: 12) {
                if isExecutingLLM {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Calling \(selectedProvider.rawValue) API...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                } else {
                    Button(action: {
                        runLLMLabRequest()
                    }) {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Run LLM Request")
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(selectedAssetIds.isEmpty || !hasApiKey ? Color.gray : Color.blue)
                        .cornerRadius(12)
                    }
                    .disabled(selectedAssetIds.isEmpty || !hasApiKey)
                    .padding(.horizontal)
                }
            }
            
            // 4. Response Output Cards
            if let error = llmError {
                VStack(alignment: .leading, spacing: 8) {
                    Text("API Error Output")
                        .font(.headline)
                        .foregroundColor(.red)
                    Text(error)
                        .font(.subheadline)
                        .padding()
                        .background(Color.red.opacity(0.08))
                        .foregroundColor(.red)
                        .cornerRadius(10)
                }
                .padding(.horizontal)
            }
            
            if let response = llmResponse {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Model Output Response")
                        .font(.headline)
                    
                    Text(response)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(12)
                }
                .padding(.horizontal)
                .padding(.bottom, 30)
            }
        }
    }
    
    // MARK: - Helpers & Data Sync Methods
    
    private func initializeSandboxSelections() {
        if selectedAssetIds.isEmpty {
            selectedAssetIds = Set(cluster.assets.map { $0.localIdentifier })
        }
    }
    
    private func getPromptHistory() -> [String] {
        guard let data = promptHistoryJSON.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
    
    private func savePromptToHistory(_ promptString: String) {
        var history = getPromptHistory()
        history.removeAll { $0 == promptString }
        history.insert(promptString, at: 0)
        let limited = Array(history.prefix(8))
        if let data = try? JSONEncoder().encode(limited),
           let jsonStr = String(data: data, encoding: .utf8) {
            promptHistoryJSON = jsonStr
        }
    }
    
    private func runLLMLabRequest() {
        let key = selectedProvider == .gemini ? apiKey : groqApiKey
        guard !key.isEmpty else {
            self.llmError = "API Key missing. Enter it in Settings."
            return
        }
        
        self.isExecutingLLM = true
        self.llmResponse = nil
        self.llmError = nil
        
        let selectedAssets = cluster.assets.filter { selectedAssetIds.contains($0.localIdentifier) }
        
        LLMService.shared.runPrompt(
            provider: selectedProvider,
            apiKey: key,
            prompt: customPrompt,
            assets: selectedAssets,
            libraryService: libraryService
        ) { response in
            self.isExecutingLLM = false
            
            if response.contains("Error") || response.contains("Network Error") {
                self.llmError = response
            } else {
                self.llmResponse = response
                self.savePromptToHistory(self.customPrompt)
            }
        }
    }
    
    private func analyzeMissingAesthetics() {
        for (index, asset) in cluster.assets.enumerated() {
            if !asset.isAestheticAnalyzed || !asset.isClassified {
                VisionAnalysisService.shared.analyzeAsset(asset, libraryService: libraryService) { analyzed in
                    if index < cluster.assets.count {
                        self.cluster.assets[index] = analyzed
                    }
                }
            }
        }
    }
    
    private func runGeminiCuration() {
        self.cluster.isGeminiCuring = true
        self.geminiError = nil
        
        let prompt = """
        You are an expert travel photographer and digital memory archivist. 
        Your task is to select the top 2-3 photos that best represent this event cluster. 
        
        Do not pick utility images (like screenshots, receipts, or documents) unless they are absolutely central to the story. Use Apple's Aesthetic Score, camera settings (like aperture for depth of field, ISO), scene tags, and visual content.
        
        Return your response in STRICT JSON format matching this schema:
        {
          "selectedPhotoIds": ["id1", "id2"],
          "reasoning": "A paragraph explaining the selection criteria, comparing why these were chosen over others (mentioning aesthetics, GPS, camera details, or contents)",
          "eventSummary": "A 1-sentence description/title of the overall event based on the metadata and images"
        }
        Do not output markdown code blocks unless it is JSON. Return ONLY the raw JSON string.
        """
        
        // We only send the top 5 images sorted by Apple's score to avoid rate limits
        let topAssets = cluster.assets
            .filter { !$0.isUtility }
            .sorted { $0.aestheticScore > $1.aestheticScore }
            .prefix(5)
        
        LLMService.shared.runPrompt(
            provider: .gemini,
            apiKey: apiKey,
            prompt: prompt,
            assets: Array(topAssets),
            libraryService: libraryService
        ) { response in
            self.cluster.isGeminiCuring = false
            
            let cleaned = response
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            struct AutoResponse: Codable {
                let selectedPhotoIds: [String]
                let reasoning: String
            }
            
            if let jsonData = cleaned.data(using: .utf8),
               let parsed = try? JSONDecoder().decode(AutoResponse.self, from: jsonData) {
                self.cluster.geminiSelectedIds = parsed.selectedPhotoIds
                self.cluster.geminiReasoning = parsed.reasoning
                self.syncGeminiSelections()
            } else {
                self.cluster.geminiSelectedIds = []
                self.cluster.geminiReasoning = response
            }
        }
    }
    
    private func syncGeminiSelections() {
        self.geminiSelectedAssets = cluster.assets.filter { asset in
            cluster.geminiSelectedIds.contains(asset.localIdentifier)
        }
    }
    
    private func clearCuration() {
        cluster.geminiSelectedIds = []
        cluster.geminiReasoning = nil
        self.geminiSelectedAssets = []
    }
}

fileprivate struct SelectableThumbnail: View {
    let asset: PhotoAsset
    let isSelected: Bool
    @ObservedObject var libraryService: PhotoLibraryService
    let action: () -> Void
    
    @State private var thumbnail: UIImage? = nil
    
    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                if let image = thumbnail {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 80)
                        .cornerRadius(8)
                        .clipped()
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.12))
                        .frame(width: 80, height: 80)
                }
                
                // Checked/Unchecked indicator badge
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.caption)
                    .foregroundColor(isSelected ? .blue : .white)
                    .padding(4)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Circle())
                    .padding(4)
            }
        }
        .buttonStyle(.plain)
        .onAppear {
            libraryService.fetchThumbnail(for: asset, size: CGSize(width: 160, height: 160)) { img in
                self.thumbnail = img
            }
        }
    }
}

fileprivate struct GridCell: View {
    let asset: PhotoAsset
    @ObservedObject var libraryService: PhotoLibraryService
    
    @State private var thumbnail: UIImage? = nil
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let image = thumbnail {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 100, height: 100)
                    .cornerRadius(10)
                    .clipped()
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.gray.opacity(0.12))
                    .frame(width: 100, height: 100)
                    .overlay(ProgressView().scaleEffect(0.6))
            }
            
            // Score Pill
            Text(String(format: "%.1f", asset.aestheticScore))
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(scoreColor(asset.aestheticScore))
                .foregroundColor(.white)
                .cornerRadius(4)
                .padding(4)
            
            // Utility icon if flagged
            if asset.isUtility {
                Image(systemName: "doc.text.fill")
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(3)
                    .background(Color.orange)
                    .clipShape(Circle())
                    .padding([.top, .leading], 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .onAppear {
            libraryService.fetchThumbnail(for: asset, size: CGSize(width: 200, height: 200)) { img in
                self.thumbnail = img
            }
        }
    }
    
    private func scoreColor(_ score: Float) -> Color {
        if score > 0.4 { return .green }
        if score > 0.0 { return .blue }
        if score > -0.4 { return .orange }
        return .red
    }
}

fileprivate struct CurationCard: View {
    let asset: PhotoAsset
    let label: String
    @ObservedObject var libraryService: PhotoLibraryService
    @State private var fullImage: UIImage? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                if let image = fullImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 200)
                        .cornerRadius(12)
                        .frame(maxWidth: .infinity)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.1))
                        .frame(height: 180)
                        .overlay(ProgressView())
                }
                
                // Overlay label (score or source marker)
                Text(label)
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.6))
                    .foregroundColor(.white)
                    .cornerRadius(6)
                    .padding(8)
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(asset.creationDate?.description ?? "unknown date")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if !asset.tags.isEmpty {
                        Text(asset.tags.map { $0.name }.joined(separator: ", "))
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                }
                
                Spacer()
                
                NavigationLink(destination: PhotoInspectorView(asset: asset, libraryService: libraryService)) {
                    Text("Inspect Metadata")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.08))
                        .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(14)
        .shadow(radius: 2)
        .onAppear {
            libraryService.fetchThumbnail(for: asset, size: CGSize(width: 500, height: 500)) { img in
                self.fullImage = img
            }
        }
    }
}
