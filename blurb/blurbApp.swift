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
    @StateObject private var auth: AuthManager
    @StateObject private var blurbStore: BlurbStore
    @AppStorage("appAppearance") private var appAppearance = AppAppearance.system.rawValue

    init() {
        FirebaseApp.configure()
        _auth = StateObject(wrappedValue: AuthManager())
        _blurbStore = StateObject(wrappedValue: BlurbStore())
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.isLoading {
                    ProgressView()
                } else if auth.user == nil {
                    WelcomeView()
                } else {
                    ContentView()
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
}
