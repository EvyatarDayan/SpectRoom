//
//  NotificationService.swift
//  SpectRoom
//
//  Created by EVYATAR DAYAN on 2025-10-23.
//

import Foundation
import UserNotifications
import UIKit

class NotificationService: NSObject, ObservableObject {
    static let shared = NotificationService()
    
    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }
    
    /// Check if notification permission is granted
    func checkNotificationPermission() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }
    
    /// Check if notifications are enabled in app settings
    func areNotificationsEnabled() -> Bool {
        return UserDefaults.standard.bool(forKey: "notificationsEnabled")
    }
    
    /// Send a local push notification for a new match
    func sendNewMatchNotification(matchName: String, matchId: String) {
        guard areNotificationsEnabled() else {
            print("📱 Notifications disabled in settings, skipping push notification")
            return
        }
        
        Task {
            let hasPermission = await checkNotificationPermission()
            guard hasPermission else {
                print("📱 Notification permission not granted, skipping push notification")
                return
            }
            
            let content = UNMutableNotificationContent()
            content.title = "It's a match! 💕"
            content.body = "You and \(matchName) like each other!"
            content.sound = .default
            content.badge = NSNumber(value: UIApplication.shared.applicationIconBadgeNumber + 1)
            content.userInfo = ["type": "match", "matchId": matchId]
            
            // Schedule notification immediately
            let request = UNNotificationRequest(
                identifier: "match_\(matchId)",
                content: content,
                trigger: nil // nil trigger means immediate
            )
            
            do {
                try await UNUserNotificationCenter.current().add(request)
                print("📱 Push notification sent for match: \(matchName)")
            } catch {
                print("❌ Failed to send match notification: \(error.localizedDescription)")
            }
        }
    }
    
    /// Send a local push notification for a new message
    func sendNewMessageNotification(senderName: String, messageContent: String, senderId: String) {
        guard areNotificationsEnabled() else {
            print("📱 Notifications disabled in settings, skipping push notification")
            return
        }
        
        Task {
            let hasPermission = await checkNotificationPermission()
            guard hasPermission else {
                print("📱 Notification permission not granted, skipping push notification")
                return
            }
            
            let content = UNMutableNotificationContent()
            content.title = "New message from \(senderName)"
            content.body = messageContent.count > 50 ? String(messageContent.prefix(50)) + "..." : messageContent
            content.sound = .default
            content.badge = NSNumber(value: UIApplication.shared.applicationIconBadgeNumber + 1)
            content.userInfo = ["type": "message", "senderId": senderId]
            
            // Schedule notification immediately
            let request = UNNotificationRequest(
                identifier: "message_\(senderId)_\(UUID().uuidString)",
                content: content,
                trigger: nil // nil trigger means immediate
            )
            
            do {
                try await UNUserNotificationCenter.current().add(request)
                print("📱 Push notification sent for message from: \(senderName)")
            } catch {
                print("❌ Failed to send message notification: \(error.localizedDescription)")
            }
        }
    }
    
    /// Request notification permission
    func requestNotificationPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            if granted {
                // Register for remote notifications if permission granted
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                print("✅ Notification permission granted")
            } else {
                print("❌ Notification permission denied")
            }
            return granted
        } catch {
            print("❌ Error requesting notification permission: \(error.localizedDescription)")
            return false
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension NotificationService: UNUserNotificationCenterDelegate {
    // Handle notification when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    // Handle notification tap
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        
        if let type = userInfo["type"] as? String {
            switch type {
            case "match":
                // Handle match notification tap
                if let matchId = userInfo["matchId"] as? String {
                    // Navigate to matches view
                    print("📱 User tapped match notification: \(matchId)")
                }
            case "message":
                // Handle message notification tap
                if let senderId = userInfo["senderId"] as? String {
                    // Navigate to message conversation
                    print("📱 User tapped message notification from: \(senderId)")
                }
            default:
                break
            }
        }
        
        completionHandler()
    }
}



