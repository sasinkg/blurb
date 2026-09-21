//
//  blurbApp.swift
//  blurb
//
//  Created by Sasin on 8/26/26.
//

import SwiftUI
import FirebaseCore

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@main
struct blurbApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var auth: AuthManager
    @StateObject private var blurbStore: BlurbStore
    @AppStorage("appAppearance") private var appAppearance = AppAppearance.system.rawValue

    init() {
        FirebaseApp.configure()
        NotificationManager.shared.configure()
        let authManager = AuthManager()
        let store = BlurbStore()
#if DEBUG
        if let screen = ProcessInfo.processInfo.appStoreScreenshot, screen != "welcome" {
            store.seedAppStoreScreenshotData()
        }
#endif
        _auth = StateObject(wrappedValue: authManager)
        _blurbStore = StateObject(wrappedValue: store)
    }

    var body: some Scene {
        WindowGroup {
#if DEBUG
            if let screenshot = ProcessInfo.processInfo.appStoreScreenshot {
                Group {
                    if screenshot == "welcome" {
                        WelcomeView()
                    } else {
                        AppStoreScreenshotContentView(screen: screenshot)
                    }
                }
                .environmentObject(auth)
                .environmentObject(blurbStore)
                .fontDesign(.serif)
                .preferredColorScheme(.light)
            } else {
                authenticatedApp
            }
#else
            authenticatedApp
#endif
        }
    }

    private var authenticatedApp: some View {
            Group {
                if auth.isLoading {
                    ProgressView()
                } else if auth.user == nil {
                    WelcomeView()
                } else {
                    SignedInRootView()
                }
            }
            .environmentObject(auth)
            .environmentObject(blurbStore)
            .fontDesign(.serif)
            .preferredColorScheme(AppAppearance(rawValue: appAppearance)?.colorScheme)
            .onChange(of: auth.user?.uid) { _, userID in
                if userID == nil {
                    blurbStore.invalidateListeners()
                    Task { @MainActor in
                        await Task.yield()
                        if auth.user == nil {
                            blurbStore.stop()
                        }
                    }
                }
            }
    }
}

private extension ProcessInfo {
    var appStoreScreenshot: String? {
        guard let index = arguments.firstIndex(of: "-AppStoreScreenshot"),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}
