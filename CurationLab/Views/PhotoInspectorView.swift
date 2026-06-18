import SwiftUI
import MapKit

public struct PhotoInspectorView: View {
    let originalAsset: PhotoAsset
    @ObservedObject var libraryService: PhotoLibraryService
    
    @State private var asset: PhotoAsset
    @State private var fullImage: UIImage? = nil
    @State private var isAnalyzing: Bool = false
    
    public init(asset: PhotoAsset, libraryService: PhotoLibraryService) {
        self.originalAsset = asset
        self.libraryService = libraryService
        self._asset = State(initialValue: asset)
    }
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Photo Canvas
                ZStack {
                    if let img = fullImage {
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 320)
                            .cornerRadius(16)
                            .shadow(radius: 6)
                    } else {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.gray.opacity(0.12))
                            .frame(height: 240)
                            .overlay(
                                ProgressView()
                            )
                    }
                }
                .padding(.horizontal)
                
                // Curation Scores Card
                VStack(alignment: .leading, spacing: 14) {
                    Text("Apple Vision Curation API")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    VStack(spacing: 12) {
                        HStack {
                            Text("Aesthetic Score")
                                .font(.subheadline)
                            Spacer()
                            Text(String(format: "%.3f", asset.aestheticScore))
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.bold)
                                .foregroundColor(scoreColor(asset.aestheticScore))
                        }
                        
                        // Score progress bar (-1 to 1 scaled to 0 to 1)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.secondary.opacity(0.2))
                                    .frame(height: 8)
                                
                                Capsule()
                                    .fill(scoreColor(asset.aestheticScore))
                                    .frame(width: max(0, CGFloat((asset.aestheticScore + 1.0) / 2.0) * geo.size.width), height: 8)
                            }
                        }
                        .frame(height: 8)
                        
                        Divider()
                            .padding(.vertical, 4)
                        
                        HStack {
                            Text("Curation Type")
                                .font(.subheadline)
                            Spacer()
                            Text(asset.isUtility ? "Utility (Exclude)" : "Memorable (Include)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(asset.isUtility ? .orange : .green)
                        }
                        
                        Text("Apple's on-device aesthetics score evaluates blur, lighting, exposure, and composition (-1 to 1). 'Utility' identifies screenshots, barcodes, receipts, and documents to filter them out.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(14)
                    .padding(.horizontal)
                }
                
                // Local Image Tags
                VStack(alignment: .leading, spacing: 10) {
                    Text("Auto-Generated Scene Tags")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    if asset.tags.isEmpty {
                        Text("No tags detected")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(14)
                            .padding(.horizontal)
                    } else {
                        FlowLayout(spacing: 8) {
                            ForEach(asset.tags) { tag in
                                HStack(spacing: 4) {
                                    Text(tag.name)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Text("\(Int(round(tag.confidence * 100)))%")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.blue.opacity(0.12))
                                .foregroundColor(.blue)
                                .cornerRadius(12)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                
                // EXIF Metadata Inspector
                VStack(alignment: .leading, spacing: 12) {
                    Text("Raw EXIF Metadata")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    VStack(spacing: 0) {
                        if asset.exifMetadata.isEmpty {
                            Text("Reading EXIF parameters...")
                                .foregroundColor(.secondary)
                                .padding()
                        } else {
                            ForEach(asset.exifMetadata.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                                HStack {
                                    Text(key)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(value)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal)
                                
                                if key != asset.exifMetadata.sorted(by: { $0.key < $1.key }).last?.key {
                                    Divider()
                                }
                            }
                        }
                    }
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(14)
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Photo Inspector")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadImage()
            loadMetadataAndVision()
        }
    }
    
    private func loadImage() {
        libraryService.fetchFullImage(for: originalAsset) { img in
            self.fullImage = img
        }
    }
    
    private func loadMetadataAndVision() {
        // 1. Fetch EXIF
        libraryService.fetchExifMetadata(for: originalAsset) { meta in
            self.asset.exifMetadata = meta
            
            // 2. Perform local Vision calculations
            self.isAnalyzing = true
            VisionAnalysisService.shared.analyzeAsset(self.asset, libraryService: libraryService) { analyzed in
                self.asset = analyzed
                self.isAnalyzing = false
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

/// A simple flow layout wrapper for Swift 16.0/17.0
fileprivate struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        var height: CGFloat = 0
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var maxRowHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > width {
                currentX = 0
                currentY += maxRowHeight + spacing
                maxRowHeight = 0
            }
            
            maxRowHeight = max(maxRowHeight, size.height)
            currentX += size.width + spacing
        }
        
        height = currentY + maxRowHeight
        return CGSize(width: width, height: height)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = bounds.width
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var maxRowHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.minX + width {
                currentX = bounds.minX
                currentY += maxRowHeight + spacing
                maxRowHeight = 0
            }
            
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: .unspecified)
            maxRowHeight = max(maxRowHeight, size.height)
            currentX += size.width + spacing
        }
    }
}
