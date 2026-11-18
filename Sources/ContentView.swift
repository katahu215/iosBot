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
        guard let scriptUrl = URL(string: "https://ваш-сервер.com/path/to/bundle.js") else { return }
        
        URLSession.shared.dataTask(with: scriptUrl) { data, response, error in
            guard let data = data, let jsCode = String(data: data, encoding: .utf8) else { return }
            
            DispatchQueue.main.async {
                webViewCoordinator.injectScript(jsCode)
            }
        }.resume()
    }
}

// Координатор управляет WKWebView и обрабатывает JS-диалоги (alert, confirm)
class WebViewCoordinator: NSObject, ObservableObject, WKUIDelegate {
    let webView: WKWebView

    override init() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        
        // Создаем WKWebView с конфигурацией
        self.webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        
        // Обязательно назначаем делегат UI, чтобы ловить confirm/alert
        self.webView.uiDelegate = self
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
        
        // Находим текущий активный контроллер экрана для показа нативного алерта
        guard let rootVC = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController })
            .first else {
            completionHandler(false)
            return
        }

        let alertController = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        
        alertController.addAction(UIAlertAction(title: "Отмена", style: .cancel) { _ in
            completionHandler(false) // Возвращает false в JavaScript при нажатии "Отмена"
        })
        
        alertController.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completionHandler(true) // Возвращает true в JavaScript при нажатии "OK"
        })
        
        rootVC.present(alertController, animated: true, completion: nil)
    }

    // MARK: - Перехват JavaScript alert() (на всякий случай)
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        guard let rootVC = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController })
            .first else {
            completionHandler()
            return
        }

        let alertController = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completionHandler()
        })
        
        rootVC.present(alertController, animated: true, completion: nil)
    }
}

// Обертка WKWebView для SwiftUI
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