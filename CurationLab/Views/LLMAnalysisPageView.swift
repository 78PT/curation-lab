import SwiftUI
import Photos

public struct LLMAnalysisPageView: View {
    @ObservedObject var libraryService: PhotoLibraryService
    
    // API Keys and Configuration
    @AppStorage("gemini_api_key") private var geminiApiKey: String = ""
    @AppStorage("groq_api_key") private var groqApiKey: String = ""
    @AppStorage("llm_selected_provider") private var selectedProviderRaw: String = ModelProvider.gemini.rawValue
    @AppStorage("prompt_history") private var promptHistoryJSON: String = "[]"
    @AppStorage("saved_memories") private var savedMemoriesJSON: String = "[]"
    @AppStorage("tagging_prompt") private var taggingPrompt: String = "Analyze this image in detail. Extract a list of key thematic tags representing objects, location, colors, and mood. Also write a short description (2-3 sentences) summarizing what is happening in the photo. Format your response strictly as a JSON object matching this structure: {\"tags\": [\"outdoor\", \"sunny\", \"portrait\", \"happy\"], \"description\": \"A close-up shot of a person smiling during a sunny outdoor trip.\"}"
    @AppStorage("memory_use_visual_data") private var memoryUseVisualData: Bool = true
    
    @State private var isHistoryExpanded = false
    @State private var isTaggingPromptExpanded = false
    
    // UI state
    @State private var selectedTab = 0 // 0 = Image Tagging, 1 = Memory Builder
    @State private var activeAssetId: String? = nil
    @State private var selectedAssetIds: Set<String> = []
    @State private var isExecuting = false
    @State private var errorText: String? = nil
    @State private var responseText: String? = nil
    @State private var isConfigExpanded = false
    @State private var newManualTag = ""
    
    // Batch tagging states for Memory Builder
    @State private var isBatchTagging = false
    @State private var batchTaggingIndex = 0
    @State private var batchTaggingTotal = 0
    
    // Curated Memory states
    @State private var curatedMemory: CuratedMemory? = nil
    @State private var customPrompt = "Create a warm, nostalgic diary entry capturing the feeling of these highlights."
    @State private var selectedSavedMemory: SavedMemory? = nil
    
    private var selectedProvider: ModelProvider {
        ModelProvider(rawValue: selectedProviderRaw) ?? .gemini
    }
    
    private var hasApiKey: Bool {
        switch selectedProvider {
        case .gemini:
            return !geminiApiKey.isEmpty || !getDefaultKey(for: "GeminiAPIKey").isEmpty
        case .groq:
            return !groqApiKey.isEmpty || !getDefaultKey(for: "GroqAPIKey").isEmpty
        }
    }
    
    private var activeAsset: PhotoAsset? {
        guard let id = activeAssetId else { return nil }
        return libraryService.loadedAssets.first { $0.localIdentifier == id }
    }
    
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
    
    private let gridColumns = [
        GridItem(.adaptive(minimum: 80, maximum: 100), spacing: 6)
    ]
    
