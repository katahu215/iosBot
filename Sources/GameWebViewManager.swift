import WebKit

class GameWebViewManager: NSObject, WKScriptMessageHandler {
    private weak var webView: WKWebView?

    init(webView: WKWebView) {
        self.webView = webView
        super.init()
        
        // Регистрируем канал iosBridge для получения JSON-словарей от бота
        webView.configuration.userContentController.add(self, name: "iosBridge")
    }

    // MARK: - Обработка моста iosBridge (JS -> Swift)
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "iosBridge" {
            guard let dict = message.body as? [String: Any],
                  let selector = dict["selector"] as? String,
                  let index = dict["index"] as? Int,
                  let callbackId = dict["callbackId"] as? String else {
                return
            }

            performClick(selector: selector, index: index) { success in
                let jsResponse = "window.__resolveKotlinAction('\(callbackId)', \(success));"
                self.webView?.evaluateJavaScript(jsResponse, completionHandler: nil)
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
        
        webView?.evaluateJavaScript(jsFindAndClick) { result, error in
            let success = (result as? Bool) ?? false
            completion(success)
        }
    }
}