import WebKit
import UIKit
import UserNotifications

/// Координатор для управления WKWebView, загрузки игры, инъекции внешнего JS-бота и моста уведомлений
class WebViewCoordinator: NSObject, ObservableObject, WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler, UNUserNotificationCenterDelegate {
    let webView: WKWebView

    override init() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true

        // 1. Создаем WKUserContentController и привязываем к config до создания WKWebView
        let contentController = WKUserContentController()
        config.userContentController = contentController

        // 2. Создаем WKWebView один раз и инициализируем stored property до super.init()
        let view = WKWebView(frame: .zero, configuration: config)
        self.webView = view
        super.init()

        // 3. Регистрируем обработчик сообщений и делегаты после super.init()
        contentController.add(self, name: "showNotification")
        self.webView.uiDelegate = self
        self.webView.navigationDelegate = self

        setKeepScreenOn(true)
        setupNotifications()
    }

    /// Запрещает или разрешает автоматическое гашение экрана при работе приложения
    private func setKeepScreenOn(_ enabled: Bool) {
        DispatchQueue.main.async {
            UIApplication.shared.isIdleTimerDisabled = enabled
        }
    }

    /// Запрашивает права на уведомления и назначает делегат для показа баннеров внутри открытого приложения
    private func setupNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("❌ Ошибка запроса прав на уведомления: \(error)")
            } else {
                print(granted ? "✅ Разрешение на уведомления получено" : "⚠️ Уведомления запрещены пользователем")
            }
        }
    }

    /// Загружает страницу игры, если она еще не была загружена
    func loadGame() {
        setKeepScreenOn(true)
        if webView.url == nil, let url = URL(string: "https://creepjs.org/") {
            webView.load(URLRequest(url: url))
        }
    }

    /// Вызывается автоматически, когда WKWebView полностью закончил загрузку основной страницы
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // fetchAndInjectScript()
    }

    /// Принимает сообщения из JS (`window.webkit.messageHandlers.showNotification.postMessage(...)`)
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "showNotification" else { return }
        let text = String(describing: message.body)
        triggerLocalNotification(message: text)
    }

    /// Создает и мгновенно планирует системное уведомление iOS
    private func triggerLocalNotification(message: String) {
        let content = UNMutableNotificationContent()
        content.title = (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "Лига 17"
        content.body = message
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.2, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Ошибка отправки уведомления: \(error)")
            }
        }
    }

    /// Заставляет уведомление всплывать баннером даже когда приложение активно на экране
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// Скачивает удаленный JS-скрипт, подготавливает окружение и внедряет его в страницу
    func fetchAndInjectScript() {
        guard let scriptUrl = URL(string: "https://pbhelperskatan.duckdns.org:8443/bot/bundle.js") else { return }

        URLSession.shared.dataTask(with: scriptUrl) { data, response, error in
            guard let data = data, let jsCode = String(data: data, encoding: .utf8) else {
                print("❌ Ошибка скачивания bundle.js")
                return
            }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                let setupScript = """
                (function() {
                    window.sessionStore = window.sessionStore || {};
                    window.sessionStore.isMobile = true;

                    // Прокидываем мост win.iosBridge.showNotification(message) в нативный код iOS
                    window.iosBridge = window.iosBridge || {};
                    window.iosBridge.showNotification = function(message) {
                        try {
                            const handler = window.webkit &&
                                window.webkit.messageHandlers &&
                                window.webkit.messageHandlers.showNotification;
                            if (handler) {
                                handler.postMessage(String(message ?? ''));
                            } else {
                                console.error('iosBridge: messageHandler showNotification не найден');
                            }
                        } catch (e) {
                            console.error('iosBridge error:', e);
                        }
                    };

                    // Экранная консоль временно отключена:
                    // if (!document.getElementById('ios-debug-console')) {
                    //     const consoleDiv = document.createElement('div');
                    //     consoleDiv.id = 'ios-debug-console';
                    //     consoleDiv.style.position = 'fixed';
                    //     consoleDiv.style.bottom = '0';
                    //     consoleDiv.style.left = '0';
                    //     consoleDiv.style.width = '100%';
                    //     consoleDiv.style.maxHeight = '150px';
                    //     consoleDiv.style.overflowY = 'auto';
                    //     consoleDiv.style.backgroundColor = 'rgba(0, 0, 0, 0.85)';
                    //     consoleDiv.style.color = '#00ff00';
                    //     consoleDiv.style.fontSize = '10px';
                    //     consoleDiv.style.zIndex = '999999';
                    //     consoleDiv.style.padding = '6px';
                    //     consoleDiv.style.pointerEvents = 'none';
                    //     document.body.appendChild(consoleDiv);
                    //
                    //     const logToScreen = (msg, color = '#00ff00') => {
                    //         const p = document.createElement('div');
                    //         p.style.color = color;
                    //         p.textContent = msg;
                    //         consoleDiv.appendChild(p);
                    //         consoleDiv.scrollTop = consoleDiv.scrollHeight;
                    //     };
                    //
                    //     window.addEventListener('error', (e) => logToScreen('ERR: ' + e.message, '#ff4444'));
                    //
                    //     const originalLog = console.log;
                    //     console.log = (...args) => {
                    //         originalLog(...args);
                    //         logToScreen(args.join(' '));
                    //     };
                    //
                    //     const originalError = console.error;
                    //     console.error = (...args) => {
                    //         originalError(...args);
                    //         logToScreen('ERR: ' + args.join(' '), '#ff4444');
                    //     };
                    // }
                })();
                """

                self.webView.evaluateJavaScript(setupScript) { _, _ in
                    self.webView.evaluateJavaScript(jsCode, completionHandler: { _, error in
                        if let error = error {
                            print("❌ Ошибка выполнения bundle.js: \(error)")
                        } else {
                            print("✅ bundle.js успешно инъектирован!")

                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                let startScript = "if (typeof window.startBot === 'function') { window.startBot(); }"
                                self.webView.evaluateJavaScript(startScript, completionHandler: nil)
                            }
                        }
                    })
                }
            }
        }.resume()
    }

    /// Обрабатывает JS-вызов `confirm(...)` и показывает нативный iOS-диалог «Отмена / OK»
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

    /// Обрабатывает JS-вызов `alert(...)` и показывает нативное iOS-уведомление с кнопкой «OK»
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