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
                logToScreen(text: "⚠️ Неверный формат сообщения iosBridge", color: "#ffaa00")
                return
            }

            logToScreen(text: "🌉 [Bridge] Клик: sel='\(selector)', idx=\(index), cb=\(callbackId)", color: "#00ffff")

            executeTouchClick(selector: selector, index: index) { [weak self] success in
                self?.sendCallback(callbackId: callbackId, success: success)
            }
        }
    }

    private func executeTouchClick(selector: String, index: Int, completion: @escaping (Bool) -> Void) {
        let js = """
        (function() {
            const elements = document.querySelectorAll('\(selector)');
            if (elements.length > \(index)) {
                const el = elements[\(index)];
                el.scrollIntoView({ behavior: 'instant', block: 'center', inline: 'center' });
                
                const rect = el.getBoundingClientRect();
                const clientX = rect.left + rect.width / 2;
                const clientY = rect.top + rect.height / 2;

                const touchObj = new Touch({
                    identifier: Date.now(),
                    target: el,
                    clientX: clientX,
                    clientY: clientY,
                    radiusX: 2.5,
                    radiusY: 2.5,
                    rotationAngle: 0,
                    force: 1.0
                });

                const touchParams = {
                    bubbles: true,
                    cancelable: true,
                    view: window,
                    touches: [touchObj],
                    targetTouches: [touchObj],
                    changedTouches: [touchObj]
                };

                el.dispatchEvent(new TouchEvent('touchstart', touchParams));
                el.dispatchEvent(new TouchEvent('touchend', touchParams));
                el.click();

                return true;
            }
            return false;
        })();
        """

        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(js) { result, error in
                if let error = error {
                    self?.logToScreen(text: "❌ Ошибка JS тача: \(error.localizedDescription)", color: "#ff4444")
                }
                let success = (result as? Bool) ?? false
                self?.logToScreen(text: "🎯 Результат поиска элемента: \(success ? "Успех" : "Не найден")", color: success ? "#00ff00" : "#ff4444")
                completion(success)
            }
        }
    }

    private func sendCallback(callbackId: String, success: Bool) {
        let jsResponse = "window.__resolveKotlinAction('\(callbackId)', \(success));"
        logToScreen(text: "📤 [Response] Отправка в JS -> cb=\(callbackId), success=\(success)", color: "#ffff00")
        
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(jsResponse, completionHandler: nil)
        }
    }

    // Вспомогательный метод вывода логов прямо в экранную консоль WebView
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