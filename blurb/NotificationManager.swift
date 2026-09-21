import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging
import UIKit
import UserNotifications

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate, MessagingDelegate {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()
    private let dailyReminderIdentifier = "daily-blurb-reminder"
    private let answeredReminderKeyPrefix = "daily-blurb-answered-reminder"
    private let reminderTimes = [(slot: "morning", hour: 10), (slot: "evening", hour: 19)]

    private override init() {
        super.init()
    }

    func configure() {
        center.delegate = self
        Messaging.messaging().delegate = self
    }

    func enableDailyReminder() async throws {
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .notDetermined:
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            guard granted else { throw NotificationError.permissionDenied }
        case .denied:
            throw NotificationError.permissionDenied
        case .authorized, .provisional, .ephemeral:
            break
        @unknown default:
            throw NotificationError.unavailable
        }

        try await scheduleDailyReminder()
        await enableRemoteDailyReminders()
    }

    func restoreDailyReminderIfAuthorized() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            do {
                try await scheduleDailyReminder()
                await enableRemoteDailyReminders()
                return true
            } catch {
                return false
            }
        default:
            return false
        }
    }

    func disableDailyReminder() {
        let identifiers = reminderIdentifiersForNextDays(45) + legacyReminderIdentifiersForNextDays(45) + [dailyReminderIdentifier]
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
        Task {
            await setDailyReminderPreference(false)
            if !UserDefaults.standard.bool(forKey: "replyNotificationsEnabled"),
               let userID = Auth.auth().currentUser?.uid {
                await removeReplyToken(for: userID)
            }
        }
    }

    func markAnsweredToday() {
        let identifier = legacyReminderIdentifier(for: .now)
        if let userID = Auth.auth().currentUser?.uid {
            UserDefaults.standard.set(identifier, forKey: answeredReminderKey(for: userID))
        }
        let identifiers = reminderTimes.map { reminderIdentifier(for: .now, slot: $0.slot) } + [identifier, dailyReminderIdentifier]
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    func enableReplyNotifications() async throws {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            guard granted else { throw NotificationError.permissionDenied }
        case .denied:
            throw NotificationError.permissionDenied
        case .authorized, .provisional, .ephemeral:
            break
        @unknown default:
            throw NotificationError.unavailable
        }

        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }
        if let token = try? await Messaging.messaging().token() {
            await save(token: token)
        }
        await setReplyNotificationPreference(true)
    }

    func restoreReplyNotificationsIfAuthorized() async -> Bool {
        let settings = await center.notificationSettings()
        guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else {
            return false
        }
        do {
            try await enableReplyNotifications()
            return true
        } catch {
            return false
        }
    }

    func disableReplyNotifications() async {
        await setReplyNotificationPreference(false)
        guard !UserDefaults.standard.bool(forKey: "dailyReminderEnabled"),
              let userID = Auth.auth().currentUser?.uid else { return }
        await removeReplyToken(for: userID)
    }

    func removeReplyToken(for userID: String) async {
        guard let token = try? await Messaging.messaging().token() else { return }
        try? await Firestore.firestore().collection("users").document(userID).updateData([
            "fcmTokens": FieldValue.arrayRemove([token])
        ])
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        Task { await save(token: fcmToken) }
    }

    private func save(token: String) async {
        guard (UserDefaults.standard.bool(forKey: "replyNotificationsEnabled") ||
               UserDefaults.standard.bool(forKey: "dailyReminderEnabled")),
              let userID = Auth.auth().currentUser?.uid else { return }
        try? await Firestore.firestore().collection("users").document(userID).setData([
            "fcmTokens": FieldValue.arrayUnion([token])
        ], merge: true)
    }

    private func scheduleDailyReminder() async throws {
        let calendar = Calendar.current
        let now = Date.now
        let answeredIdentifier: String?
        if let userID = Auth.auth().currentUser?.uid {
            answeredIdentifier = UserDefaults.standard.string(forKey: answeredReminderKey(for: userID))
        } else {
            answeredIdentifier = nil
        }
        let oldIdentifiers = reminderIdentifiersForNextDays(45) + legacyReminderIdentifiersForNextDays(45) + [dailyReminderIdentifier]
        center.removePendingNotificationRequests(withIdentifiers: oldIdentifiers)

        for offset in 0..<30 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now),
                  legacyReminderIdentifier(for: day) != answeredIdentifier else { continue }
            for reminder in reminderTimes {
                guard let fireDate = calendar.date(bySettingHour: reminder.hour, minute: 0, second: 0, of: day),
                      fireDate > now else { continue }
                let content = UNMutableNotificationContent()
                content.title = reminder.slot == "morning" ? "Today’s Blurb is ready" : "Don’t forget today’s Blurb"
                content.body = reminder.slot == "morning"
                    ? "Start the conversation with your answer."
                    : "There’s still time to answer today’s question."
                content.sound = .default
                let request = UNNotificationRequest(
                    identifier: reminderIdentifier(for: fireDate, slot: reminder.slot),
                    content: content,
                    trigger: UNCalendarNotificationTrigger(
                        dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate),
                        repeats: false
                    )
                )
                try await center.add(request)
            }
        }
    }

    private func reminderIdentifiersForNextDays(_ count: Int) -> [String] {
        let calendar = Calendar.current
        return (0..<count).flatMap { offset -> [String] in
            guard let day = calendar.date(byAdding: .day, value: offset, to: .now) else { return [] }
            return reminderTimes.map { reminderIdentifier(for: day, slot: $0.slot) }
        }
    }

    private func legacyReminderIdentifiersForNextDays(_ count: Int) -> [String] {
        let calendar = Calendar.current
        return (0..<count).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: .now).map(legacyReminderIdentifier)
        }
    }

    private func reminderIdentifier(for date: Date, slot: String) -> String {
        "\(legacyReminderIdentifier(for: date))-\(slot)"
    }

    private func legacyReminderIdentifier(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(dailyReminderIdentifier)-\(formatter.string(from: date))"
    }

    private func enableRemoteDailyReminders() async {
        await setDailyReminderPreference(true)
        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }
        if let token = try? await Messaging.messaging().token() {
            await save(token: token)
        }
    }

    private func setDailyReminderPreference(_ enabled: Bool) async {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        try? await Firestore.firestore().collection("users").document(userID).updateData([
            "notificationPreferences.dailyReminders": enabled
        ])
    }

    private func setReplyNotificationPreference(_ enabled: Bool) async {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        try? await Firestore.firestore().collection("users").document(userID).updateData([
            "notificationPreferences.replyNotifications": enabled
        ])
    }

    private func answeredReminderKey(for userID: String) -> String {
        "\(answeredReminderKeyPrefix)-\(userID)"
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken
    }
}

enum NotificationError: LocalizedError {
    case permissionDenied
    case unavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Notifications are turned off. Enable them for Daily Blurb in the Settings app to use the daily reminder."
        case .unavailable:
            return "Daily reminders are unavailable right now. Please try again."
        }
    }
}
