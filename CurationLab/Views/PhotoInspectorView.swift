import SwiftUI
import MapKit

public struct PhotoInspectorView: View {
    let originalAsset: PhotoAsset
    @ObservedObject var libraryService: PhotoLibraryService
    
    @State private var asset: PhotoAsset
    @State private var fullImage: UIImage? = nil
    @State private var isAnalyzing: Bool = false
    @State private var showCopySuccess = false
    
    public init(asset: PhotoAsset, libraryService: PhotoLibraryService) {
        self.originalAsset = asset
        self.libraryService = libraryService
        self._asset = State(initialValue: asset)
    }
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Photo Canvas Card
                ZStack(alignment: .bottomTrailing) {
                    if let img = fullImage {
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 320)
                            .cornerRadius(16)
                            .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
                    } else {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.gray.opacity(0.1))
                            .frame(height: 240)
                            .overlay(ProgressView())
                    }
                    
                    if isAnalyzing {
                        ProgressView()
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .cornerRadius(10)
                            .padding(10)
                    } else if asset.isFullyAnalyzed {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.green)
                            Text("Analyzed")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                        .padding(10)
                    }
                }
                .padding(.horizontal)
                
                // Aesthetics Quality Card
                VStack(alignment: .leading, spacing: 12) {
                    Text("Aesthetics & Curation")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    VStack(spacing: 12) {
                        HStack {
                            Text("Overall Quality")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(String(format: "%.3f", asset.aestheticScore))
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.bold)
                                .foregroundColor(scoreColor(asset.aestheticScore))
                        }
                        
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
                        
                        HStack {
                            Text("Classification")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(asset.isUtility ? "Utility (Receipt/Screenshot)" : "Memorable (Photo/Scene)")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(asset.isUtility ? .orange : .green)
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(14)
                }
                .padding(.horizontal)
                
                // Vision Detections Card
                VStack(alignment: .leading, spacing: 12) {
                    Text("Objects & People Detection")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 12) {
                        // Faces Found Card
                        VStack(spacing: 8) {
                            Image(systemName: "face.smiling.fill")
                                .font(.title)
                                .foregroundColor(.orange)
                            Text("\(asset.faceCount) Faces")
                                .fontWeight(.bold)
                            Text("Detected")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(14)
                        
                        // Humans Found Card
                        VStack(spacing: 8) {
                            Image(systemName: "person.fill")
                                .font(.title)
                                .foregroundColor(.blue)
                            Text("\(asset.humanCount) People")
                                .fontWeight(.bold)
                            Text("Detected")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(14)
                    }
                }
                .padding(.horizontal)
                
                // Scene Tags Card
                VStack(alignment: .leading, spacing: 12) {
                    Text("Scene Classification Tags")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    if asset.tags.isEmpty {
                        Text(isAnalyzing ? "Analyzing scene..." : "No tags detected")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemGroupedBackground))
                            .cornerRadius(14)
                    } else {
                        FlowLayout(spacing: 8) {
                            ForEach(asset.tags) { tag in
                                HStack(spacing: 4) {
                                    Text(tag.name)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Text("\(Int(round(tag.confidence * 100)))%")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.blue.opacity(0.12))
                                .foregroundColor(.blue)
                                .cornerRadius(12)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(14)
                    }
                }
                .padding(.horizontal)
                
                // Text OCR Card
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Extracted OCR Text")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Spacer()
                        if !asset.recognizedText.isEmpty {
                            Button(action: copyTextToPasteboard) {
                                Label(showCopySuccess ? "Copied" : "Copy Text", systemImage: showCopySuccess ? "checkmark.circle.fill" : "doc.on.doc")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    
                    if asset.recognizedText.isEmpty {
                        Text(isAnalyzing ? "Reading text..." : "No text detected in image")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemGroupedBackground))
                            .cornerRadius(14)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(asset.recognizedText, id: \.self) { line in
                                Text(line)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(14)
                    }
                }
                .padding(.horizontal)
                
                // Map/Location Card
                if let location = asset.location {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("GPS Location")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        MapSection(coordinate: location.coordinate)
                            .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
                    }
                    .padding(.horizontal)
                }
                
                // EXIF Metadata Inspector
                VStack(alignment: .leading, spacing: 12) {
                    Text("Camera & Exif Specs")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    VStack(spacing: 0) {
                        if asset.exifMetadata.isEmpty {
                            Text("Reading EXIF parameters...")
                                .foregroundColor(.secondary)
                                .padding()
                                .frame(maxWidth: .infinity)
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
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(14)
                }
                .padding(.horizontal)
                .padding(.bottom, 30)
            }
            .padding(.vertical)
        }
        .navigationTitle("Photo Inspector")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
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
        // 1. Fetch EXIF metadata
        libraryService.fetchExifMetadata(for: originalAsset) { meta in
            DispatchQueue.main.async {
                self.asset.exifMetadata = meta
                
                // 2. Perform Apple Vision calculations (which caches internally)
                self.isAnalyzing = true
                VisionAnalysisService.shared.analyzeAsset(self.asset, libraryService: libraryService) { analyzed in
                    self.asset = analyzed
                    self.isAnalyzing = false
                }
            }
        }
    }
    
    private func copyTextToPasteboard() {
        let fullText = asset.recognizedText.joined(separator: "\n")
        UIPasteboard.general.string = fullText
        withAnimation {
            showCopySuccess = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                showCopySuccess = false
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

fileprivate struct MapSection: View {
    let coordinate: CLLocationCoordinate2D
    @State private var region: MKCoordinateRegion
    
    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
        self._region = State(initialValue: MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        ))
    }
    
    var body: some View {
        Map(coordinateRegion: $region, annotationItems: [MapPinItem(coordinate: coordinate)]) { item in
            MapMarker(coordinate: item.coordinate, tint: .red)
        }
        .frame(height: 180)
        .cornerRadius(14)
    }
}

fileprivate struct MapPinItem: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

/// A simple flow layout wrapper for Swift
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
