import UIKit
import UserNotifications

class NotificationManager: NSObject {
    
    override init() {
        super.init()
        setupNotifications()
    }
    
    // MARK: - Setup
    
    private func setupNotifications() {
        UNUserNotificationCenter.current().delegate = self
        requestNotificationPermission()
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification permission error: \(error)")
            }
        }
    }
    
    // MARK: - Local Notifications
    
    func scheduleDisconnectionNotification(for worldName: String) {
        let content = UNMutableNotificationContent()
        content.title = "MUDTapper"
        content.body = "Disconnected from \(worldName)"
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "disconnect-\(worldName)",
            content: content,
            trigger: nil // Immediate notification
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling notification: \(error)")
            }
        }
    }
    
    func scheduleReconnectionNotification(for worldName: String, delay: TimeInterval = 5.0) {
        let content = UNMutableNotificationContent()
        content.title = "MUDTapper"
        content.body = "Attempting to reconnect to \(worldName)..."
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: "reconnect-\(worldName)",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling reconnection notification: \(error)")
            }
        }
    }
    
    func cancelNotifications(for worldName: String) {
        let identifiers = [
            "disconnect-\(worldName)",
            "reconnect-\(worldName)"
        ]
        
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
    }
    
    func cancelAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, 
                               willPresent notification: UNNotification, 
                               withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, 
                               didReceive response: UNNotificationResponse, 
                               withCompletionHandler completionHandler: @escaping () -> Void) {
        // Handle notification tap
        let identifier = response.notification.request.identifier
        
        if identifier.hasPrefix("disconnect-") || identifier.hasPrefix("reconnect-") {
            // Bring app to foreground and potentially reconnect
            NotificationCenter.default.post(name: .notificationTapped, object: identifier)
        }
        
        completionHandler()
    }
}

// MARK: - Notification Extension

extension Notification.Name {
    static let notificationTapped = Notification.Name("NotificationTappedNotification")
} 