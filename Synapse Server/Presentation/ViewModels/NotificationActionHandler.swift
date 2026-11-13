//
//  NotificationActionHandler.swift
//  Synapse Server
//
//  Adds a "Reply" text box to banners of phone notifications that can be answered,
//  and shows banners even while Synapse is the frontmost app.
//

import Foundation
import UserNotifications

final class NotificationActionHandler: NSObject, UNUserNotificationCenterDelegate {
    static let replyCategory = "SYNAPSE_REPLY"
    static let replyAction = "SYNAPSE_REPLY_ACTION"
    static let keyInfo = "notification_key"

    private weak var viewModel: SynapseViewModel?

    init(viewModel: SynapseViewModel) {
        self.viewModel = viewModel
    }

    func register() {
        let center = UNUserNotificationCenter.current()
        let reply = UNTextInputNotificationAction(
            identifier: Self.replyAction,
            title: "Yanıtla",
            options: [],
            textInputButtonTitle: "Gönder",
            textInputPlaceholder: "Yanıt yazın…"
        )
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.replyCategory, actions: [reply], intentIdentifiers: [])
        ])
        center.delegate = self
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        defer { completionHandler() }
        guard response.actionIdentifier == Self.replyAction,
              let textResponse = response as? UNTextInputNotificationResponse,
              let key = response.notification.request.content.userInfo[Self.keyInfo] as? String else { return }
        let text = textResponse.userText
        Task { @MainActor [weak viewModel] in
            viewModel?.replyToNotification(key: key, text: text)
        }
    }
}
