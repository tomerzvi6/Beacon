import Foundation

/// UI strings for the caregiver reporting screen, per supported language.
/// The family side of the app stays Hebrew; only the caregiver kiosk screen
/// uses these. Adding a language: add a `CaregiverLanguage` case and a
/// matching `strings(for:)` entry here.
struct CaregiverStrings {
    let screenTitle: String
    let greeting: String

    let mealSection: String
    let ateWell: String
    let ateLittle: String
    let didNotEat: String

    let hydrationSection: String
    let drankEnough: String
    let drankLittle: String
    let didNotDrink: String

    let sleepSection: String
    let sleptWell: String
    let sleptPoorly: String

    let painSection: String
    let nauseaSection: String
    let fatigueSection: String
    let levelNone: String
    let levelSevere: String

    let medicationSection: String
    let medicationTaken: String
    let medicationMissed: String
    let medicationNotSure: String

    let noteSection: String
    let notePlaceholder: String

    let submitButton: String
    let submittedTitle: String
    let submittedMessage: String
    let closeButton: String

    static func strings(for language: CaregiverLanguage) -> CaregiverStrings {
        switch language {
        case .english:   return english
        case .tagalog:   return tagalog
        case .hindi:     return hindi
        case .malayalam: return malayalam
        case .tamil:     return tamil
        }
    }

    // MARK: - English

    private static let english = CaregiverStrings(
        screenTitle: "Daily Update",
        greeting: "How is the patient today?",
        mealSection: "Food",
        ateWell: "Ate well",
        ateLittle: "Ate a little",
        didNotEat: "Did not eat",
        hydrationSection: "Drinking",
        drankEnough: "Drank enough",
        drankLittle: "Drank a little",
        didNotDrink: "Did not drink",
        sleepSection: "Sleep",
        sleptWell: "Slept well",
        sleptPoorly: "Slept poorly",
        painSection: "Pain",
        nauseaSection: "Nausea",
        fatigueSection: "Weakness",
        levelNone: "None",
        levelSevere: "Severe",
        medicationSection: "Medication",
        medicationTaken: "Taken",
        medicationMissed: "Missed",
        medicationNotSure: "Not sure",
        noteSection: "Message to the family",
        notePlaceholder: "Write anything else here...",
        submitButton: "Send update",
        submittedTitle: "Thank you!",
        submittedMessage: "The family received your update.",
        closeButton: "Close"
    )

    // MARK: - Tagalog

    private static let tagalog = CaregiverStrings(
        screenTitle: "Pang-araw-araw na Ulat",
        greeting: "Kumusta ang pasyente ngayon?",
        mealSection: "Pagkain",
        ateWell: "Kumain nang mabuti",
        ateLittle: "Kumain nang kaunti",
        didNotEat: "Hindi kumain",
        hydrationSection: "Pag-inom",
        drankEnough: "Uminom nang sapat",
        drankLittle: "Uminom nang kaunti",
        didNotDrink: "Hindi uminom",
        sleepSection: "Tulog",
        sleptWell: "Natulog nang mahimbing",
        sleptPoorly: "Hindi nakatulog nang maayos",
        painSection: "Sakit",
        nauseaSection: "Pagduduwal",
        fatigueSection: "Panghihina",
        levelNone: "Wala",
        levelSevere: "Matindi",
        medicationSection: "Gamot",
        medicationTaken: "Nainom",
        medicationMissed: "Hindi nainom",
        medicationNotSure: "Hindi sigurado",
        noteSection: "Mensahe sa pamilya",
        notePlaceholder: "Isulat dito ang iba pa...",
        submitButton: "Ipadala ang ulat",
        submittedTitle: "Salamat!",
        submittedMessage: "Natanggap ng pamilya ang iyong ulat.",
        closeButton: "Isara"
    )

    // MARK: - Hindi