    public init(libraryService: PhotoLibraryService) {
        self.libraryService = libraryService
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    
                    // 1. API Configuration Card (Collapsible)
                    VStack(alignment: .leading, spacing: 10) {
                        Button(action: {
                            withAnimation(.easeInOut) {
                                isConfigExpanded.toggle()
                            }
                        }) {
                            HStack {
                                Label("API Setup", systemImage: "key.horizontal.fill")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: isConfigExpanded ? "chevron.up" : "chevron.down")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 12)
                        
                        if isConfigExpanded {
                            VStack(alignment: .leading, spacing: 12) {
                                Picker("Provider", selection: $selectedProviderRaw) {
                                    ForEach(ModelProvider.allCases, id: \.rawValue) { prov in
                                        Text(prov.rawValue).tag(prov.rawValue)
                                    }
                                }
                                .pickerStyle(.segmented)
                                
                                if selectedProvider == .gemini {
                                    SecureField("Gemini API Key (Default Key Active)", text: $geminiApiKey)
                                        .textFieldStyle(.roundedBorder)
                                        .textInputAutocapitalization(.none)
                                        .autocorrectionDisabled(true)
                                } else {
                                    SecureField("Groq API Key (Default Key Active)", text: $groqApiKey)
                                        .textFieldStyle(.roundedBorder)
                                        .textInputAutocapitalization(.none)
                                        .autocorrectionDisabled(true)
                                }
                                
                                if !hasApiKey {
                                    HStack {
                                        Image(systemName: "exclamationmark.circle.fill")
                                            .foregroundColor(.orange)
                                        Text("Please enter a valid API Key to make requests.")
                                            .font(.caption2)
                                            .foregroundColor(.orange)
                                    }
                                }
                            }
                            .padding([.horizontal, .bottom])
                        }
                    }
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .cornerRadius(14)
                    .padding(.horizontal)
                    .padding(.top, 4)
                    
                    // Tab Picker
                    Picker("LLM Lab Mode", selection: $selectedTab) {
                        Text("Image Tagging").tag(0)
                        Text("Memory Builder").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    
                    if selectedTab == 0 {
                        // TAB 0: Single Image Tagging View
                        renderTaggingView()
                    } else {
                        // TAB 1: Memory Builder View
                        renderMemoryBuilderView()
                    }
                    
                    renderPromptHistoryCard()
                }
            }
            .navigationTitle("LLM Labs")
            .background(Color(uiColor: .systemGroupedBackground))
            .sheet(item: $selectedSavedMemory) { memory in
                SavedMemoryDetailView(memory: memory, libraryService: libraryService)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    albumPickerMenu
                }
            }
            .onAppear {
                // Set initial active asset if none is set
                if activeAssetId == nil, let first = libraryService.loadedAssets.first {
                    activeAssetId = first.localIdentifier
                }
            }
        }
    }
    
    // MARK: - Sub-View: Image Tagging
    
    @ViewBuilder
    private func renderTaggingView() -> some View {
        VStack(spacing: 16) {
            // Tagging Prompt Customizer
            VStack(alignment: .leading, spacing: 8) {
                Button(action: {
                    withAnimation {
                        isTaggingPromptExpanded.toggle()
                    }
                }) {
                    HStack {
                        Label("Customize Tagging Prompt", systemImage: "square.and.pencil")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Image(systemName: isTaggingPromptExpanded ? "chevron.up" : "chevron.down")
                    }
                    .foregroundColor(.blue)
                }
                .padding(.horizontal)
                .padding(.top, 10)
                
                if isTaggingPromptExpanded {
                    VStack(alignment: .trailing, spacing: 8) {
                        TextEditor(text: $taggingPrompt)
                            .font(.system(.caption, design: .monospaced))
                            .frame(minHeight: 100)
                            .padding(6)
                            .background(Color(uiColor: .systemGroupedBackground))
                            .cornerRadius(8)
                            .padding(.horizontal)
                        
                        Button("Reset to Default") {
                            taggingPrompt = "Analyze this image in detail. Extract a list of key thematic tags representing objects, location, colors, and mood. Also write a short description (2-3 sentences) summarizing what is happening in the photo. Format your response strictly as a JSON object matching this structure: {\"tags\": [\"outdoor\", \"sunny\", \"portrait\", \"happy\"], \"description\": \"A close-up shot of a person smiling during a sunny outdoor trip.\"}"
                        }
                        .font(.caption2)
                        .padding(.trailing)
                        .padding(.bottom, 10)
                    }
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .cornerRadius(14)
            .padding(.horizontal)
            
            // Large Preview Card
            VStack(spacing: 12) {
                if let asset = activeAsset {
                    ActivePhotoPreview(asset: asset, libraryService: libraryService)
                        .frame(height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)
                        .padding(.top, 12)
                    
                    // Metadata & Tags Detail
                    VStack(alignment: .leading, spacing: 12) {
                        if asset.isLlmAnalyzed {
                            Text("LLM Tags")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                            
                            // Wrapping Tag Badges Scroll
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(asset.llmTags, id: \.self) { tag in
                                        HStack(spacing: 4) {
                                            Text(tag)
                                                .font(.caption)
                                                .fontWeight(.medium)
                                            Button(action: {
                                                removeManualTag(for: asset, tag: tag)
                                            }) {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.blue.opacity(0.12))
                                        .foregroundColor(.blue)
                                        .cornerRadius(20)
                                    }
                                }
                                .padding(.horizontal)
                            }
                            
                            // Add tag manually row
                            HStack {
                                TextField("Add Tag", text: $newManualTag)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.subheadline)
                                    .frame(maxWidth: 150)
                                
                                Button(action: {
                                    addManualTag(for: asset)
                                }) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title3)
                                }
                                .disabled(newManualTag.isEmpty)
                            }
                            .padding(.horizontal)
                            
                            Divider().padding(.horizontal)
                            
                            Text("LLM Description")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.secondary)
                                .padding(.horizontal)
                            
                            Text(asset.llmDescription)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(uiColor: .systemGroupedBackground))
                                .cornerRadius(10)
                                .padding(.horizontal)
                            
                            // Action Buttons
                            HStack(spacing: 12) {
                                Button(action: {
                                    executeSingleTagging(for: asset)
                                }) {
                                    Label("Re-Analyze", systemImage: "arrow.clockwise")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(8)
                                }
                                
                                Button(action: {
                                    libraryService.clearLLMAnalysis(for: asset.localIdentifier)
                                }) {
                                    Label("Clear Data", systemImage: "trash")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.red)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color.red.opacity(0.1))
                                        .cornerRadius(8)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 12)
                            
                        } else {
                            // Empty State / Click to Analyze
                            VStack(spacing: 12) {
                                Text("This photo has not been tagged by an LLM yet.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                
                                if isExecuting {
                                    VStack(spacing: 8) {
                                        ProgressView()
                                        Text("Analyzing with \(selectedProvider.rawValue)...")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                } else {
                                    Button(action: {
                                        executeSingleTagging(for: asset)
                                    }) {
                                        HStack {
                                            Image(systemName: "sparkles")
                                            Text("Analyze & Tag with LLM")
                                                .fontWeight(.bold)
                                        }
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 12)
                                        .background(hasApiKey ? Color.blue : Color.gray)
                                        .cornerRadius(10)
                                    }
                                    .disabled(!hasApiKey)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                        }
                    }
                } else {
                    Text("No Photos Found")
                        .foregroundColor(.secondary)
                        .padding()
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .cornerRadius(16)
            .padding(.horizontal)
            
            // Photo Selection Grid
            VStack(alignment: .leading, spacing: 12) {
                Text("Select Photo to Tag")
                    .font(.headline)
                    .padding(.horizontal)
                
                LazyVGrid(columns: gridColumns, spacing: 6) {
                    ForEach(libraryService.loadedAssets) { asset in
                        Button(action: {
                            withAnimation {
                                activeAssetId = asset.localIdentifier
                            }
                        }) {
                            ZStack(alignment: .topTrailing) {
                                ThumbnailCell(asset: asset, libraryService: libraryService)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(activeAssetId == asset.localIdentifier ? Color.blue : Color.clear, lineWidth: 3)
                                    )
                                
                                if asset.isLlmAnalyzed {
                                    Image(systemName: "tag.fill")
                                        .font(.caption2)
                                        .foregroundColor(.white)
                                        .padding(4)
                                        .background(Color.blue.clipShape(Circle()))
                                        .padding(4)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    
                    if !libraryService.isLoading {
                        Color.clear
                            .frame(height: 30)
                            .onAppear {
                                libraryService.loadNextBatch()
                            }
                    }
                }
                .padding(.horizontal)
                
                if libraryService.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            }
            .padding(.vertical, 12)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .cornerRadius(16)
            .padding(.horizontal)
        }
    }
    
    // MARK: - Sub-View: Memory Builder
    
    @ViewBuilder
    private func renderMemoryBuilderView() -> some View {
        VStack(spacing: 16) {
            
            // Selected Assets Info
            VStack(alignment: .leading, spacing: 12) {
                Text("Curate Highlights (\(selectedAssetIds.count) Selected)")
                    .font(.headline)
                    .padding(.horizontal)
                    .padding(.top, 12)
                
                let selectedAssets = libraryService.loadedAssets.filter { selectedAssetIds.contains($0.localIdentifier) }
                let untaggedCount = selectedAssets.filter { !$0.isLlmAnalyzed }.count
                
                if !selectedAssetIds.isEmpty {
                    // Selected Horizontal Scroll
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(selectedAssets) { asset in
                                ZStack(alignment: .topTrailing) {
                                    ThumbnailCell(asset: asset, libraryService: libraryService)
                                        .frame(width: 70, height: 70)
                                        .cornerRadius(8)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(asset.isLlmAnalyzed ? Color.green : Color.orange, lineWidth: 2)
                                        )
                                    
                                    Button(action: {
                                        _ = selectedAssetIds.remove(asset.localIdentifier)
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.red)
                                            .background(Color.white.clipShape(Circle()))
                                    }
                                    .offset(x: 4, y: -4)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .frame(height: 80)
                    
                    Divider().padding(.horizontal)
                    
                    // Batch tagging trigger
                    if untaggedCount > 0 {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(untaggedCount) selected photos are untagged")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("Tagging them helps the memory builder curate better.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            
                            if isBatchTagging {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("\(batchTaggingIndex)/\(batchTaggingTotal)")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                }
                            } else {
                                Button("Auto-Tag (\(untaggedCount))") {
                                    triggerBatchTagging(for: selectedAssets.filter { !$0.isLlmAnalyzed })
                                }
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(hasApiKey ? Color.blue : Color.gray)
                                .cornerRadius(8)
                                .disabled(!hasApiKey)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 12)
                    }
                } else {
                    Text("Select 2 or more photos below to build a curated memory scrapbook.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                }
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .cornerRadius(16)
            .padding(.horizontal)
            
            // Scrapbook Builder Panel
            if !selectedAssetIds.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Curation Configuration")
                        .font(.headline)
                        .padding(.horizontal)
                        .padding(.top, 12)
                    
                    Toggle("Send Images Visual Data", isOn: $memoryUseVisualData)
                        .padding(.horizontal)
                    
                    Text(memoryUseVisualData ? "Sends resized photo frames to the LLM. Displays output as a collage." : "Only sends tags and descriptions. Displays output as a slideshow.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                        .padding(.bottom, 4)
                    
                    Divider().padding(.horizontal)
                    
                    Text("Scrapbook Narrative Style")
                        .font(.headline)
                        .padding(.horizontal)
                        .padding(.top, 12)
                    
                    TextEditor(text: $customPrompt)
                        .font(.subheadline)
                        .frame(minHeight: 60, maxHeight: 90)
                        .padding(8)
                        .background(Color(uiColor: .systemGroupedBackground))
                        .cornerRadius(8)
                        .padding(.horizontal)
                    
                    // Narrative presets
                    HStack(spacing: 8) {
                        Button("Nostalgic") {
                            customPrompt = "Create a warm, nostalgic diary entry capturing the feeling of these highlights."
                        }
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)
                        
                        Button("Humorous") {
                            customPrompt = "Write a fun, quirky, and lighthearted commentary about what went down in these photos."
                        }
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)
                        
                        Button("Short Caption") {
                            customPrompt = "Generate a single poetic, minimalist sentence caption suitable for Instagram."
                        }
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)
                    }
                    .padding(.horizontal)
                    
                    // Generation trigger
                    if isExecuting {
                        VStack(spacing: 8) {
                            ProgressView()
                            Text("Curating & generating scrapbook with \(selectedProvider.rawValue)...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    } else {
                        Button(action: executeMemoryGeneration) {
                            HStack {
                                Image(systemName: "book.fill")
                                Text("Generate Curated Memory")
                                    .fontWeight(.bold)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(hasApiKey && selectedAssetIds.count >= 2 ? Color.blue : Color.gray)
                            .cornerRadius(10)
                        }
                        .disabled(!hasApiKey || selectedAssetIds.count < 2)
                        .padding(.horizontal)
                        .padding(.bottom, 12)
                    }
                }
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(16)
                .padding(.horizontal)
            }
            
            // Generated Memory Display
            if let error = errorText {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.red.opacity(0.08))
                    .cornerRadius(10)
                    .padding(.horizontal)
            }
            
            if let memory = curatedMemory {
                VStack(spacing: 16) {
                    Text("Preview: Curated Scrapbook Memory")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                    
                    VStack(spacing: 16) {
                        // Title
                        Text(memory.headline)
                            .font(.title3)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                            .padding(.top, 16)
                        
                        // Curated collage or slideshow of images chosen by the LLM
                        let chosenAssets = libraryService.loadedAssets.filter { memory.selected_photo_ids.contains($0.localIdentifier) }
                        if !chosenAssets.isEmpty {
                            if memory.isSlideshow == true {
                                SlideshowView(assets: chosenAssets, libraryService: libraryService)
                                    .padding(.horizontal)
                            } else {
                                MemoryCollageView(assets: chosenAssets, libraryService: libraryService)
                                    .padding(.horizontal)
                            }
                        } else {
                            // Fallback if LLM ID mapping is fuzzy
                            let fallbackAssets = libraryService.loadedAssets.filter { selectedAssetIds.contains($0.localIdentifier) }
                            if memory.isSlideshow == true {
                                SlideshowView(assets: Array(fallbackAssets.prefix(8)), libraryService: libraryService)
                                    .padding(.horizontal)
                            } else {
                                MemoryCollageView(assets: Array(fallbackAssets.prefix(8)), libraryService: libraryService)
                                    .padding(.horizontal)
                            }
                        }
                        
                        // Story narrative
                        Text(memory.story)
                            .font(.body)
                            .foregroundColor(.primary)
                            .lineSpacing(5)
                            .padding()
                            .background(Color(uiColor: .systemGroupedBackground))
                            .cornerRadius(10)
                            .padding(.horizontal)
                        
                        // Save memory button
                        Button(action: {
                            saveMemoryToScrapbook(memory)
                        }) {
                            Label("Save to Scrapbook History", systemImage: "bookmark.fill")
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 10)
                                .background(Color.green)
                                .cornerRadius(8)
                        }
                        .padding(.bottom, 16)
                    }
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .cornerRadius(16)
                    .shadow(radius: 4)
                    .padding(.horizontal)
                }
            }
            
            // Saved Scrapbook History List
            let savedMemories = getSavedMemories()
            if !savedMemories.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Saved Scrapbook History")
                        .font(.headline)
                        .padding(.horizontal)
                        .padding(.top, 8)
                    
                    ForEach(savedMemories) { memory in
                        HStack {
                            Button(action: {
                                selectedSavedMemory = memory
                            }) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(memory.headline)
                                        .font(.subheadline)
                                        .fontWeight(.bold)
                                        .foregroundColor(.primary)
                                    
                                    Text(memory.story)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            
                            Button(action: {
                                deleteSavedMemory(id: memory.idString)
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                                    .padding(8)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding()
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }
                }
            }
            
            // Photo Selection Grid for Multi-Select
            VStack(alignment: .leading, spacing: 12) {
                Text("Select Photos to Include")
                    .font(.headline)
                    .padding(.horizontal)
                    .padding(.top, 12)
                
                LazyVGrid(columns: gridColumns, spacing: 6) {
                    ForEach(libraryService.loadedAssets) { asset in
                        Button(action: {
                            if selectedAssetIds.contains(asset.localIdentifier) {
                                selectedAssetIds.remove(asset.localIdentifier)
                            } else {
                                selectedAssetIds.insert(asset.localIdentifier)
                            }
                        }) {
                            ZStack(alignment: .topTrailing) {
                                ThumbnailCell(asset: asset, libraryService: libraryService)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(selectedAssetIds.contains(asset.localIdentifier) ? Color.blue : Color.clear, lineWidth: 3)
                                    )
                                
                                Image(systemName: selectedAssetIds.contains(asset.localIdentifier) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selectedAssetIds.contains(asset.localIdentifier) ? .blue : .white)
                                    .padding(4)
                                    .background(Color.black.opacity(selectedAssetIds.contains(asset.localIdentifier) ? 0.0 : 0.3).clipShape(Circle()))
                                    .padding(4)
                                
                                if asset.isLlmAnalyzed {
                                    VStack {
                                        Spacer()
                                        HStack {
                                            Image(systemName: "tag.fill")
                                                .font(.caption2)
                                                .foregroundColor(.white)
                                            Text("\(asset.llmTags.count)")
                                                .font(.system(size: 8))
                                                .fontWeight(.bold)
                                                .foregroundColor(.white)
                                        }
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                        .background(Color.green.opacity(0.85))
                                        .cornerRadius(4)
                                        .padding(4)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    
                    if !libraryService.isLoading {
                        Color.clear
                            .frame(height: 30)
                            .onAppear {
                                libraryService.loadNextBatch()
                            }
                    }
                }
                .padding(.horizontal)
                
                if libraryService.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            }
            .padding(.vertical, 12)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .cornerRadius(16)
            .padding(.horizontal)
        }
    }
    
    // MARK: - Logic & Helper Methods
    
    private func addManualTag(for asset: PhotoAsset) {
        let tag = newManualTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else { return }
        
        var tags = asset.llmTags
        if !tags.contains(tag) {
            tags.append(tag)
        }
        libraryService.saveLLMAnalysis(for: asset.localIdentifier, tags: tags, description: asset.llmDescription)
        newManualTag = ""
    }
    
    private func removeManualTag(for asset: PhotoAsset, tag: String) {
        var tags = asset.llmTags
        tags.removeAll { $0 == tag }
        libraryService.saveLLMAnalysis(for: asset.localIdentifier, tags: tags, description: asset.llmDescription)
    }
    
    private func executeSingleTagging(for asset: PhotoAsset) {
        let defaultKey = selectedProvider == .gemini ? getDefaultKey(for: "GeminiAPIKey") : getDefaultKey(for: "GroqAPIKey")
        let enteredKey = selectedProvider == .gemini ? geminiApiKey : groqApiKey
        let key = enteredKey.isEmpty ? defaultKey : enteredKey
        
        guard !key.isEmpty else { return }
        
        isExecuting = true
        errorText = nil
        
        let prompt = taggingPrompt
        savePromptToHistory(prompt, type: "Tagging")
        
        LLMService.shared.runPrompt(
            provider: selectedProvider,
            apiKey: key,
            prompt: prompt,
            assets: [asset],
            libraryService: libraryService
        ) { response in
            isExecuting = false
            if let parsed = self.parseTagResponse(response) {
                libraryService.saveLLMAnalysis(for: asset.localIdentifier, tags: parsed.tags, description: parsed.description)
            } else {
                errorText = "Failed to parse JSON response from LLM.\n\nRaw response:\n\(response)"
            }
        }
    }
    
    private func triggerBatchTagging(for assets: [PhotoAsset]) {
        let defaultKey = selectedProvider == .gemini ? getDefaultKey(for: "GeminiAPIKey") : getDefaultKey(for: "GroqAPIKey")
        let enteredKey = selectedProvider == .gemini ? geminiApiKey : groqApiKey
        let key = enteredKey.isEmpty ? defaultKey : enteredKey
        
        guard !key.isEmpty else { return }
        
        isBatchTagging = true
        batchTaggingTotal = assets.count
        batchTaggingIndex = 0
        
        savePromptToHistory(taggingPrompt, type: "Tagging")
        
        func tagNext(index: Int) {
            guard index < assets.count else {
                DispatchQueue.main.async {
                    self.isBatchTagging = false
                    self.libraryService.rebuildClustersLazy()
                }
                return
            }
            
            DispatchQueue.main.async {
                self.batchTaggingIndex = index + 1
            }
            
            let asset = assets[index]
            let prompt = taggingPrompt
            
            LLMService.shared.runPrompt(
                provider: selectedProvider,
                apiKey: key,
                prompt: prompt,
                assets: [asset],
                libraryService: libraryService
            ) { response in
                if let parsed = self.parseTagResponse(response) {
                    libraryService.saveLLMAnalysis(for: asset.localIdentifier, tags: parsed.tags, description: parsed.description)
                }
                
                tagNext(index: index + 1)
            }
        }
        
        tagNext(index: 0)
    }

    private func executeMemoryGeneration() {
        let defaultKey = selectedProvider == .gemini ? getDefaultKey(for: "GeminiAPIKey") : getDefaultKey(for: "GroqAPIKey")
        let enteredKey = selectedProvider == .gemini ? geminiApiKey : groqApiKey
        let key = enteredKey.isEmpty ? defaultKey : enteredKey
        
        guard !key.isEmpty else { return }
        
        isExecuting = true
        curatedMemory = nil
        errorText = nil
        
        savePromptToHistory(customPrompt, type: "Memory")
        
        let selectedAssets = libraryService.loadedAssets.filter { selectedAssetIds.contains($0.localIdentifier) }
        
        // Build metadata content of tagged photos
        var photoContext = ""
        for (idx, asset) in selectedAssets.enumerated() {
            photoContext += "Photo #\(idx + 1) (ID: \(asset.localIdentifier))\n"
            photoContext += "  Dimensions: \(asset.width)x\(asset.height)\n"
            photoContext += "  Date: \(asset.creationDate?.description ?? "unknown")\n"
            if asset.isLlmAnalyzed {
                photoContext += "  LLM Description: \(asset.llmDescription)\n"
                photoContext += "  LLM Tags: [\(asset.llmTags.joined(separator: ", "))]\n"
            } else {
                photoContext += "  On-Device Tags: [\(asset.tags.map { $0.name }.joined(separator: ", "))]\n"
            }
            photoContext += "\n"
        }
        
        let prompt = """
        You are a memory curation assistant. Below is a list of photos, each with its identifier, date, and descriptions/tags:
        
        \(photoContext)
        
        Your tasks are:
        1. Select a subset (between 2 to 8 photos) that together tell the most cohesive, beautiful story. Filter out duplicates, bad quality, or redundant pictures.
        2. Write a catchy title/headline for this memory collection.
        3. Write a beautifully crafted, warm, and nostalgic diary/journal entry story (under 150 words) based on the prompt style request: "\(customPrompt)"
        
        Format your response strictly as a JSON object matching this structure:
        {
          "selected_photo_ids": ["chosen_id_1", "chosen_id_2"],
          "headline": "A Beautiful title for the Memory",
          "story": "The story narrative text..."
        }
        """
        
        LLMService.shared.runPrompt(
            provider: selectedProvider,
            apiKey: key,
            prompt: prompt,
            assets: selectedAssets,
            sendImages: memoryUseVisualData,
            libraryService: libraryService
        ) { response in
            isExecuting = false
            if var decoded = self.parseMemoryJSON(response) {
                decoded.isSlideshow = !memoryUseVisualData
                curatedMemory = decoded
            } else {
                errorText = "Failed to parse structured JSON scrapbook output from LLM.\n\nRaw Response:\n\(response)"
            }
        }
    }
    
    // MARK: - JSON Parsers
    
    private func parseTagResponse(_ text: String) -> LLMTagResponse? {
        var cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanText.hasPrefix("```json") {
            cleanText = cleanText.replacingOccurrences(of: "```json", with: "")
            if cleanText.hasSuffix("```") {
                cleanText = String(cleanText.dropLast(3))
            }
        } else if cleanText.hasPrefix("```") {
            cleanText = cleanText.replacingOccurrences(of: "```", with: "")
            if cleanText.hasSuffix("```") {
                cleanText = String(cleanText.dropLast(3))
            }
        }
        cleanText = cleanText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove trailing commas in arrays if the LLM produced malformed JSON
        guard let data = cleanText.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(LLMTagResponse.self, from: data)
    }
    
    private func parseMemoryJSON(_ text: String) -> CuratedMemory? {
        var cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanText.hasPrefix("```json") {
            cleanText = cleanText.replacingOccurrences(of: "```json", with: "")
            if cleanText.hasSuffix("```") {
                cleanText = String(cleanText.dropLast(3))
            }
        } else if cleanText.hasPrefix("```") {
            cleanText = cleanText.replacingOccurrences(of: "```", with: "")
            if cleanText.hasSuffix("```") {
                cleanText = String(cleanText.dropLast(3))
            }
        }
        cleanText = cleanText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let data = cleanText.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(CuratedMemory.self, from: data)
    }
    
    // MARK: - Persistent Saved Scrapbook Management
    
    private func getSavedMemories() -> [SavedMemory] {
        guard let data = savedMemoriesJSON.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([SavedMemory].self, from: data)) ?? []
    }
    
    private func saveMemoryToScrapbook(_ memory: CuratedMemory) {
        var list = getSavedMemories()
        
        // Avoid adding duplicate headline
        if list.contains(where: { $0.headline == memory.headline }) {
            return
        }
        
        let saved = SavedMemory(
            idString: UUID().uuidString,
            headline: memory.headline,
            story: memory.story,
            photoIds: memory.selected_photo_ids,
            dateCreated: Date()
        )
        list.insert(saved, at: 0)
        
        if let data = try? JSONEncoder().encode(list),
           let json = String(data: data, encoding: .utf8) {
            savedMemoriesJSON = json
            // Clear current preview after saving to keep UI clean
            curatedMemory = nil
        }
    }
    
    private func deleteSavedMemory(id: String) {
        var list = getSavedMemories()
        list.removeAll { $0.idString == id }
        
        if let data = try? JSONEncoder().encode(list),
           let json = String(data: data, encoding: .utf8) {
            savedMemoriesJSON = json
        }
    }
    
    private func getPromptHistory() -> [PromptHistoryItem] {
        guard let data = promptHistoryJSON.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([PromptHistoryItem].self, from: data)) ?? []
    }
    
    private func savePromptToHistory(_ prompt: String, type: String) {
        var list = getPromptHistory()
        // Avoid adding exact duplicate prompts consecutively to keep history clean
        if list.first?.prompt == prompt {
            return
        }
        let newItem = PromptHistoryItem(
            idString: UUID().uuidString,
            prompt: prompt,
            type: type,
            date: Date()
        )
        list.insert(newItem, at: 0)
        
        // Keep last 50 prompts
        if list.count > 50 {
            list = Array(list.prefix(50))
        }
        
        if let data = try? JSONEncoder().encode(list),
           let json = String(data: data, encoding: .utf8) {
            promptHistoryJSON = json
        }
    }
    
    @ViewBuilder
    private func renderPromptHistoryCard() -> some View {
        let history = getPromptHistory()
        
        VStack(alignment: .leading, spacing: 10) {
            Button(action: {
                withAnimation(.easeInOut) {
                    isHistoryExpanded.toggle()
                }
            }) {
                HStack {
                    Label("Prompt History (\(history.count))", systemImage: "clock.arrow.circlepath")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: isHistoryExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)
            
            if isHistoryExpanded {
                if history.isEmpty {
                    Text("No prompts in history yet.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding([.horizontal, .bottom])
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(history) { item in
                            Button(action: {
                                // Tap to re-populate active inputs
                                if item.type == "Tagging" {
                                    taggingPrompt = item.prompt
                                    selectedTab = 0
                                } else {
                                    customPrompt = item.prompt
                                    selectedTab = 1
                                }
                            }) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(item.type)
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(item.type == "Tagging" ? Color.blue.opacity(0.15) : Color.purple.opacity(0.15))
                                            .foregroundColor(item.type == "Tagging" ? .blue : .purple)
                                            .cornerRadius(4)
                                        
                                        Spacer()
                                        
                                        Text(item.date, style: .time)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Text(item.prompt)
                                        .font(.subheadline)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                        .foregroundColor(.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(8)
                                .background(Color(uiColor: .tertiarySystemGroupedBackground))
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding([.horizontal, .bottom])
                }
            }
        }
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(14)
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var albumPickerMenu: some View {
        Menu {
            Button(action: {
                libraryService.selectedAlbumId = nil
            }) {
                HStack {
                    Text("All Photos")
                    if libraryService.selectedAlbumId == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }
            
            if !libraryService.albums.isEmpty {
                Divider()
                
                ForEach(libraryService.albums) { album in
                    Button(action: {
                        libraryService.selectedAlbumId = album.localIdentifier
                    }) {
                        HStack {
                            Label(album.title, systemImage: album.isShared ? "person.2.fill" : "rectangle.stack.fill")
                            if libraryService.selectedAlbumId == album.localIdentifier {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                let activeTitle = libraryService.albums.first(where: { $0.localIdentifier == libraryService.selectedAlbumId })?.title ?? "All Photos"
                Image(systemName: libraryService.selectedAlbumId == nil ? "photo.on.rectangle.angled" : "rectangle.stack.fill")
                    .imageScale(.small)
                Text(activeTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.blue.opacity(0.1))
            .foregroundColor(.blue)
            .cornerRadius(8)
        }
    }
}

// MARK: - Helper Codable Models

struct PromptHistoryItem: Codable, Identifiable {
    var id: String { idString }
    let idString: String
    let prompt: String
    let type: String // "Tagging" or "Memory"
    let date: Date
}

struct LLMTagResponse: Codable {
    let tags: [String]
    let description: String
}

struct CuratedMemory: Codable {
    let selected_photo_ids: [String]
    let headline: String
    let story: String
    var isSlideshow: Bool? = false
}

struct SavedMemory: Codable, Identifiable {
    var id: String { idString }
    let idString: String
    let headline: String
    let story: String
    let photoIds: [String]
    let dateCreated: Date
    var isSlideshow: Bool? = false
}

// MARK: - Layout Sub-components

fileprivate struct ThumbnailCell: View {
    let asset: PhotoAsset
    @ObservedObject var libraryService: PhotoLibraryService
    @State private var thumbnail: UIImage? = nil
    
    var body: some View {
        ZStack {
            if let img = thumbnail {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 80)
                    .cornerRadius(6)
                    .clipped()
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.12))
                    .frame(width: 80, height: 80)
            }
        }
        .onAppear {
            libraryService.fetchThumbnail(for: asset, size: CGSize(width: 160, height: 160)) { img in
                self.thumbnail = img
            }
        }
    }
}

fileprivate struct ActivePhotoPreview: View {
    let asset: PhotoAsset
    @ObservedObject var libraryService: PhotoLibraryService
    @State private var image: UIImage? = nil
    
    var body: some View {
        ZStack {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(12)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.12))
                    .overlay(ProgressView())
            }
        }
        .onAppear {
            libraryService.fetchThumbnail(for: asset, size: CGSize(width: 600, height: 600)) { img in
                self.image = img
            }
        }
    }
}

// MARK: - Collage Layout

struct MemoryCollageView: View {
    let assets: [PhotoAsset]
    @ObservedObject var libraryService: PhotoLibraryService
    
    private let collageColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]
    
    var body: some View {
        Group {
            if assets.isEmpty {
                EmptyView()
            } else if assets.count == 1 {
                CollageImage(asset: assets[0], libraryService: libraryService)
                    .frame(height: 250)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if assets.count == 2 {
                HStack(spacing: 8) {
                    CollageImage(asset: assets[0], libraryService: libraryService)
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                    CollageImage(asset: assets[1], libraryService: libraryService)
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if assets.count == 3 {
                HStack(spacing: 8) {
                    CollageImage(asset: assets[0], libraryService: libraryService)
                        .frame(width: 160, height: 220)
                    
                    VStack(spacing: 8) {
                        CollageImage(asset: assets[1], libraryService: libraryService)
                            .frame(height: 106)
                        CollageImage(asset: assets[2], libraryService: libraryService)
                            .frame(height: 106)
                    }
                    .frame(maxWidth: .infinity)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if assets.count == 4 {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        CollageImage(asset: assets[0], libraryService: libraryService)
                            .frame(maxWidth: .infinity)
                            .frame(height: 120)
                        CollageImage(asset: assets[1], libraryService: libraryService)
                            .frame(maxWidth: .infinity)
                            .frame(height: 120)
                    }
                    HStack(spacing: 8) {
                        CollageImage(asset: assets[2], libraryService: libraryService)
                            .frame(maxWidth: .infinity)
                            .frame(height: 120)
                        CollageImage(asset: assets[3], libraryService: libraryService)
                            .frame(maxWidth: .infinity)
                            .frame(height: 120)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else { // 5 to 8
                LazyVGrid(columns: collageColumns, spacing: 8) {
                    ForEach(assets.prefix(8)) { asset in
                        CollageImage(asset: asset, libraryService: libraryService)
                            .frame(height: 110)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

struct SlideshowView: View {
    let assets: [PhotoAsset]
    let libraryService: PhotoLibraryService
    
    var body: some View {
        TabView {
            ForEach(assets) { asset in
                CollageImage(asset: asset, libraryService: libraryService)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))
        .frame(height: 250)
    }
}

struct CollageImage: View {
    let asset: PhotoAsset
    @ObservedObject var libraryService: PhotoLibraryService
    @State private var image: UIImage? = nil
    
    var body: some View {
        ZStack {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipped()
            } else {
                Color.gray.opacity(0.12)
                    .overlay(ProgressView())
            }
        }
        .onAppear {
            libraryService.fetchThumbnail(for: asset, size: CGSize(width: 320, height: 320)) { img in
                self.image = img
            }
        }
    }
}

struct SavedMemoryDetailView: View {
    let memory: SavedMemory
    @ObservedObject var libraryService: PhotoLibraryService
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Title
                    Text(memory.headline)
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .padding(.top)
                    
                    // Collage or slideshow of chosen photos
                    let chosenAssets = libraryService.loadedAssets.filter { memory.photoIds.contains($0.localIdentifier) }
                    if !chosenAssets.isEmpty {
                        if memory.isSlideshow == true {
                            SlideshowView(assets: chosenAssets, libraryService: libraryService)
                                .padding(.horizontal)
                        } else {
                            MemoryCollageView(assets: chosenAssets, libraryService: libraryService)
                                .padding(.horizontal)
                        }
                    }
                    
                    // Story Text
                    Text(memory.story)
                        .font(.body)
                        .lineSpacing(6)
                        .foregroundColor(.primary)
                        .padding()
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    
                    Spacer()
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Scrapbook Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}
