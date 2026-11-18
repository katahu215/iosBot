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
                return
            }

            // Выполняем поиск элемента и клик прямо в контексте WKWebView через JS
            executeClick(selector: selector, index: index) { [weak self] success in
                self?.sendCallback(callbackId: callbackId, success: success)
            }
        }
    }

    private func executeClick(selector: String, index: Int, completion: @escaping (Bool) -> Void) {
        let js = """
        (function() {
            const elements = document.querySelectorAll('\(selector)');
            if (elements.length > \(index)) {
                const el = elements[\(index)];
                
                // Прокручиваем к элементу, чтобы он был в зоне видимости
                el.scrollIntoView({ behavior: 'smooth', block: 'center', inline: 'center' });
                
                // Вызываем стандартный клик
                el.click();
                
                // Также можно дополнительно эмулировать события мыши/тача для надежности фреймворков (React/Vue и т.д.)
                ['mousedown', 'mouseup', 'click'].forEach(eventType => {
                    const event = new MouseEvent(eventType, {
                        view: window,
                        bubbles: true,
                        cancelable: true,
                        clientX: el.getBoundingClientRect().x + el.getBoundingClientRect().width / 2,
                        clientY: el.getBoundingClientRect().y + el.getBoundingClientRect().height / 2
                    });
                    el.dispatchEvent(event);
                });

                return true;
            }
            return false;
        })();
        """

        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(js) { result, error in
                let success = (result as? Bool) ?? false
                completion(success)
            }
        }
    }

    private func sendCallback(callbackId: String, success: Bool) {
        let jsResponse = "window.__resolveKotlinAction('\(callbackId)', \(success));"
        DispatchQueue.main.async {
            self.webView?.evaluateJavaScript(jsResponse, completionHandler: nil)
        }
    }
}