    private static let hindi = CaregiverStrings(
        screenTitle: "दैनिक रिपोर्ट",
        greeting: "मरीज़ आज कैसे हैं?",
        mealSection: "खाना",
        ateWell: "अच्छा खाया",
        ateLittle: "थोड़ा खाया",
        didNotEat: "नहीं खाया",
        hydrationSection: "पानी",
        drankEnough: "पर्याप्त पिया",
        drankLittle: "थोड़ा पिया",
        didNotDrink: "नहीं पिया",
        sleepSection: "नींद",
        sleptWell: "अच्छी नींद",
        sleptPoorly: "ख़राब नींद",
        painSection: "दर्द",
        nauseaSection: "मतली",
        fatigueSection: "कमज़ोरी",
        levelNone: "नहीं",
        levelSevere: "बहुत",
        medicationSection: "दवाई",
        medicationTaken: "ले ली",
        medicationMissed: "नहीं ली",
        medicationNotSure: "पक्का नहीं",
        noteSection: "परिवार के लिए संदेश",
        notePlaceholder: "यहाँ कुछ और लिखें...",
        submitButton: "रिपोर्ट भेजें",
        submittedTitle: "धन्यवाद!",
        submittedMessage: "परिवार को आपकी रिपोर्ट मिल गई।",
        closeButton: "बंद करें"
    )

    // MARK: - Malayalam

    private static let malayalam = CaregiverStrings(
        screenTitle: "ദിവസ റിപ്പോർട്ട്",
        greeting: "രോഗി ഇന്ന് എങ്ങനെയുണ്ട്?",
        mealSection: "ഭക്ഷണം",
        ateWell: "നന്നായി കഴിച്ചു",
        ateLittle: "കുറച്ച് കഴിച്ചു",
        didNotEat: "കഴിച്ചില്ല",
        hydrationSection: "വെള്ളം",
        drankEnough: "മതിയായത്ര കുടിച്ചു",
        drankLittle: "കുറച്ച് കുടിച്ചു",
        didNotDrink: "കുടിച്ചില്ല",
        sleepSection: "ഉറക്കം",
        sleptWell: "നന്നായി ഉറങ്ങി",
        sleptPoorly: "ശരിയായി ഉറങ്ങിയില്ല",
        painSection: "വേദന",
        nauseaSection: "ഓക്കാനം",
        fatigueSection: "ക്ഷീണം",
        levelNone: "ഇല്ല",
        levelSevere: "കഠിനം",
        medicationSection: "മരുന്ന്",
        medicationTaken: "കഴിച്ചു",
        medicationMissed: "കഴിച്ചില്ല",
        medicationNotSure: "ഉറപ്പില്ല",
        noteSection: "കുടുംബത്തിനുള്ള സന്ദേശം",
        notePlaceholder: "മറ്റെന്തെങ്കിലും ഇവിടെ എഴുതുക...",
        submitButton: "റിപ്പോർട്ട് അയയ്ക്കുക",
        submittedTitle: "നന്ദി!",
        submittedMessage: "കുടുംബത്തിന് നിങ്ങളുടെ റിപ്പോർട്ട് ലഭിച്ചു.",
        closeButton: "അടയ്ക്കുക"
    )

    // MARK: - Tamil

    private static let tamil = CaregiverStrings(
        screenTitle: "தினசரி அறிக்கை",
        greeting: "நோயாளி இன்று எப்படி இருக்கிறார்?",
        mealSection: "உணவு",
        ateWell: "நன்றாக சாப்பிட்டார்",
        ateLittle: "கொஞ்சம் சாப்பிட்டார்",
        didNotEat: "சாப்பிடவில்லை",
        hydrationSection: "தண்ணீர்",
        drankEnough: "போதுமான அளவு குடித்தார்",
        drankLittle: "கொஞ்சம் குடித்தார்",
        didNotDrink: "குடிக்கவில்லை",
        sleepSection: "தூக்கம்",
        sleptWell: "நன்றாக தூங்கினார்",
        sleptPoorly: "சரியாக தூங்கவில்லை",
        painSection: "வலி",
        nauseaSection: "குமட்டல்",
        fatigueSection: "சோர்வு",
        levelNone: "இல்லை",
        levelSevere: "கடுமை",
        medicationSection: "மருந்து",
        medicationTaken: "எடுத்தார்",
        medicationMissed: "எடுக்கவில்லை",
        medicationNotSure: "உறுதியில்லை",
        noteSection: "குடும்பத்திற்கு செய்தி",
        notePlaceholder: "வேறு ஏதேனும் இங்கே எழுதவும்...",
        submitButton: "அறிக்கையை அனுப்பவும்",
        submittedTitle: "நன்றி!",
        submittedMessage: "உங்கள் அறிக்கை குடும்பத்திற்கு கிடைத்தது.",
        closeButton: "மூடு"
    )
}
