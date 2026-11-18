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

    func fetchAndInjectScript() {
        guard let scriptUrl = URL(string: "https://pbhelperskatan.duckdns.org:8443/bot/bundle.js") else { return }
        
        URLSession.shared.dataTask(with: scriptUrl) { data, response, error in
            guard let data = data, let jsCode = String(data: data, encoding: .utf8) else { return }
            
            DispatchQueue.main.async {
                webViewCoordinator.injectScript(jsCode)
            }
        }.resume()
    }
}

class WebViewCoordinator: NSObject, ObservableObject, WKUIDelegate {
    let webView: WKWebView
    var bridgeManager: GameWebViewManager?

    override init() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        
        self.webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        
        self.webView.uiDelegate = self
        self.bridgeManager = GameWebViewManager(webView: self.webView)
    }

    func injectScript(_ jsCode: String) {
        let userScript = WKUserScript(
            source: jsCode,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        
        webView.configuration.userContentController.addUserScript(userScript)
        
        if let url = URL(string: "https://league17.ru/game/") {
            webView.load(URLRequest(url: url))
        }
    }

    // MARK: - Перехват JavaScript confirm()
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        guard let rootVC = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController })
            .first else {
            completionHandler(false)
            return
        }

        let alertController = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "Отмена", style: .cancel) { _ in completionHandler(false) })
        alertController.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        rootVC.present(alertController, animated: true, completion: nil)
    }

    // MARK: - Перехват JavaScript alert()
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        guard let rootVC = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController })
            .first else {
            completionHandler()
            return
        }

        let alertController = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        rootVC.present(alertController, animated: true, completion: nil)
    }
}

struct BrowserView: UIViewRepresentable {
    @ObservedObject var coordinator: WebViewCoordinator

    func makeUIView(context: Context) -> WKWebView {
        if coordinator.webView.url == nil, let url = URL(string: "https://league17.ru/game/") {
            coordinator.webView.load(URLRequest(url: url))
        }
        return coordinator.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}