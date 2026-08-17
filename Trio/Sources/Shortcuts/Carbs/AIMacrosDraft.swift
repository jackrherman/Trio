import Foundation

/// A short-lived macro estimate received from the AI Macros Shortcut.
///
/// This is deliberately only a draft. Storing or consuming it never writes a
/// treatment, calculates insulin, or communicates with a pump.
struct AIMacrosDraft: Codable, Equatable {
    static let currentSchemaVersion = 1
    static let absoluteMaximumGrams = 300

    let schemaVersion: Int
    let id: UUID
    let carbs: Int
    let fat: Int
    let protein: Int
    let createdAt: Date

    init(
        id: UUID = UUID(),
        carbs: Int,
        fat: Int,
        protein: Int,
        createdAt: Date = Date(),
        schemaVersion: Int = AIMacrosDraft.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.carbs = carbs
        self.fat = fat
        self.protein = protein
        self.createdAt = createdAt
    }

    func validate(maximums: AIMacrosDraftMaximums) throws {
        guard carbs >= 0 else { throw AIMacrosDraftValidationError.negativeCarbs }
        guard fat >= 0 else { throw AIMacrosDraftValidationError.negativeFat }
        guard protein >= 0 else { throw AIMacrosDraftValidationError.negativeProtein }
        guard carbs > 0 || fat > 0 || protein > 0 else {
            throw AIMacrosDraftValidationError.emptyEstimate
        }
        guard carbs <= maximums.carbs else {
            throw AIMacrosDraftValidationError.carbsExceedsMaximum(maximums.carbs)
        }
        guard fat <= maximums.fat else {
            throw AIMacrosDraftValidationError.fatExceedsMaximum(maximums.fat)
        }
        guard protein <= maximums.protein else {
            throw AIMacrosDraftValidationError.proteinExceedsMaximum(maximums.protein)
        }
    }

    var isStructurallyValid: Bool {
        schemaVersion == Self.currentSchemaVersion &&
            carbs >= 0 && carbs <= Self.absoluteMaximumGrams &&
            fat >= 0 && fat <= Self.absoluteMaximumGrams &&
            protein >= 0 && protein <= Self.absoluteMaximumGrams &&
            (carbs > 0 || fat > 0 || protein > 0)
    }
}

struct AIMacrosDraftMaximums: Equatable {
    let carbs: Int
    let fat: Int
    let protein: Int
}

enum AIMacrosDraftValidationError: LocalizedError, Equatable {
    case negativeCarbs
    case negativeFat
    case negativeProtein
    case emptyEstimate
    case carbsExceedsMaximum(Int)
    case fatExceedsMaximum(Int)
    case proteinExceedsMaximum(Int)

    var errorDescription: String? {
        switch self {
        case .negativeCarbs:
            return String(localized: "Carbohydrates cannot be negative.")
        case .negativeFat:
            return String(localized: "Fat cannot be negative.")
        case .negativeProtein:
            return String(localized: "Protein cannot be negative.")
        case .emptyEstimate:
            return String(localized: "At least one macro value must be greater than zero.")
        case let .carbsExceedsMaximum(maximum):
            return String(localized: "Carbohydrates exceed your maximum of \(maximum) g.")
        case let .fatExceedsMaximum(maximum):
            return String(localized: "Fat exceeds your maximum of \(maximum) g.")
        case let .proteinExceedsMaximum(maximum):
            return String(localized: "Protein exceeds your maximum of \(maximum) g.")
        }
    }
}

/// Persists one latest AI macro draft for the treatment screen to review.
final class AIMacrosDraftStore {
    static let shared = AIMacrosDraftStore()

    static let defaultTimeToLive: TimeInterval = 15 * 60
    static let defaultKey = "aiMacros.latestDraft.v1"

    private let defaults: UserDefaults
    private let key: String
    private let timeToLive: TimeInterval
    private let lock = NSLock()

    init(
        defaults: UserDefaults = .standard,
        key: String = AIMacrosDraftStore.defaultKey,
        timeToLive: TimeInterval = AIMacrosDraftStore.defaultTimeToLive
    ) {
        self.defaults = defaults
        self.key = key
        self.timeToLive = timeToLive
    }

    /// Validates and overwrites the older draft. It does not create a treatment.
    @discardableResult func save(
        carbs: Int,
        fat: Int,
        protein: Int,
        maximums: AIMacrosDraftMaximums,
        at date: Date = Date()
    ) throws -> AIMacrosDraft {
        lock.lock()
        defer { lock.unlock() }

        // A failed new handoff must not leave the previous meal available.
        defaults.removeObject(forKey: key)

        let draft = AIMacrosDraft(carbs: carbs, fat: fat, protein: protein, createdAt: date)
        try draft.validate(maximums: maximums)

        let data = try JSONCoding.encoder.encode(draft)
        defaults.set(data, forKey: key)
        return draft
    }

    /// Loads the current valid draft, clearing malformed and expired payloads.
    func latest(at now: Date = Date()) -> AIMacrosDraft? {
        lock.lock()
        defer { lock.unlock() }
        return loadCurrentDraft(at: now)
    }

    /// Returns and clears the current draft only when the exact ID still matches.
    func consume(id: UUID, at now: Date = Date()) -> AIMacrosDraft? {
        lock.lock()
        defer { lock.unlock() }

        guard let draft = loadCurrentDraft(at: now), draft.id == id else { return nil }
        defaults.removeObject(forKey: key)
        return draft
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        defaults.removeObject(forKey: key)
    }

    private func loadCurrentDraft(at now: Date) -> AIMacrosDraft? {
        guard let data = defaults.data(forKey: key),
              let draft = try? JSONCoding.decoder.decode(AIMacrosDraft.self, from: data),
              draft.isStructurallyValid,
              draft.createdAt <= now,
              now < draft.createdAt.addingTimeInterval(timeToLive)
        else {
            defaults.removeObject(forKey: key)
            return nil
        }
        return draft
    }
}
