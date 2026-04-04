import SwiftUI

@main
struct TeamsAutoRecorderApp: App {
    var body: some Scene {
        WindowGroup("TeamsAutoRecorder") {
            ContentView()
                .frame(minWidth: 480, minHeight: 280)
        }
    }
}

private struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("TeamsAutoRecorder MVP")
                .font(.title2)
            Text("Use the menu bar app flow in future iterations.")
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }
}
