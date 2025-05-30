//
//  StossycordApp.swift
//  Stossycord
//
//  Created by Stossy11 on 19/9/2024.
//

import SwiftUI
import KeychainSwift
import UserNotifications

@main
struct FinchcordApp: App {
    @StateObject var webSocketService = WebSocketService.shared
    let keychain = KeychainSwift()
    @State var isPresented: Bool = false
    @State var isfirst: Bool = false
    @Environment(\.scenePhase) var scenePhase
    @State var network = true
    var body: some Scene {
        WindowGroup {
            NavView(webSocketService: webSocketService)
                .onChange(of: scenePhase) { newPhase in
                    switch newPhase {
                    case .active:
                        if !isfirst {
                            isfirst = true
                        } else {
                            webSocketService.connect()
                            if !webSocketService.currentchannel.isEmpty {
                                getDiscordMessages(token: webSocketService.token, webSocketService: webSocketService)
                            }
                            
                            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
                                if granted {
                                    print("Notifications granted")
                                }
                                else {
                                    print("Notifications denied")
                                }
                            }
                            
                            print("App opened")
                        }
                    case .inactive:
                        webSocketService.disconnect()
                        // Handle app going inactive
                        print("App going inactive")
                    case .background:
                        webSocketService.disconnect()
                        // Handle app closed or backgrounded
                        print("App closed or in background")
                    @unknown default:
                        break
                    }
                }
                .sheet(isPresented: $isPresented) {
                    WelcomeView(webSocketService: webSocketService)
                }
                .onAppear {
                    if let token = keychain.get("token"), !token.isEmpty {
                        webSocketService.connect()
                    } else {
                        isPresented = true
                    }
                }
                .overlay {
                    if !network {
                        VStack {
                            Text("You Are Offline")
                            Spacer()
                        }
                    }
                }
                .onChange(of: webSocketService.isNetworkAvailable) { newValue in
                    if newValue {
                        print("Network is Avalible")
                    }
                    if !newValue {
                        print("Network is Unavalible")
                    }
                    
                    network = newValue
                }
        }
    }
}
