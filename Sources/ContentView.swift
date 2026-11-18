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
        // Подставлена ваша реальная ссылка на сервер
        guard let scriptUrl = URL(string: "https://pbhelperskatan.duckdns.org:8443/bot/bundle.js") else { return }
        
        URLSession.shared.dataTask(with: scriptUrl) { data, response, error in
            guard let data = data, let jsCode = String(data: data, encoding: .utf8) else { return }
            
            DispatchQueue.main.async {
                webViewCoordinator.injectScript(jsCode)
            }
        }.resume()
    }
}

// Координатор управляет WKWebView, JS-диалогами и мостом KotlinBridge
class WebViewCoordinator: NSObject, ObservableObject, WKUIDelegate, WKScriptMessageHandler {
    let webView: WKWebView

    override init() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        
        // Регистрируем мост под именем KotlinBridge для связи с bundle.js
        config.userContentController.add(self, name: "KotlinBridge")
        
        self.webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        
        // Назначаем делегат UI для перехвата confirm/alert
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

    // MARK: - Обработка моста KotlinBridge (JS -> Swift)
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "KotlinBridge" {
            guard let array = message.body as? [Any],
                  let selector = array.count > 0 ? array[0] as? String : nil,
                  let index = array.count > 1 ? array[1] as? Int : nil,
                  let callbackId = array.count > 2 ? array[2] as? String : nil else {
                return
            }

            // Выполняем поиск элемента и клик на странице игры
            performClick(selector: selector, index: index) { success in
                // Возвращаем результат в JS-функцию win.__resolveKotlinAction
                let jsResponse = "window.__resolveKotlinAction('\(callbackId)', \(success));"
                self.webView.evaluateJavaScript(jsResponse, completionHandler: nil)
            }
        }
    }

    private func performClick(selector: String, index: Int, completion: @escaping (Bool) -> Void) {
        let jsFindAndClick = """
        (function() {
            const elements = document.querySelectorAll('\(selector)');
            if (elements.length > \(index)) {
                elements[\(index)].click();
                return true;
            }
            return false;
        })();
        """
        
        webView.evaluateJavaScript(jsFindAndClick) { result, error in
            let success = (result as? Bool) ?? false
            completion(success)
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
        
        alertController.addAction(UIAlertAction(title: "Отмена", style: .cancel) { _ in
            completionHandler(false)
        })
        
        alertController.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completionHandler(true)
        })
        
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