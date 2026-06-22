import SwiftUI
import Photos

public struct AppleAnalysisPageView: View {
    @ObservedObject var libraryService: PhotoLibraryService
    @State private var showSettings = false
    
    private let columns = [
        GridItem(.adaptive(minimum: 90, maximum: 110), spacing: 8)
    ]
    
    public init(libraryService: PhotoLibraryService) {
        self.libraryService = libraryService
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header card
                    VStack(alignment: .leading, spacing: 8) {
                        Text("On-Device Vision Analysis")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("This page runs local Apple framework calculations (Vision, ImageIO) on individual photos to showcase on-device capabilities.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    .padding(.top)
                    
                    if libraryService.loadedAssets.isEmpty && libraryService.isLoading {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Scanning Photo Library...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 250)
                    } else if libraryService.loadedAssets.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text("No Photos Found")
                                .font(.headline)
                            Text("Please ensure you have granted photo library access.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                        .frame(maxWidth: .infinity, minHeight: 250)
                    } else {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(libraryService.loadedAssets) { asset in
                                NavigationLink(destination: PhotoInspectorView(asset: asset, libraryService: libraryService)) {
                                    GridPhotoCell(asset: asset, libraryService: libraryService)
                                }
                            }
                            
                            // Infinite scrolling trigger
                            if !libraryService.isLoading {
                                Color.clear
                                    .frame(height: 40)
                                    .onAppear {
                                        libraryService.loadNextBatch()
                                    }
                            }
                        }
                        .padding(.horizontal)
                        
                        if libraryService.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical)
                        }
                    }
                }
            }
            .navigationTitle("Apple Analysis")
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    albumPickerMenu
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showSettings = true
                    }) {
                        Image(systemName: "slider.horizontal.3")
                            .imageScale(.large)
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(libraryService: libraryService)
            }
        }
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

fileprivate struct GridPhotoCell: View {
    let asset: PhotoAsset
    @ObservedObject var libraryService: PhotoLibraryService
    @State private var thumbnail: UIImage? = nil
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let img = thumbnail {
                Image(uiImage: img)
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
            
            // Icon indicators
            HStack(spacing: 2) {
                if asset.isFullyAnalyzed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.green)
                        .background(Color.white.clipShape(Circle()))
                }
                
                if asset.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.yellow)
                }
            }
            .padding(4)
        }
        .onAppear {
            libraryService.fetchThumbnail(for: asset, size: CGSize(width: 200, height: 200)) { img in
                self.thumbnail = img
            }
        }
    }
}
