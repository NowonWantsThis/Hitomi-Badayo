import AppKit
import Foundation
import UserNotifications

final class CompletionAlertCenter: NSObject, UNUserNotificationCenterDelegate {
    override init() {
        super.init()
        notificationCenterIfAvailable()?.delegate = self
    }

    func requestAuthorizationIfNeeded() {
        guard let center = notificationCenterIfAvailable() else { return }
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert]) { _, _ in }
        }
    }

    func notifyJobFinished(title: String, outputPath: String) {
        let body: String
        if outputPath.trimmed.isEmpty {
            body = "Download finished."
        } else {
            body = URL(fileURLWithPath: outputPath).lastPathComponent
        }
        deliver(title: "Download Complete", body: body, identifierPrefix: "job")
    }

    func notifyQueueFinished(summary: String) {
        deliver(title: "Queue Complete", body: summary, identifierPrefix: "queue")
    }

    func playCompletionSound() {
        playSystemSound(named: "Glass")
    }

    func playClipboardSound() {
        playSystemSound(named: "Pop")
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }

    private func deliver(title: String, body: String, identifierPrefix: String) {
        guard let center = notificationCenterIfAvailable() else { return }
        center.getNotificationSettings { [weak self] settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                self?.submit(title: title, body: body, identifierPrefix: identifierPrefix)
            case .notDetermined:
                center.requestAuthorization(options: [.alert]) { granted, _ in
                    guard granted else { return }
                    self?.submit(title: title, body: body, identifierPrefix: identifierPrefix)
                }
            case .denied:
                return
            @unknown default:
                return
            }
        }
    }

    private func submit(title: String, body: String, identifierPrefix: String) {
        guard let center = notificationCenterIfAvailable() else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body

        let request = UNNotificationRequest(
            identifier: "hitomi-native-\(identifierPrefix)-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        center.add(request)
    }

    private func notificationCenterIfAvailable() -> UNUserNotificationCenter? {
        guard ProcessInfo.processInfo.environment["HITOMI_NATIVE_SKIP_NOTIFICATION_AUTH"] != "1" else { return nil }
        guard Bundle.main.bundleURL.pathExtension == "app" else { return nil }
        return UNUserNotificationCenter.current()
    }

    private func playSystemSound(named name: String) {
        if let sound = NSSound(named: NSSound.Name(name)) {
            sound.play()
        } else {
            NSSound.beep()
        }
    }
}
