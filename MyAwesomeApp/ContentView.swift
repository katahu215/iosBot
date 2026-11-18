import SwiftUI
import WebKit

// Мост для WKWebView с поддержкой управления через Coordinator
struct WebView: UIViewRepresentable {
    let url: URL
    @ObservedObject var webViewStore: WebViewStore

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences = prefs

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        
        // Передаем экземпляр webView в хранилище для управления извне (кнопки назад/вперед)
        webViewStore.webView = webView
        
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if uiView.url != url {
            let request = URLRequest(url: url)
            uiView.load(request)
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebView

        init(_ parent: WebView) {
            self.parent = parent
        }

        // Обновляем URL в адресной строке при переходе на новую страницу
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let currentURL = webView.url {
                parent.webViewStore.currentURL = currentURL
                parent.webViewStore.urlString = currentURL.absoluteString
            }
            parent.webViewStore.canGoBack = webView.canGoBack
            parent.webViewStore.canGoForward = webView.canGoForward
        }
    }
}

// Класс для хранения состояния браузера
class WebViewStore: ObservableObject {
    @Published var webView: WKWebView?
    @Published var urlString: String = "https://www.google.com"
    @Published var currentURL: URL? = URL(string: "https://www.google.com")
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false

    func goBack() {
        webView?.goBack()
    }

    func goForward() {
        webView?.goForward()
    }

    func reload() {
        webView?.reload()
    }

    func load(url: URL) {
        webView?.load(URLRequest(url: url))
    }
}

struct ContentView: View {
    @StateObject private var webViewStore = WebViewStore()
    @State private var inputURL: String = "https://www.google.com"

    var body: some View {
        VStack(spacing: 0) {
            // Верхняя панель: Адресная строка и кнопка ввода
            HStack(spacing: 8) {
                TextField("Введите URL", text: $inputURL)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .padding(8)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)

                Button(action: {
                    var formattedURL = inputURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !formattedURL.hasPrefix("http://") && !formattedURL.hasPrefix("https://") {
                        formattedURL = "https://" + formattedURL
                    }
                    if let url = URL(string: formattedURL) {
                        webViewStore.load(url: url)
                    }
                }) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 24))
                }
            }
            .padding()
            .background(Color(.systemBackground))

            // Сам браузер на весь экран
            if let url = webViewStore.currentURL {
                WebView(url: url, webViewStore: webViewStore)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                Text("Неверный URL")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()

            // Нижняя панель навигации (Назад, Вперед, Обновить)
            HStack {
                Button(action: {
                    webViewStore.goBack()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                }
                .disabled(!webViewStore.canGoBack)

                Spacer()

                Button(action: {
                    webViewStore.goForward()
                }) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 20, weight: .semibold))
                }
                .disabled(!webViewStore.canGoForward)

                Spacer()

                Button(action: {
                    webViewStore.reload()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 20, weight: .semibold))
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
        }
        .onChange(of: webViewStore.urlString) { newString in
            inputURL = newString
        }
    }
}