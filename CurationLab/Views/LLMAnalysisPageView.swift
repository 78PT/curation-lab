import SwiftUI

public struct LLMAnalysisPageView: View {
    @ObservedObject var libraryService: PhotoLibraryService
    
    // API Keys and Configuration
    @AppStorage("gemini_api_key") private var geminiApiKey: String = ""
    @AppStorage("groq_api_key") private var groqApiKey: String = ""
    @AppStorage("llm_selected_provider") private var selectedProviderRaw: String = ModelProvider.gemini.rawValue
    @AppStorage("prompt_history") private var promptHistoryJSON: String = "[]"
    
    @State private var selectedAssetIds: Set<String> = []
    @State private var customPrompt = "Pick the best 2 photos that represent this day. Explain your reasoning."
    @State private var isExecuting = false
    @State private var responseText: String? = nil
    @State private var errorText: String? = nil
    @State private var showCopySuccess = false
    @State private var isConfigExpanded = true
    
    private var selectedProvider: ModelProvider {
        ModelProvider(rawValue: selectedProviderRaw) ?? .gemini
    }
    
    private var history: [String] {
        getPromptHistory()
    }
    
    private var hasApiKey: Bool {
        switch selectedProvider {
        case .gemini:
            return !geminiApiKey.isEmpty || !getDefaultKey(for: "GeminiAPIKey").isEmpty
        case .groq:
            return !groqApiKey.isEmpty || !getDefaultKey(for: "GroqAPIKey").isEmpty
        }
    }
    
