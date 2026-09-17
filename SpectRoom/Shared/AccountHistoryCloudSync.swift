//
//  AccountHistoryCloudSync.swift
//  SpectRoom
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

/// Persists account history events under `users/{uid}/accountHistory/{eventId}`.
/// Local UserDefaults remains a cache; Firestore is source of truth when signed in.
enum AccountHistoryCloudSync {
    private static let collectionName = "accountHistory"

    @MainActor
    @discardableResult
    static func pushEvent(_ event: AccountHistoryEvent) async -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else {
            print("⚠️ Skip account history push: no signed-in user for \(event.id)")
            return false
        }
        let ref = Firestore.firestore()
            .collection("users")
            .document(uid)
            .collection(collectionName)
            .document(event.id)
        do {
            try await ref.setData(firestoreData(for: event), merge: true)
            print("✅ Pushed account history \(event.kind.rawValue) \(event.id)")
            return true
        } catch {
            print("⚠️ Failed to sync account history event: \(error.localizedDescription)")
            return false
        }
    }

    /// Uploads any local-only events (e.g. created offline / before cloud sync existed).
    @MainActor
    static func pushMissingEvents(_ events: [AccountHistoryEvent]) async {
        guard Auth.auth().currentUser?.uid != nil else { return }
        let remote = await fetchEvents()
        let remoteIds = Set(remote.map(\.id))
        for event in events where !remoteIds.contains(event.id) {
            await pushEvent(event)
        }
    }

    @MainActor
    static func fetchEvents() async -> [AccountHistoryEvent] {
        guard let uid = Auth.auth().currentUser?.uid else { return [] }
        do {
            let snapshot = try await Firestore.firestore()
                .collection("users")
                .document(uid)
                .collection(collectionName)
                .order(by: "date", descending: true)
                .getDocuments()
            return snapshot.documents.compactMap { parseEvent(id: $0.documentID, data: $0.data()) }
        } catch {
            print("⚠️ Failed to fetch account history: \(error.localizedDescription)")
            return []
        }
    }

    static func firestoreData(for event: AccountHistoryEvent) -> [String: Any] {
        var data: [String: Any] = [
            "kind": event.kind.rawValue,
            "date": Timestamp(date: event.date),
            "currencyCode": event.currencyCode,
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        if let planTier = event.planTier {
            data["planTier"] = planTier.rawValue
        }
        if let interval = event.interval {
            data["billingInterval"] = interval.rawValue
        }
        if let amount = event.amount {
            data["amount"] = NSDecimalNumber(decimal: amount).stringValue
        }
        if let status = event.status {
            data["status"] = status.rawValue
        }
        return data
    }

    static func parseEvent(id: String, data: [String: Any]) -> AccountHistoryEvent? {
        guard let kindRaw = data["kind"] as? String,
              let kind = AccountHistoryEventKind(rawValue: kindRaw) else {
            return nil
        }

        let date: Date = {
            if let ts = data["date"] as? Timestamp {
                return ts.dateValue()
            }
            if let interval = data["date"] as? TimeInterval {
                return Date(timeIntervalSince1970: interval)
            }
            return Date()
        }()

        let planTier = (data["planTier"] as? String).flatMap(PlanTier.init(rawValue:))
        let interval = (data["billingInterval"] as? String).flatMap(BillingInterval.init(rawValue:))
        let currencyCode = (data["currencyCode"] as? String) ?? "USD"
        let status = (data["status"] as? String).flatMap(InvoiceStatus.init(rawValue:))

        let amount: Decimal? = {
            if let string = data["amount"] as? String {
                return Decimal(string: string)
            }
            if let number = data["amount"] as? NSNumber {
                return number.decimalValue
            }
            if let double = data["amount"] as? Double {
                return Decimal(double)
            }
            return nil
        }()

        return AccountHistoryEvent(
            id: id,
            date: date,
            kind: kind,
            planTier: planTier,
            interval: interval,
            amount: amount,
            currencyCode: currencyCode,
            status: status
        )
    }

    /// Merge remote + local by event id (remote wins on conflict).
    static func merge(local: [AccountHistoryEvent], remote: [AccountHistoryEvent]) -> [AccountHistoryEvent] {
        var byId: [String: AccountHistoryEvent] = [:]
        for event in local {
            byId[event.id] = event
        }
        for event in remote {
            byId[event.id] = event
        }
        return Array(byId.values).sorted { $0.date > $1.date }
    }
}
