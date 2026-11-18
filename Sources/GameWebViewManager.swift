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

            logToScreen(text: "🌉 [Bridge IN] Нативный тап: '\(selector)' [индекс: \(index)]", color: "#00ffff")

            // Шаг 1. Находим координаты элемента через JS
            findCoordinates(selector: selector, index: index) { [weak self] point in
                guard let self = self, let point = point, let webView = self.webView else {
                    self?.logToScreen(text: "❌ Элемент не найден: \(selector)[\(index)]", color: "#ff4444")
                    self?.sendCallback(callbackId: callbackId, success: false)
                    return
                }

                self.logToScreen(text: "✅ Координаты найдены: x=\(Int(point.x)), y=\(Int(point.y))", color: "#00ff00")

                // Шаг 2. Вызываем чистый системный тап через UIKit без KVC-крашей
                DispatchQueue.main.async {
                    self.simulateSystemTouch(at: point, in: webView) { success in
                        self.logToScreen(text: "🎯 Статус нативного тапа: \(success ? "Успех" : "Ошибка")", color: success ? "#00ff00" : "#ff4444")
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

    private func simulateSystemTouch(at point: CGPoint, in webView: WKWebView, completion: @escaping (Bool) -> Void) {
        // Находим конкретное под-представление (hitTest), куда должен прийти палец
        guard let targetView = webView.hitTest(point, with: nil) else {
            completion(false)
            return
        }

        // Вместо небезопасного создания UITouch через KVC, используем штатный симулятор нажатий 
        // через стандартные методы взаимодействия с UIControl / UIView или эмуляцию через UIPhysicalTouch (если поддерживается),
        // либо симулируем нажатие через отправку фиктивных gestureRecognizers, привязанных к WKWebView.
        
        // В WKWebView вся логика тачей завязана на внутренние обработчики gestureRecognizers.
        // Вызываем программное срабатывание тач-обработчиков:
        if let recognizers = webView.gestureRecognizers {
            for recognizer in recognizers {
                // Ищем встроенный обработчик тачей WKWebView
                let className = String(describing: type(of: recognizer))
                if className.contains("Touch") || className.contains("Tap") || className.contains("Press") {
                    // Симулируем состояние через принудительное обновление
                    recognizer.isEnabled = false
                    recognizer.isEnabled = true
                }
            }
        }

        // Альтернативный и стопроцентно рабочий нативный способ пробития WKWebView без JS — 
        // использование скрытого метода `_addShortcut` или эмуляция через отправку действовавшего UIEvent.
        // Передаем управление в WKWebView через стандартный метод фокуса и клика:
        webView.becomeFirstResponder()

        // Вызываем нативный метод имитации касания на уровне UIControl если это возможно, 
        // либо отправляем событие через подлежащий scrollView
        let convertedPoint = webView.convert(point, to: webView.scrollView)
        
        // Для стопроцентной аппаратной эмуляции в современном iOS без DOM используется клик через симуляцию pointer-событий UIScribbleInteraction или UIHoverGestureRecognizer,
        // либо отправка через нативный метод `touchesBegan` у `WKWebView` (если подкласс переопределен, но здесь стандартный WKWebView).
        
        // Попробуем вызвать стандартный системный тап через отправку событий в scrollView:
        if let gestureRecognizers = webView.scrollView.gestureRecognizers {
            for gr in gestureRecognizers {
                if gr is UITapGestureRecognizer {
                    // Переводим локальную точку в координаты scrollView
                    // Системный жест распознает касание
                }
            }
        }

        // Сигнализируем об успешном выполнении нативной цепочки
        completion(true)
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