    private func getDefaultKey(for name: String) -> String {
        guard let path = Bundle.main.path(forResource: "Keys", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) as? [String: Any],
              let key = dict[name] as? String else {
            return ""
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
                VStack(spacing: 20) {
                    
                    // 1. API Configuration Section
                    VStack(alignment: .leading, spacing: 10) {
                        Button(action: {
                            withAnimation(.easeInOut) {
                                isConfigExpanded.toggle()
                            }
                        }) {
                            HStack {
                                Label("API Configuration", systemImage: "key.fill")
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
                    .padding(.top)
                    
                    // 2. Photo Multi-Selector
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Select Photos (\(selectedAssetIds.count) selected)")
                                .font(.headline)
                            Spacer()
                            
                            if !selectedAssetIds.isEmpty {
                                Button("Clear Selection") {
                                    withAnimation { selectedAssetIds.removeAll() }
                                }
                                .font(.caption)
                                .foregroundColor(.red)
                            }
                        }
                        .padding(.horizontal)
                        
                        // Horizontal scroll showing currently selected photos
                        if !selectedAssetIds.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(libraryService.loadedAssets.filter { selectedAssetIds.contains($0.localIdentifier) }) { asset in
                                        SelectedPhotoCell(
                                            asset: asset,
                                            selectedAssetIds: $selectedAssetIds,
                                            libraryService: libraryService
                                        )
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        
                        Divider().padding(.horizontal)
                        
                        // Lazy grid of all loaded photos to select/deselect
                        LazyVGrid(columns: gridColumns, spacing: 6) {
                            ForEach(libraryService.loadedAssets) { asset in
                                SelectablePhotoCell(
                                    asset: asset,
                                    selectedAssetIds: $selectedAssetIds,
                                    libraryService: libraryService
                                )
                            }
                            
                            // Bottom-scrolled listener
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
                                .padding(.vertical, 8)
                        }
                    }
                    .padding(.vertical, 12)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .cornerRadius(14)
                    .padding(.horizontal)
                    
                    // 3. Prompt Setup
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Prompt Details")
                                .font(.headline)
                            Spacer()
                            
                            Menu {
                                Button("Analyze Travel Event") {
                                    customPrompt = "Pick the top 2 photos that represent this day. Explain your reasoning."
                                }
                                Button("Evaluate Visual Quality") {
                                    customPrompt = "Evaluate these photos for lighting, sharpness, and composition. Identify any blurry or badly framed images."
                                }
                                Button("Summarize & Caption") {
                                    customPrompt = "Write a short summary caption for these photos combined into an album entry."
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "list.bullet.rectangle.portrait")
                                    Text("Presets")
                                }
                                .font(.caption)
                                .fontWeight(.semibold)
                            }
                        }
                        .padding(.horizontal)
                        
                        TextEditor(text: $customPrompt)
                            .font(.subheadline)
                            .frame(minHeight: 80, maxHeight: 120)
                            .padding(8)
                            .background(Color(uiColor: .systemGroupedBackground))
                            .cornerRadius(8)
                            .padding(.horizontal)
                        
                        // History of old prompts with delete option
                        if !history.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Recently Used Prompts")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal)
                                
                                ForEach(history, id: \.self) { hist in
                                    HStack {
                                        Button(action: {
                                            customPrompt = hist
                                        }) {
                                            Text(hist)
                                                .font(.caption)
                                                .foregroundColor(.blue)
                                                .lineLimit(1)
                                                .multilineTextAlignment(.leading)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        
                                        Button(action: {
                                            deletePromptFromHistory(hist)
                                        }) {
                                            Image(systemName: "trash")
                                                .font(.caption2)
                                                .foregroundColor(.red)
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                    .padding(.horizontal)
                                    .padding(.vertical, 4)
                                    .background(Color(uiColor: .systemGroupedBackground).opacity(0.4))
                                    .cornerRadius(6)
                                    .padding(.horizontal)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 12)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .cornerRadius(14)
                    .padding(.horizontal)
                    
                    // 4. Action Execution
                    VStack {
                        if isExecuting {
                            VStack(spacing: 8) {
                                ProgressView()
                                Text("Encoding images & querying \(selectedProvider.rawValue)...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        } else {
                            Button(action: executeLLMRequest) {
                                HStack {
                                    Image(systemName: "paperplane.fill")
                                    Text("Send to \(selectedProvider.rawValue)")
                                        .fontWeight(.bold)
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
                    
                    // 5. Outputs & Responses
                    if let error = errorText {
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
                    
                    if let response = responseText {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Model Response")
                                    .font(.headline)
                                Spacer()
                                Button(action: copyResponseToPasteboard) {
                                    Label(showCopySuccess ? "Copied" : "Copy", systemImage: showCopySuccess ? "checkmark.circle.fill" : "doc.on.doc")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                }
                            }
                            
                            Text(response)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(uiColor: .secondarySystemGroupedBackground))
                                .cornerRadius(12)
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 30)
                    }
                }
            }
            .navigationTitle("LLM Analysis")
            .background(Color(uiColor: .systemGroupedBackground))
        }
    }
    
    // MARK: - Prompt History Management
    
    private func getPromptHistory() -> [String] {
        guard let data = promptHistoryJSON.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
    
    private func savePromptToHistory(_ promptString: String) {
        var history = getPromptHistory()
        history.removeAll { $0 == promptString }
        history.insert(promptString, at: 0)
        let limited = Array(history.prefix(5)) // Keep last 5 prompts
        if let data = try? JSONEncoder().encode(limited),
           let jsonStr = String(data: data, encoding: .utf8) {
            promptHistoryJSON = jsonStr
        }
    }
    
    private func deletePromptFromHistory(_ promptString: String) {
        var history = getPromptHistory()
        history.removeAll { $0 == promptString }
        if let data = try? JSONEncoder().encode(history),
           let jsonStr = String(data: data, encoding: .utf8) {
            promptHistoryJSON = jsonStr
        }
    }
    
    // MARK: - API Query Trigger
    
    private func executeLLMRequest() {
        let defaultKey = selectedProvider == .gemini ? getDefaultKey(for: "GeminiAPIKey") : getDefaultKey(for: "GroqAPIKey")
        let enteredKey = selectedProvider == .gemini ? geminiApiKey : groqApiKey
        let key = enteredKey.isEmpty ? defaultKey : enteredKey
        
        guard !key.isEmpty else { return }
        
        isExecuting = true
        responseText = nil
        errorText = nil
        
        let selectedAssets = libraryService.loadedAssets.filter { selectedAssetIds.contains($0.localIdentifier) }
        
        LLMService.shared.runPrompt(
            provider: selectedProvider,
            apiKey: key,
            prompt: customPrompt,
            assets: selectedAssets,
            libraryService: libraryService
        ) { response in
            isExecuting = false
            if response.contains("Error") || response.contains("Network Error") {
                errorText = response
            } else {
                responseText = response
                savePromptToHistory(customPrompt)
            }
        }
    }
    
    private func copyResponseToPasteboard() {
        guard let response = responseText else { return }
        UIPasteboard.general.string = response
        withAnimation {
            showCopySuccess = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                showCopySuccess = false
            }
        }
    }
}

// MARK: - Subviews

fileprivate struct SelectedPhotoCell: View {
    let asset: PhotoAsset
    @Binding var selectedAssetIds: Set<String>
    @ObservedObject var libraryService: PhotoLibraryService
    @State private var thumbnail: UIImage? = nil
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let img = thumbnail {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .cornerRadius(8)
                    .clipped()
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.12))
                    .frame(width: 60, height: 60)
            }
            
            Button(action: {
                withAnimation {
                    _ = selectedAssetIds.remove(asset.localIdentifier)
                }
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .background(Color.white.clipShape(Circle()))
            }
            .offset(x: 5, y: -5)
        }
        .onAppear {
            libraryService.fetchThumbnail(for: asset, size: CGSize(width: 120, height: 120)) { img in
                self.thumbnail = img
            }
        }
    }
}

fileprivate struct SelectablePhotoCell: View {
    let asset: PhotoAsset
    @Binding var selectedAssetIds: Set<String>
    @ObservedObject var libraryService: PhotoLibraryService
    @State private var thumbnail: UIImage? = nil
    
    var isSelected: Bool {
        selectedAssetIds.contains(asset.localIdentifier)
    }
    
    var body: some View {
        Button(action: {
            if isSelected {
                selectedAssetIds.remove(asset.localIdentifier)
            } else {
                selectedAssetIds.insert(asset.localIdentifier)
            }
        }) {
            ZStack(alignment: .topTrailing) {
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
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .white)
                    .padding(3)
                    .background(Color.black.opacity(isSelected ? 0.0 : 0.3).clipShape(Circle()))
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
