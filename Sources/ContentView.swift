import SwiftUI
import WebKit

struct ContentView: View {
    var body: some View {
        WebView(url: URL(string: "https://league17.ru/game/")!)
            .edgesIgnoringSafeArea(.all) // Растягиваем браузер на весь экран, включая «челку» и «остров»
    }
}

// Обертка для интеграции WKWebView в SwiftUI
struct WebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let prefs = WKWebviewPreferences()
        prefs.isFraudulentWebsiteWarningEnabled = false
        
        let config = WKWebViewConfiguration()
        config.preferences = prefs
        
        // Дополнительные параметры для комфортной игры в браузере
        config.allowsInlineMediaPlayback = true
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = true
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let request = URLRequest(url: url)
        webView.load(request)
    }
}