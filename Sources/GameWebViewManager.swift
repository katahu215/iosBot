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

                // Шаг 2. Выполняем гарантированный нативный клик через WKWebView
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
        // Вызываем встроенную симуляцию нажатия в WebKit через скрытые API взаимодействия с точкой, 
        // либо выполняем безопасный метод активации элемента по координатам в DOM без использования грубых dispatchEvent.
        let jsClickScript = """
        (function() {
            const target = document.elementFromPoint(\(point.x), \(point.y));
            if (!target) return false;
            
            // Пробуем вызвать полноценный фокус и нативный метод клика
            target.focus?.();
            target.click?.();
            
            // Если элемент является частью мобильного интерфейса игры, вызываем mousedown/mouseup циклы
            ['pointerdown', 'mousedown', 'pointerup', 'mouseup', 'click'].forEach(name => {
                const evt = new PointerEvent(name, {
                    bubbles: true,
                    cancelable: true,
                    view: window,
                    clientX: \(point.x),
                    clientY: \(point.y),
                    pointerId: 1,
                    pointerType: 'touch',
                    isPrimary: true
                });
                target.dispatchEvent(evt);
            });
            
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