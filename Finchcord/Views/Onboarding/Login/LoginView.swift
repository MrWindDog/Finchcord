//
//  LoginView.swift
//  Stossycord
//
//  Created by Stossy11 on 21/9/2024.
//

import SwiftUI
import KeychainSwift
import WebKit

struct LoginView: View {
    @Environment(\.dismiss) var dismiss
    @State var login = false
    @State var token = ""
    @StateObject var webSocketService: WebSocketService
    let keychain = KeychainSwift()
    var body: some View {
        VStack {
            Text("Login")
                .font(.largeTitle)
                .bold()
                .frame(maxWidth: .infinity, alignment: .center)
            
            WebView(url: URL(string: "https://discord.com/login")!) { newToken in
                self.token = newToken
                print(newToken)
                keychain.set(token, forKey: "token")
                
                if !token.isEmpty {
                    dismiss()
                    webSocketService.connect()
                }
                
            }
            
            .interactiveDismissDisabled()
            TextField("Discord Token", text: $token)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.gray)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.gray, lineWidth: 1)
                )
                .onSubmit {
                    keychain.set(token, forKey: "token")
                    
                    if !token.isEmpty {
                        dismiss()
                        webSocketService.connect()
                    }
                }
                .padding(.horizontal)
        }
        .padding()
    }
}





#if os(macOS)
struct WebView: NSViewRepresentable {
    let url: URL
    var onTokenDetected: ((String) -> Void)?

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator

        // Load the Discord login page
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) { }

    func makeCoordinator() -> Coordinator {
        return Coordinator(onTokenDetected: onTokenDetected)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var onTokenDetected: ((String) -> Void)?
        var retryCount = 0

        init(onTokenDetected: ((String) -> Void)?) {
            self.onTokenDetected = onTokenDetected
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            checkForToken(in: webView)
        }

        func checkForToken(in webView: WKWebView) {
            let js = """
            (function() {
                try {
                    // First try: look in localStorage (legacy)
                    let token = localStorage.getItem("token");
                    if (token) return token.replace(/"/g, '');

                    // Second try: look for a global function that exposes the token
                    for (let key in window) {
                        try {
                            if (window[key] && typeof window[key].getToken === 'function') {
                                const t = window[key].getToken();
                                if (t) return t;
                            }
                        } catch (e) {}
                    }

                    // Third try: fallback using Object.values and Webpack search
                    if (typeof webpackChunkdiscord_app === 'object') {
                        let a = [];
                        webpackChunkdiscord_app.push([
                            [Math.random()],
                            {},
                            e => {
                                for (let c of Object.keys(e.c)) {
                                    try {
                                        let m = e.c[c].exports?.default;
                                        if (m && typeof m.getToken === 'function') {
                                            let token = m.getToken();
                                            if (token) {
                                                a.push(token);
                                                break;
                                            }
                                        }
                                    } catch (err) {}
                                }
                            }
                        ]);
                        return a[0];
                    }

                    return null;
                } catch (e) {
                    return null;
                }
            })();
            """

            webView.evaluateJavaScript(js) { result, error in
                if let token = result as? String, !token.isEmpty {
                    print("Token found")
                    self.onTokenDetected?(token)
                } else {
                    self.retryCount += 1
                    if self.retryCount < 10 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            self.checkForToken(in: webView)
                        }
                    } else {
                        print("Token not found after multiple attempts.")
                    }
                }
            }
        }
    }
}

#elseif os(iOS)
struct WebView: UIViewRepresentable {
    let url: URL
    var onTokenDetected: ((String) -> Void)?

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator

        // Load the Discord login page
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) { }

    func makeCoordinator() -> Coordinator {
        return Coordinator(onTokenDetected: onTokenDetected)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var onTokenDetected: ((String) -> Void)?
        var retryCount = 0

        init(onTokenDetected: ((String) -> Void)?) {
            self.onTokenDetected = onTokenDetected
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            checkForToken(in: webView)
        }

        func checkForToken(in webView: WKWebView) {
            let js = """
            (function() {
                try {
                    // First try: look in localStorage (legacy)
                    let token = localStorage.getItem("token");
                    if (token) return token.replace(/"/g, '');

                    // Second try: look for a global function that exposes the token
                    for (let key in window) {
                        try {
                            if (window[key] && typeof window[key].getToken === 'function') {
                                const t = window[key].getToken();
                                if (t) return t;
                            }
                        } catch (e) {}
                    }

                    // Third try: fallback using Object.values and Webpack search
                    if (typeof webpackChunkdiscord_app === 'object') {
                        let a = [];
                        webpackChunkdiscord_app.push([
                            [Math.random()],
                            {},
                            e => {
                                for (let c of Object.keys(e.c)) {
                                    try {
                                        let m = e.c[c].exports?.default;
                                        if (m && typeof m.getToken === 'function') {
                                            let token = m.getToken();
                                            if (token) {
                                                a.push(token);
                                                break;
                                            }
                                        }
                                    } catch (err) {}
                                }
                            }
                        ]);
                        return a[0];
                    }

                    return null;
                } catch (e) {
                    return null;
                }
            })();
            """

            webView.evaluateJavaScript(js) { result, error in
                if let token = result as? String, !token.isEmpty {
                    print("Token found")
                    self.onTokenDetected?(token)
                } else {
                    self.retryCount += 1
                    if self.retryCount < 10 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            self.checkForToken(in: webView)
                        }
                    } else {
                        print("Token not found after multiple attempts.")
                    }
                }
            }
        }
    }
}
#endif
