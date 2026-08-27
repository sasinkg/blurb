//
//  blurbApp.swift
//  blurb
//
//  Created by Sasin on 8/26/26.
//

import SwiftUI
import FirebaseCore

@main
struct blurbApp: App {
    @StateObject private var auth = AuthManager()
    @StateObject private var blurbStore = BlurbStore()

    init() {
        FirebaseApp.configure()
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
        }
    }
}
