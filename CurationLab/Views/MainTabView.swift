import SwiftUI

public struct MainTabView: View {
    @ObservedObject var libraryService: PhotoLibraryService
    @State private var selectedTab = 0
    
    public init(libraryService: PhotoLibraryService) {
        self.libraryService = libraryService
    }
    
    public var body: some View {
        TabView(selection: $selectedTab) {
            AppleAnalysisPageView(libraryService: libraryService)
                .tabItem {
                    Label("Apple Tools", systemImage: "sparkles")
                }
                .tag(0)
            
            LLMAnalysisPageView(libraryService: libraryService)
                .tabItem {
                    Label("LLM Lab", systemImage: "brain.head.profile")
                }
                .tag(1)
        }
        .tint(.blue)
    }
}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView(libraryService: PhotoLibraryService())
    }
}
