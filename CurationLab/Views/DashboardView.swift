import SwiftUI

public struct DashboardView: View {
    @ObservedObject var libraryService: PhotoLibraryService
    @State private var showSettings = false
    
    public init(libraryService: PhotoLibraryService) {
        self.libraryService = libraryService
    }
    
    public var body: some View {
        NavigationStack {
            Group {
                if libraryService.isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Running clustering algorithms...")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    }
                } else if libraryService.eventClusters.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 64))
                            .foregroundColor(.secondary)
                        Text("No Events Detected")
                            .font(.headline)
                        Text("Add more photos to your device library or adjust clustering thresholds in Settings.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                } else {
                    List(libraryService.eventClusters) { cluster in
                        NavigationLink(destination: EventDetailView(cluster: cluster, libraryService: libraryService)) {
                            EventRow(cluster: cluster, libraryService: libraryService)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("CurationLab")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showSettings = true
                    }) {
                        Image(systemName: "slider.horizontal.3")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(libraryService: libraryService)
            }
        }
    }
}

fileprivate struct EventRow: View {
    let cluster: EventCluster
    @ObservedObject var libraryService: PhotoLibraryService
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(cluster.name)
                        .font(.headline)
                        .fontWeight(.bold)
                    
                    Text(cluster.locationName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text("\(cluster.assets.count) Photos")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(6)
            }
            
            // Photo row preview
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(cluster.assets.prefix(6)) { asset in
                        ThumbnailPreview(asset: asset, libraryService: libraryService)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(14)
        .shadow(color: Color.black.opacity(0.04), radius: 5, x: 0, y: 2)
    }
}

fileprivate struct ThumbnailPreview: View {
    let asset: PhotoAsset
    @ObservedObject var libraryService: PhotoLibraryService
    
    @State private var thumbnail: UIImage? = nil
    @State private var score: Float = 0.0
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
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
            
            // Score overlay badge if analyzed
            if score != 0.0 {
                Text(String(format: "%.1f", score))
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(scoreColor(score))
                    .foregroundColor(.white)
                    .cornerRadius(4)
                    .padding(4)
            }
        }
        .onAppear {
            libraryService.fetchThumbnail(for: asset, size: CGSize(width: 160, height: 160)) { img in
                self.thumbnail = img
            }
            
            // Extract the score if already calculated, otherwise run a fast calculation
            if asset.isAestheticAnalyzed {
                self.score = asset.aestheticScore
            } else {
                VisionAnalysisService.shared.analyzeAsset(asset, libraryService: libraryService) { analyzed in
                    self.score = analyzed.aestheticScore
                }
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

struct DashboardView_Previews: PreviewProvider {
    static var previews: some View {
        DashboardView(libraryService: PhotoLibraryService())
    }
}
