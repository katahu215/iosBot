import SwiftUI
import WebKit

struct ContentView: View {
    @State private var webViewCoordinator = WebViewCoordinator()

    var body: some View {
        BrowserView(coordinator: webViewCoordinator)
            .ignoresSafeArea()
    }
}

struct BrowserView: UIViewRepresentable {
    @ObservedObject var coordinator: WebViewCoordinator

    func makeUIView(context: Context) -> WKWebView {
        coordinator.loadGame()
        return coordinator.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}