import SwiftUI
import WebKit

struct ContentView: View {
    @State private var webViewCoordinator = WebViewCoordinator()

    var body: some View {
        BrowserView(coordinator: webViewCoordinator)
            .edgesIgnoringSafeArea(.all)
            .onAppear {
                fetchAndInjectScript()
            }
    }

    // Скачиваем ваш bundle.js с сервера
    func fetchAndInjectScript() {
        guard let scriptUrl = URL(string: "https://pbhelperskatan.duckdns.org:8443/bot/bundle.js") else { return }
        
        URLSession.shared.dataTask(with: scriptUrl) { data, response, error in
            guard let data = data, let jsCode = String(data: data, encoding: .utf8) else { return }
            
            // Передаем полученный код в координатор веб-вью
            DispatchQueue.main.async {
                webViewCoordinator.injectScript(jsCode)
            }
        }.resume()
    }
}

class WebViewCoordinator: ObservableObject {
    let webView: WKWebView = {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        return WKWebView(frame: .zero, configuration: config)
    }()

    func injectScript(_ jsCode: String) {
        // Создаем пользовательский скрипт, который внедрится в страницу
        let userScript = WKUserScript(
            source: jsCode,
            injectionTime: .atDocumentEnd, // Выполнить сразу после загрузки DOM (или .atDocumentStart)
            forMainFrameOnly: true
        )
        
        // Добавляем скрипт в конфигуратор контента
        webView.configuration.userContentController.addUserScript(userScript)
        
        // Загружаем саму игру
        if let url = URL(string: "https://league17.ru/game/") {
            webView.load(URLRequest(url: url))
        }
    }
}

// Обертка WKWebView для SwiftUI
struct BrowserView: UIViewRepresentable {
    @ObservedObject var coordinator: WebViewCoordinator

    func makeUIView(context: Context) -> WKWebView {
        // Первоначальная загрузка страницы, если скрипт еще не скачался
        if coordinator.webView.url == nil, let url = URL(string: "https://league17.ru/game/") {
            coordinator.webView.load(URLRequest(url: url))
        }
        return coordinator.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}