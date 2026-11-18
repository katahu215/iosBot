import WebKit
import UIKit

class GameWebViewManager: NSObject, WKScriptMessageHandler {
    private weak var webView: WKWebView?

    init(webView: WKWebView) {
        self.webView = webView
        super.init()
        webView.configuration.userContentController.add(self, name: "iosBridge")
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "iosBridge" {
            guard let dict = message.body as? [String: Any],
                  let selector = dict["selector"] as? String,
                  let index = dict["index"] as? Int,
                  let callbackId = dict["callbackId"] as? String else {
                logToScreen(text: "⚠️ [Bridge] Ошибка: Неверный формат JSON", color: "#ffaa00")
                return
            }

            logToScreen(text: "🌉 [Bridge IN] Запрос клика: '\(selector)' [индекс: \(index)]", color: "#00ffff")

            // Шаг 1. Находим координаты элемента через JS
            findCoordinates(selector: selector, index: index) { [weak self] point in
                guard let self = self, let point = point, let webView = self.webView else {
                    self?.logToScreen(text: "❌ Элемент не найден: \(selector)[\(index)]", color: "#ff4444")
                    self?.sendCallback(callbackId: callbackId, success: false)
                    return
                }

                self.logToScreen(text: "✅ Координаты найдены: x=\(Int(point.x)), y=\(Int(point.y))", color: "#00ff00")

                // Шаг 2. Выполняем нативную активацию по координатам через WKWebView
                DispatchQueue.main.async {
                    self.executeNativeClick(at: point, in: webView) { success in
                        self.logToScreen(text: "🎯 Статус выполнения: \(success ? "Успех" : "Ошибка")", color: success ? "#00ff00" : "#ff4444")
                        self.sendCallback(callbackId: callbackId, success: success)
                    }
                }
            }
        }
    }

    private func findCoordinates(selector: String, index: Int, completion: @escaping (CGPoint?) -> Void) {
        let js = """
        (function() {
            const elements = document.querySelectorAll('\(selector)');
            if (elements.length > \(index)) {
                const el = elements[\(index)];
                el.scrollIntoView({ behavior: 'instant', block: 'center', inline: 'center' });
                const rect = el.getBoundingClientRect();
                return {
                    x: rect.left + rect.width / 2,
                    y: rect.top + rect.height / 2
                };
            }
            return null;
        })();
        """

        webView?.evaluateJavaScript(js) { result, _ in
            guard let dict = result as? [String: CGFloat],
                  let x = dict["x"], let y = dict["y"] else {
                completion(nil)
                return
            }
            let scale = self.webView?.scrollView.zoomScale ?? 1.0
            completion(CGPoint(x: x * scale, y: y * scale))
        }
    }

    private func executeNativeClick(at point: CGPoint, in webView: WKWebView, completion: @escaping (Bool) -> Void) {
        // Убедимся, что точка находится в пределах видимости вьюхи
        guard webView.bounds.contains(point) else {
            completion(false)
            return
        }
        
        // Проверяем наличие UIKit вьюхи под точкой
        let hitView = webView.hitTest(point, with: nil)
        guard hitView != nil else {
            completion(false)
            return
        }
        
        // Переводим фокус на WKWebView для активации цепочки ответов
        webView.becomeFirstResponder()

        // Чистый нативный вызов без самодельных PointerEvent-эмуляций в JS
        let jsClickScript = """
        (function() {
            const target = document.elementFromPoint(\(point.x), \(point.y));
            if (!target) return false;
            
            // Фокусируемся и вызываем стандартный метод активации
            if (typeof target.focus === 'function') {
                target.focus();
            }
            if (typeof target.click === 'function') {
                target.click();
            }
            
            return true;
        })();
        """

        webView.evaluateJavaScript(jsClickScript) { result, error in
            if let error = error {
                print("❌ Ошибка выполнения нативного клика: \(error)")
                completion(false)
                return
            }
            let success = (result as? Bool) ?? false
            completion(success)
        }
    }

    private func sendCallback(callbackId: String, success: Bool) {
        let jsResponse = "window.__resolveKotlinAction('\(callbackId)', \(success));"
        logToScreen(text: "📤 [Bridge OUT] Ответ: cb=\(callbackId), success=\(success)", color: "#ffff00")
        
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(jsResponse, completionHandler: nil)
        }
    }

    private func logToScreen(text: String, color: String) {
        let escapedText = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: " ")

        let js = """
        (function() {
            const consoleDiv = document.getElementById('ios-debug-console');
            if (consoleDiv) {
                const p = document.createElement('div');
                p.style.color = '\(color)';
                p.textContent = '\(escapedText)';
                consoleDiv.appendChild(p);
                consoleDiv.scrollTop = consoleDiv.scrollHeight;
            }
        })();
        """
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}

import SwiftUI
import WebKit

struct ContentView: View {
    @State private var webViewCoordinator = WebViewCoordinator()

    var body: some View {
        BrowserView(coordinator: webViewCoordinator)
            .edgesIgnoringSafeArea(.all)
            .onAppear {
                webViewCoordinator.loadGame()
            }
    }
}

class WebViewCoordinator: NSObject, ObservableObject, WKUIDelegate, WKNavigationDelegate {
    let webView: WKWebView
    var bridgeManager: GameWebViewManager?

    override init() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        
        self.webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        
        self.webView.uiDelegate = self
        self.webView.navigationDelegate = self
        self.bridgeManager = GameWebViewManager(webView: self.webView)
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

struct BrowserView: UIViewRepresentable {
    @ObservedObject var coordinator: WebViewCoordinator

    func makeUIView(context: Context) -> WKWebView {
        coordinator.loadGame()
        return coordinator.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}