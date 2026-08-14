import SwiftUI

@main
struct SupaNotesSwiftApp: App {
  var body: some Scene {
    WindowGroup {
      ContentView()
        .onAppear {
          DispatchQueue.global(qos: .userInitiated).async {
            runAutocompletePipelineFromSample()
          }
        }
    }
  }
}
