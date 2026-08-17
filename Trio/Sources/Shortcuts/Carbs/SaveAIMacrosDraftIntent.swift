import AppIntents
import Foundation
import Swinject

/// Saves a reviewed-later macro draft from Shortcuts. It never logs a treatment.
struct SaveAIMacrosDraftIntent: AppIntent {
    static var title: LocalizedStringResource = "Save AI Macros"

    static var description = IntentDescription(
        "Save estimated meal macros for review in Trio before logging a treatment."
    )

    @Parameter(
        title: "Carbohydrates",
        description: "Estimated carbohydrates in whole grams",
        controlStyle: .field,
        inclusiveRange: (lowerBound: 0, upperBound: 300)
    ) var carbs: Int

    @Parameter(
        title: "Fat",
        description: "Estimated fat in whole grams",
        controlStyle: .field,
        inclusiveRange: (lowerBound: 0, upperBound: 300)
    ) var fat: Int

    @Parameter(
        title: "Protein",
        description: "Estimated protein in whole grams",
        controlStyle: .field,
        inclusiveRange: (lowerBound: 0, upperBound: 300)
    ) var protein: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Save \(\.$carbs) g carbs, \(\.$fat) g fat, and \(\.$protein) g protein")
    }

    @MainActor func perform() async throws -> some ProvidesDialog {
        // This invocation supersedes any earlier meal, even if validation fails.
        AIMacrosDraftStore.shared.clear()

        guard let settingsManager = TrioApp.resolver.resolve(SettingsManager.self) else {
            return .result(dialog: IntentDialog(stringLiteral: String(localized: "Trio settings are unavailable.")))
        }

        let maximums = AIMacrosDraftMaximums(
            carbs: Int(truncating: settingsManager.settings.maxCarbs as NSDecimalNumber),
            fat: Int(truncating: settingsManager.settings.maxFat as NSDecimalNumber),
            protein: Int(truncating: settingsManager.settings.maxProtein as NSDecimalNumber)
        )
        do {
            try AIMacrosDraftStore.shared.save(
                carbs: carbs,
                fat: fat,
                protein: protein,
                maximums: maximums
            )
        } catch let error as AIMacrosDraftValidationError {
            return .result(dialog: IntentDialog(stringLiteral: error.localizedDescription))
        } catch {
            return .result(dialog: IntentDialog(stringLiteral: String(localized: "AI Macros could not be saved.")))
        }
        return .result(
            dialog: IntentDialog(
                stringLiteral: String(
                    localized: "AI Macros saved for review: \(carbs) g carbs, \(fat) g fat, \(protein) g protein."
                )
            )
        )
    }
}
