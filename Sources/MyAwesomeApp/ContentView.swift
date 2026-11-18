import SwiftUI
import WebKit

struct WebView: UIViewRepresentable {
    let url: URL
    @ObservedObject var webViewStore: WebViewStore

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webViewStore.webView = webView
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if uiView.url != url {
            uiView.load(URLRequest(url: url))
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebView
        init(_ parent: WebView) { self.parent = parent }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let currentURL = webView.url {
                parent.webViewStore.urlString = currentURL.absoluteString
            }
            parent.webViewStore.canGoBack = webView.canGoBack
            parent.webViewStore.canGoForward = webView.canGoForward
        }
    }
}

class WebViewStore: ObservableObject {
    @Published var webView: WKWebView?
    @Published var urlString: String = "https://www.google.com"
    @Published var currentURL: URL? = URL(string: "https://www.google.com")
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func reload() { webView?.reload() }
    func load(url: URL) { webView?.load(URLRequest(url: url)) }
}

struct ContentView: View {
    @StateObject private var webViewStore = WebViewStore()
    @State private var inputURL: String = "https://www.google.com"

    var body: some View {
        VStack(spacing: 0) {
            // Панель ввода адреса
            HStack(spacing: 8) {
                TextField("URL", text: $inputURL)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .padding(8)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)

                Button(action: {
                    var formatted = inputURL
                    if !formatted.hasPrefix("http://") && !formatted.hasPrefix("https://") {
                        formatted = "https://" + formatted
                    }
                    if let url = URL(string: formatted) {
                        webViewStore.load(url: url)
                    }
                }) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 24))
                }
            }
            .padding()

            // Область WebView
            if let url = webViewStore.currentURL {
                WebView(url: url, webViewStore: webViewStore)
                    .ignoresSafeArea(edges: .bottom)
            }

            Divider()

            // Нижняя панель навигации
            HStack {
                Button(action: { webViewStore.goBack() }) {
                    Image(systemName: "chevron.left").font(.system(size: 20, weight: .semibold))
                }
                .disabled(!webViewStore.canGoBack)

                Spacer()

                Button(action: { webViewStore.goForward() }) {
                    Image(systemName: "chevron.right").font(.system(size: 20, weight: .semibold))
                }
                .disabled(!webViewStore.canGoForward)

                Spacer()

                Button(action: { webViewStore.reload() }) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 20, weight: .semibold))
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 12)
        }
        .onChange(of: webViewStore.urlString) { newString in
            inputURL = newString
        }
    }
}
