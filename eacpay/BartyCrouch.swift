import Foundation

enum BartyCrouch {
	enum SupportedLanguage: String {
		/* NOTE: remove unsupported languages from the following cases list & add any missing languages
		 When adding more localizations:
		 1. Copy the new label here in from the Strings.swift file
		 2. Include the English version
		 3. Go to a translator and add the localization within the Localizable file
		 4. Test
		 */
		case chineseSimplified = "zh-Hans"
		case chineseTraditional = "zh-Hant"
		case english = "en"
		case french = "fr"
		case german = "de"
		case indonesian = "id"
		case italian = "it"
		case japanese = "ja"
		case korean = "ko"
		case portuguese = "pt"
		case russian = "ru"
		case spanish = "es"
		case turkey = "tr"
		case ukrainian = "uk"
	}

	static func translate(key: String, translations: [SupportedLanguage: String], comment _: String? = nil) -> String {
		let typeName = String(describing: BartyCrouch.self)
		let methodName = #function

		print(
			"Warning: [BartyCrouch]",
			"Untransformed \(typeName).\(methodName) method call found with key '\(key)' and base translations '\(translations)'.",
			"Please ensure that BartyCrouch is installed and configured correctly."
		)

		// fall back in case something goes wrong with BartyCrouch transformation
		return "BC: TRANSFORMATION FAILED!"
	}
}
