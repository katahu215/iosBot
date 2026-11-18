import WebKit

class GameWebViewManager: NSObject, WKScriptMessageHandler {
    private weak var webView: WKWebView?

    init(webView: WKWebView) {
        self.webView = webView
        super.init()
        
        // Регистрируем мост KotlinBridge
        webView.configuration.userContentController.add(self, name: "KotlinBridge")
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