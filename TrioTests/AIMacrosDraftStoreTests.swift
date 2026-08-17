import Foundation
import Testing

@testable import Trio

@Suite("AI Macros draft store", .serialized) struct AIMacrosDraftStoreTests {
    private static let now = Date(timeIntervalSinceReferenceDate: 123_456)
    private static let maximums = AIMacrosDraftMaximums(carbs: 100, fat: 50, protein: 75)

    private func makeStore() -> (store: AIMacrosDraftStore, defaults: UserDefaults, key: String) {
        let suiteName = "AIMacrosDraftStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let key = "draft.\(suiteName)"
        return (
            AIMacrosDraftStore(defaults: defaults, key: key, timeToLive: AIMacrosDraftStore.defaultTimeToLive),
            defaults,
            key
        )
    }

    @Test("Validates non-negative values and all configured maxima") func validatesValuesAgainstMaximums() throws {
        let maximums = AIMacrosDraftMaximums(carbs: 100, fat: 50, protein: 75)
        try AIMacrosDraft(carbs: 100, fat: 50, protein: 75).validate(maximums: maximums)
        #expect(throws: AIMacrosDraftValidationError.negativeCarbs) {
            try AIMacrosDraft(carbs: -1, fat: 0, protein: 0).validate(maximums: maximums)
        }
        #expect(throws: AIMacrosDraftValidationError.negativeFat) {
            try AIMacrosDraft(carbs: 0, fat: -1, protein: 0).validate(maximums: maximums)
        }
        #expect(throws: AIMacrosDraftValidationError.negativeProtein) {
            try AIMacrosDraft(carbs: 0, fat: 0, protein: -1).validate(maximums: maximums)
        }
        #expect(throws: AIMacrosDraftValidationError.emptyEstimate) {
            try AIMacrosDraft(carbs: 0, fat: 0, protein: 0).validate(maximums: maximums)
        }
        #expect(throws: AIMacrosDraftValidationError.carbsExceedsMaximum(100)) {
            try AIMacrosDraft(carbs: 101, fat: 0, protein: 0).validate(maximums: maximums)
        }
        #expect(throws: AIMacrosDraftValidationError.fatExceedsMaximum(50)) {
            try AIMacrosDraft(carbs: 0, fat: 51, protein: 0).validate(maximums: maximums)
        }
        #expect(throws: AIMacrosDraftValidationError.proteinExceedsMaximum(75)) {
            try AIMacrosDraft(carbs: 0, fat: 0, protein: 76).validate(maximums: maximums)
        }
    }

    @Test("Saving validates and overwrites the previous draft") func saveOverwritesPreviousDraft() throws {
        let (store, _, _) = makeStore()
        let first = try store.save(carbs: 20, fat: 10, protein: 5, maximums: Self.maximums, at: Self.now)
        let second = try store.save(carbs: 40, fat: 20, protein: 10, maximums: Self.maximums, at: Self.now)

        #expect(store.latest(at: Self.now) == second)
        #expect(store.consume(id: first.id, at: Self.now) == nil)
        #expect(store.latest(at: Self.now) == second)
    }

    @Test("A failed replacement clears the previous meal") func failedReplacementClearsPreviousDraft() throws {
        let (store, _, _) = makeStore()
        try store.save(carbs: 20, fat: 10, protein: 5, maximums: Self.maximums, at: Self.now)

        #expect(throws: AIMacrosDraftValidationError.carbsExceedsMaximum(100)) {
            try store.save(carbs: 101, fat: 10, protein: 5, maximums: Self.maximums, at: Self.now)
        }
        #expect(store.latest(at: Self.now) == nil)
    }

    @Test("Malformed and expired drafts are cleared") func malformedAndExpiredDraftsAreCleared() throws {
        let (store, defaults, key) = makeStore()
        defaults.set(Data("not json".utf8), forKey: key)
        #expect(store.latest(at: Self.now) == nil)
        #expect(defaults.data(forKey: key) == nil)

        let unsupportedSchema = AIMacrosDraft(carbs: 20, fat: 10, protein: 5, schemaVersion: 0)
        defaults.set(try JSONCoding.encoder.encode(unsupportedSchema), forKey: key)
        #expect(store.latest(at: Self.now) == nil)
        #expect(defaults.data(forKey: key) == nil)

        let future = AIMacrosDraft(carbs: 20, fat: 10, protein: 5, createdAt: Self.now.addingTimeInterval(1))
        defaults.set(try JSONCoding.encoder.encode(future), forKey: key)
        #expect(store.latest(at: Self.now) == nil)
        #expect(defaults.data(forKey: key) == nil)

        let expired = AIMacrosDraft(
            carbs: 20,
            fat: 10,
            protein: 5,
            createdAt: Self.now.addingTimeInterval(-AIMacrosDraftStore.defaultTimeToLive - 1)
        )
        defaults.set(try JSONCoding.encoder.encode(expired), forKey: key)
        #expect(store.latest(at: Self.now) == nil)
        #expect(defaults.data(forKey: key) == nil)
    }

    @Test("A draft expires at the exact 15-minute boundary") func expiresAtExactTimeToLiveBoundary() throws {
        let (store, defaults, key) = makeStore()
        try store.save(
            carbs: 20,
            fat: 10,
            protein: 5,
            maximums: Self.maximums,
            at: Self.now.addingTimeInterval(-AIMacrosDraftStore.defaultTimeToLive)
        )

        #expect(store.latest(at: Self.now) == nil)
        #expect(defaults.data(forKey: key) == nil)
    }

    @Test("Consuming a matching draft returns it once and clears it") func consumeIsOneTimeAndExactIDOnly() throws {
        let (store, _, _) = makeStore()
        let draft = try store.save(carbs: 20, fat: 10, protein: 5, maximums: Self.maximums, at: Self.now)

        #expect(store.consume(id: UUID(), at: Self.now) == nil)
        #expect(store.latest(at: Self.now) == draft)
        #expect(store.consume(id: draft.id, at: Self.now) == draft)
        #expect(store.consume(id: draft.id, at: Self.now) == nil)
        #expect(store.latest(at: Self.now) == nil)
    }
}
