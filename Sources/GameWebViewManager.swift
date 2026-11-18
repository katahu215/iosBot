import WebKit
import UIKit

class WebViewCoordinator: NSObject, ObservableObject, WKUIDelegate, WKNavigationDelegate {
    let webView: WKWebView

    override init() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        
        self.webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        
        self.webView.uiDelegate = self
        self.webView.navigationDelegate = self
    }

    func loadGame() {
        if webView.url == nil, let url = URL(string: "https://league17.ru/game/") {
            webView.load(URLRequest(url: url))
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        fetchAndInjectScript()
    }

    func fetchAndInjectScript() {
        guard let scriptUrl = URL(string: "https://pbhelperskatan.duckdns.org:8443/bot/bundle.js") else { return }
        
        URLSession.shared.dataTask(with: scriptUrl) { data, response, error in
            guard let data = data, let jsCode = String(data: data, encoding: .utf8) else { return }
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                let setupScript = """
                (function() {
                    window.sessionStore = window.sessionStore || {};
                    window.sessionStore.isMobile = true;

                    if (!document.getElementById('ios-debug-console')) {
                        const consoleDiv = document.createElement('div');
                        consoleDiv.id = 'ios-debug-console';
                        consoleDiv.style.position = 'fixed';
                        consoleDiv.style.bottom = '0';
                        consoleDiv.style.left = '0';
                        consoleDiv.style.width = '100%';
                        consoleDiv.style.maxHeight = '150px';
                        consoleDiv.style.overflowY = 'auto';
                        consoleDiv.style.backgroundColor = 'rgba(0, 0, 0, 0.85)';
                        consoleDiv.style.color = '#00ff00';
                        consoleDiv.style.fontSize = '10px';
                        consoleDiv.style.zIndex = '999999';
                        consoleDiv.style.padding = '6px';
                        consoleDiv.style.pointerEvents = 'none';
                        document.body.appendChild(consoleDiv);

                        const logToScreen = (msg, color = '#00ff00') => {
                            const p = document.createElement('div');
                            p.style.color = color;
                            p.textContent = msg;
                            consoleDiv.appendChild(p);
                            consoleDiv.scrollTop = consoleDiv.scrollHeight;
                        };

                        window.addEventListener('error', (e) => logToScreen('ERR: ' + e.message, '#ff4444'));
                        
                        const originalLog = console.log;
                        console.log = (...args) => {
                            originalLog(...args);
                            logToScreen(args.join(' '));
                        };
                        
                        const originalError = console.error;
                        console.error = (...args) => {
                            originalError(...args);
                            logToScreen('ERR: ' + args.join(' '), '#ff4444');
                        };
                    }
                })();
                """
                
                self.webView.evaluateJavaScript(setupScript) { _, _ in
                    self.webView.evaluateJavaScript(jsCode, completionHandler: { _, error in
                        if let error = error {
                            print("❌ Ошибка выполнения bundle.js: \(error)")
                        } else {
                            print("✅ bundle.js успешно инъектирован!")
                        }
                    })
                }
            }
        }.resume()
    }

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