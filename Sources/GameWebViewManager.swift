import SwiftUI
import WebKit

struct ContentView: View {
    @State private var webViewCoordinator = WebViewCoordinator()

    var body: some View {
        BrowserView(coordinator: webViewCoordinator)
            .ignoresSafeArea()
    }
}

struct BrowserView: UIViewRepresentable {
    @ObservedObject var coordinator: WebViewCoordinator

    func makeUIView(context: Context) -> WKWebView {
        return coordinator.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

class WebViewCoordinator: NSObject, ObservableObject, WKUIDelegate, WKNavigationDelegate {
    let webView: WKWebView
    private var webViewConfig: WKWebViewConfiguration
    
    // Кэш для скачанного скрипта, если страница загрузилась быстрее, чем скачался бандл
    private var preloadedBundleCode: String?
    private var isGameLoaded = false

    override init() {
        self.webViewConfig = WKWebViewConfiguration()
        webViewConfig.allowsInlineMediaPlayback = true
        
        // Создаем webView с базовой конфигурацией
        self.webView = WKWebView(frame: .zero, configuration: webViewConfig)
        super.init()
        
        self.webView.uiDelegate = self
        self.webView.navigationDelegate = self
        
        // 1. Сразу в фоне начинаем скачивать bundle.js ДО старта загрузки страницы
        preloadedBundleScript()
        
        // 2. Начинаем загрузку сайта
        loadGame()
    }

    func loadGame() {
        if webView.url == nil, let url = URL(string: "https://league17.ru/game/") {
            webView.load(URLRequest(url: url))
        }
    }

    private func preloadedBundleScript() {
        guard let scriptUrl = URL(string: "https://pbhelperskatan.duckdns.org:8443/bot/bundle.js") else { return }
        
        URLSession.shared.dataTask(with: scriptUrl) { [weak self] data, _, error in
            guard let self = self, let data = data, let jsCode = String(data: data, encoding: .utf8) else {
                print("❌ Ошибка предварительного скачивания bundle.js")
                return
            }
            
            DispatchQueue.main.async {
                self.preloadedBundleCode = jsCode
                print("📦 bundle.js успешно скачан в фоновом режиме заранее!")
                
                // Если сайт уже открылся, а скрипт только что докачался — инъектируем его вручную
                if self.isGameLoaded {
                    self.injectDownloadedScript(jsCode)
                }
            }
        }.resume()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isGameLoaded = true
        
        // Если бандл уже скачался к моменту окончания загрузки страницы — выполняем
        if let bundleCode = preloadedBundleCode {
            injectDownloadedScript(bundleCode)
        } else {
            print("⏳ Страница загрузилась быстрее, чем скачался bundle.js, ждем загрузку сети...")
        }
    }

    private func injectDownloadedScript(_ jsCode: String) {
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
        
        webView.evaluateJavaScript(setupScript) { _, _ in
            webView.evaluateJavaScript(jsCode, completionHandler: { _, error in
                if let error = error {
                    print("❌ Ошибка выполнения bundle.js: \(error)")
                } else {
                    print("✅ bundle.js успешно инъектирован!")
                    
                    // Даем игре 1.5 секунды на инициализацию движка и запускаем бота
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        let startScript = "if (typeof window.startBot === 'function') { window.startBot(); }"
                        webView.evaluateJavaScript(startScript, completionHandler: nil)
                    }
                }
            })
        }
    }

    // Обработка JavaScript Alert/Confirm
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

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: name, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        // остальной код без изменений
    }
}