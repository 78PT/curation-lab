import SwiftUI
import Photos

public struct OnboardingView: View {
    @ObservedObject var libraryService: PhotoLibraryService
    
    public init(libraryService: PhotoLibraryService) {
        self.libraryService = libraryService
    }
    
    public var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
                Spacer()
                
                Image(systemName: "photo.stack.fill")
                    .font(.system(size: 72))
                    .foregroundColor(.blue)
                    .shadow(radius: 4)
                
                VStack(spacing: 12) {
                    Text("CurationLab")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    
                    Text("Event Clustering & Metadata Experiment Tool")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                
                VStack(alignment: .leading, spacing: 16) {
                    FeatureItem(icon: "clock.badge.checkmark", title: "Smart Event Clustering", description: "Groups library photos into distinct events automatically based on spatial-temporal limits.")
                    
                    FeatureItem(icon: "sparkles", title: "Apple Curation Metrics", description: "Retrieves hidden aesthetic quality scores and screenshot detection from Apple's Vision framework.")
                    
                    FeatureItem(icon: "brain.head.profile", title: "Gemini LLM Curation", description: "Passes photo metadata and preview frames to Gemini to test and evaluate automated memory selection.")
                }
                .padding(.horizontal, 30)
                .padding(.vertical, 20)
                
                Spacer()
                
                VStack(spacing: 16) {
                    if libraryService.permissionStatus == .notDetermined {
                        Button(action: {
                            libraryService.requestPermission()
                        }) {
                            Text("Grant Photo Library Access")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .background(Color.blue)
                                .cornerRadius(12)
                        }
                    } else if libraryService.permissionStatus == .denied || libraryService.permissionStatus == .restricted {
                        VStack(spacing: 12) {
                            Text("Access is Denied")
                                .font(.headline)
                                .foregroundColor(.red)
                            
                            Text("Please enable Photo Access in Settings to proceed with calculations.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            
                            Button(action: {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }) {
                                Text("Open Settings")
                                    .font(.headline)
                                    .foregroundColor(.blue)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 50)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.blue, lineWidth: 1.5)
                                    )
                            }
                        }
                    } else {
                        VStack(spacing: 10) {
                            ProgressView()
                            Text("Scanning Photo Library & Clustering...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
    }
}

fileprivate struct FeatureItem: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 32, height: 32)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView(libraryService: PhotoLibraryService())
    }
}
