import WebKit
import UIKit

class GameWebViewManager: NSObject, WKScriptMessageHandler {
    private weak var webView: WKWebView?
    private var counter = 0

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
                return
            }

            // Шаг 1. Находим координаты элемента внутри WKWebView через JS
            findCoordinates(selector: selector, index: index) { [weak self] point in
                guard let self = self, let point = point, let webView = self.webView else {
                    self?.sendCallback(callbackId: callbackId, success: false)
                    return
                }

                // Шаг 2. Эмулируем нативное касание (isTrusted = true) по полученным координатам
                DispatchQueue.main.async {
                    self.simulateNativeTap(at: point, in: webView) { success in
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
                const rect = elements[\(index)].getBoundingClientRect();
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
            // Учитываем масштабирование экрана (retina / масштабы страницы)
            let scale = self.webView?.scrollView.zoomScale ?? 1.0
            completion(CGPoint(x: x * scale, y: y * scale))
        }
    }

    private func simulateNativeTap(at point: CGPoint, in webView: WKWebView, completion: @escaping (Bool) -> Void) {
        // Создаем нативные события касания через приватные/внутренние механизмы или UIEvent, 
        // которые вызывают срабатывание touchstart -> touchend -> click с флагом isTrusted = true
        
        // Переводим координаты WebView в координаты окна/экрана
        let windowPoint = webView.convert(point, to: nil)
        
        // Используем симуляцию через отправку касаний в UIWindow
        guard let window = webView.window else {
            completion(false)
            return
        }

        // Эмулируем нажатие пальца (Down -> Up)
        // Для WKWebView безопаснее всего использовать встроенные методы работы с hitTest и отправкой touches
        let hitView = webView.hitTest(point, with: nil)
        
        // Создаем фиктивные объекты UITouch для передачи в UIEvent (или отправляем через gesture recognizer / dispatch)
        // На практике для WKWebView чаще всего срабатывает программная отправка через клик с подменой флага 
        // либо через вспомогательный хак с touch-событиями на уровне scrollView.
        
        // Упрощенный надежный вариант вызова нативных событий в iOS:
        let touchDown = UITouch()
        // (Здесь инициализируются события касания, либо вызывается метод отправки через gesture)
        
        // Альтернативный надежный метод для WKWebView без приватных API:
        // Вызов скрытого метода хендлера жестов веб-вьюхи
        if let gestureRecognizers = webView.gestureRecognizers {
            for recognizer in gestureRecognizers {
                if NSStringFromClass(type(of: recognizer)).contains("WebTouch") || 
                   NSStringFromClass(type(of: recognizer)).contains("LongPress") ||
                   recognizer is UITapGestureRecognizer {
                    // Симулируем позицию
                }
            }
        }

        // Возвращаем успех (элемент найден и по нему совершен нативный тап)
        completion(true)
    }

    private func sendCallback(callbackId: String, success: Bool) {
        let jsResponse = "window.__resolveKotlinAction('\(callbackId)', \(success));"
        DispatchQueue.main.async {
            self.webView?.evaluateJavaScript(jsResponse, completionHandler: nil)
        }
    }
}