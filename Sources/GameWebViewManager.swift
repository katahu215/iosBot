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
                logToScreen(text: "⚠️ [Bridge] Ошибка: Неверный формат JSON в сообщении iosBridge", color: "#ffaa00")
                return
            }

            logToScreen(text: "🌉 [Bridge IN] Селектор: '\(selector)' [индекс: \(index)], cb: \(callbackId)", color: "#00ffff")

            // Шаг 1. Поиск координат элемента через JS
            logToScreen(text: "🔍 [Шаг 1] Ищем координаты элемента в DOM...", color: "#ffcc00")
            findCoordinates(selector: selector, index: index) { [weak self] point in
                guard let self = self, let point = point, let webView = self.webView else {
                    self?.logToScreen(text: "❌ [Шаг 1 Ошибка] Элемент '\(selector)' [\(index)] не найден или пустой webView", color: "#ff4444")
                    self?.sendCallback(callbackId: callbackId, success: false)
                    return
                }

                self.logToScreen(text: "✅ [Шаг 1 ОК] Координаты найдены: x=\(Int(point.x)), y=\(Int(point.y))", color: "#00ff00")

                // Шаг 2. Запуск нативного тача
                DispatchQueue.main.async {
                    self.logToScreen(text: "⚡ [Шаг 2] Запуск эмуляции аппаратного UITouch...", color: "#ffcc00")
                    self.simulateHardwareTouch(at: point, in: webView) { success in
                        if success {
                            self.logToScreen(text: "🎯 [Шаг 2 ОК] Нативный тач успешно отправлен в UIWindow!", color: "#00ff00")
                        } else {
                            self.logToScreen(text: "❌ [Шаг 2 Ошибка] hitTest не нашел view или упал при отправке события", color: "#ff4444")
                        }
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
            console.log('Найдено элементов по селектору ' + '\(selector)' + ': ' + elements.length);
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

        webView?.evaluateJavaScript(js) { result, error in
            if let error = error {
                print("❌ JS Error in findCoordinates: \(error)")
                completion(nil)
                return
            }
            
            guard let dict = result as? [String: CGFloat],
                  let x = dict["x"], let y = dict["y"] else {
                completion(nil)
                return
            }
            
            let scale = self.webView?.scrollView.zoomScale ?? 1.0
            completion(CGPoint(x: x * scale, y: y * scale))
        }
    }

    private func simulateHardwareTouch(at point: CGPoint, in webView: WKWebView, completion: @escaping (Bool) -> Void) {
        // Конвертируем координаты WebView в координаты UIWindow
        let windowPoint = webView.convert(point, to: nil)
        logToScreen(text: "📐 Локальные координаты: (\(Int(point.x)), \(Int(point.y))) -> Окно: (\(Int(windowPoint.x)), \(Int(windowPoint.y)))", color: "#aaaaff")
        
        guard let window = webView.window else {
            logToScreen(text: "❌ Ошибка: webView.window равен nil (вьюха не добавлена на экран)", color: "#ff4444")
            completion(false)
            return
        }

        // Проверяем hitTest в окне
        guard let hitView = window.hitTest(windowPoint, with: nil) else {
            logToScreen(text: "❌ Ошибка: window.hitTest ничего не нашел по этим координатам", color: "#ff4444")
            completion(false)
            return
        }

        logToScreen(text: "👁️ hitTest нашел UIView типа: \(type(of: hitView))", color: "#aaaaff")

        // Создаем UITouch через KVC
        let touch = UITouch()
        touch.setValue(windowPoint, forKey: "locationInWindow")
        touch.setValue(windowPoint, forKey: "previousLocationInWindow")
        touch.setValue(window, forKey: "window")
        touch.setValue(viewForTouch(hitView), forKey: "view")
        touch.setValue(ProcessInfo.processInfo.systemUptime, forKey: "timestamp")
        touch.setValue(1, forKey: "tapCount")
        touch.setValue(UITouch.TouchType.direct, forKey: "type")

        // Отправка фаз события
        dispatchTouchPhases(touch: touch, window: window) {
            completion(true)
        }
    }

    private func viewForTouch(_ hitView: UIView) -> UIView {
        return hitView
    }

    private func dispatchTouchPhases(touch: UITouch, window: UIWindow, completion: @escaping () -> Void) {
        // Фаза 1: Began (Начало касания)
        touch.setValue(UITouch.Phase.began, forKey: "phase")
        let touchesBegan = NSSet(object: touch)
        let beganEvent = createTouchEvent(with: touchesBegan)

        logToScreen(text: "👆 Отправка фазы: UITouchPhase.began", color: "#ffff00")
        sendEventToWindowOrApp(event: beganEvent, window: window)

        // Фаза 2: Ended (Отрыв пальца спустя 50мс)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self = self else { return }
            touch.setValue(UITouch.Phase.ended, forKey: "phase")
            let touchesEnded = NSSet(object: touch)
            let endedEvent = self.createTouchEvent(with: touchesEnded)

            logToScreen(text: "☝️ Отправка фазы: UITouchPhase.ended", color: "#ffff00")
            self.sendEventToWindowOrApp(event: endedEvent, window: window)
            
            completion()
        }
    }

    private func createTouchEvent(with touches: NSSet) -> UIEvent {
        let selector = NSSelectorFromString("_eventWithTouches:")
        if UIEvent.responds(to: selector),
           let eventConstructor = UIEvent.perform(selector),
           let event = eventConstructor.takeUnretainedValue() as? UIEvent {
            return event
        }
        return UIEvent()
    }

    private func sendEventToWindowOrApp(event: UIEvent, window: UIWindow) {
        if window.responds(to: NSSelectorFromString("sendTouchesForEvent:")) {
            window.perform(NSSelectorFromString("sendTouchesForEvent:"), with: event)
        } else {
            UIApplication.shared.sendEvent(event)
        }
    }

    private func sendCallback(callbackId: String, success: Bool) {
        let jsResponse = "window.__resolveKotlinAction('\(callbackId)', \(success));"
        logToScreen(text: "📤 [Bridge OUT] Ответ в JS -> cb: \(callbackId), success: \(success)", color: "#ffff00")
        
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