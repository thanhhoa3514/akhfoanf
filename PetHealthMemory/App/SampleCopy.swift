import Foundation

/// Demo-data wording per screenshot language. Shared by the app (`SampleData`, UI-test mode only)
/// and the UI test target (which taps these titles and types `searchTerm`).
///
/// Data stored in models stays data: stable codes (species "Dog", event types) are mapped to the
/// user's language at display time. Only free text a person would have typed, or that is printed
/// on a local vet's document, is written in the local language here.
struct SampleCopy {
    struct Field {
        let value: String?
        let source: String
    }

    let clinicName: String
    let vetName: String
    let breed: String
    let rabies: String
    let combinedVaccine: String
    let medication: String
    let dosage: String
    let frequency: String
    let visitTitle: String
    let visitNotes: String
    let allergy: String
    let rabiesBooster: String
    let medicationRefill: String
    let skinRecheck: String
    let certificateTitle: String
    let certificateLines: [String]
    let reportTitle: String
    let reportLines: [String]
    // Extracted fields on the report (value, text on the page).
    let reportHeading: String
    let petNameSource: String
    let dateSource: String
    let weightSource: String
    let diagnosis: Field
    let medicationField: Field
    let dosageField: Field
    let frequencyField: Field
    let vaccineField: Field
    let nextDueSource: String
    /// Typed into Search for the App Store screenshot.
    let searchTerm: String

    static func forLanguage(_ code: String) -> SampleCopy {
        switch code.prefix(2) {
        case "de": .german
        case "fr": .french
        case "ja": .japanese
        default: .english
        }
    }

    static let english = SampleCopy(
        clinicName: "Riverside Animal Clinic", vetName: "Dr. Sarah Chen", breed: "Shiba Inu",
        rabies: "Rabies", combinedVaccine: "DHPP", medication: "Apoquel",
        dosage: "5.4 mg tablet", frequency: "Once daily with food",
        visitTitle: "Annual check-up", visitNotes: "Mild skin allergy. Recheck in 4 weeks.",
        allergy: "Chicken protein",
        rabiesBooster: "Rabies booster", medicationRefill: "Apoquel refill", skinRecheck: "Skin recheck",
        certificateTitle: "Rabies certificate",
        certificateLines: [
            "RIVERSIDE ANIMAL CLINIC", "Vaccination certificate", "",
            "Patient: MOCHI   Species: Canine   Breed: Shiba Inu",
            "Rabies - Nobivac 1yr      given 17/12/25",
            "Next due 17/12/26", "", "Dr. Sarah Chen",
        ],
        reportTitle: "Check-up report",
        reportLines: [
            "RIVERSIDE ANIMAL CLINIC", "Consultation report", "",
            "Patient: MOCHI    Date: 08/11/2026", "Wt 10.2kg",
            "Dx: mild atopic dermatitis",
            "Rx: Apoquel 5.4mg tab - 1 tab SID with food x 30d",
            "DHPPi booster given", "Recheck 4 wks  next due 11/12/27",
        ],
        reportHeading: "Consultation report", petNameSource: "Patient: MOCHI",
        dateSource: "Date: 08/11/2026", weightSource: "Wt 10.2kg",
        diagnosis: Field(value: "Mild atopic dermatitis", source: "Dx: mild atopic dermatitis"),
        medicationField: Field(value: "Apoquel 5.4mg", source: "Apoquel 5.4mg tab"),
        dosageField: Field(value: "1 tab", source: "1 tab"),
        frequencyField: Field(value: "SID with food", source: "SID with food"),
        vaccineField: Field(value: "DHPPi", source: "DHPPi booster given"),
        nextDueSource: "next due 11/12/27",
        searchTerm: "Rab"
    )

    static let german = SampleCopy(
        clinicName: "Tierarztpraxis am Stadtpark", vetName: "Dr. Anna Weber", breed: "Shiba Inu",
        rabies: "Tollwut", combinedVaccine: "SHPPi", medication: "Apoquel",
        dosage: "5,4-mg-Tablette", frequency: "1× täglich mit Futter",
        visitTitle: "Jahresuntersuchung", visitNotes: "Leichte Hautallergie. Kontrolle in 4 Wochen.",
        allergy: "Hühnerprotein",
        rabiesBooster: "Tollwut-Auffrischung", medicationRefill: "Apoquel nachkaufen", skinRecheck: "Hautkontrolle",
        certificateTitle: "Impfnachweis Tollwut",
        certificateLines: [
            "TIERARZTPRAXIS AM STADTPARK", "Impfbescheinigung", "",
            "Patient: MOCHI   Tierart: Hund   Rasse: Shiba Inu",
            "Tollwut - Nobivac T      geimpft 17.12.25",
            "Nächste Impfung 17.12.26", "", "Dr. Anna Weber",
        ],
        reportTitle: "Untersuchungsbericht",
        reportLines: [
            "TIERARZTPRAXIS AM STADTPARK", "Untersuchungsbericht", "",
            "Patient: MOCHI    Datum: 08.11.2026", "Gew. 10,2 kg",
            "Diagnose: leichte atopische Dermatitis",
            "Rx: Apoquel 5,4 mg Tbl. - 1 Tbl. 1x tägl. mit Futter, 30 Tage",
            "SHPPi Auffrischung erfolgt", "Kontrolle in 4 Wo.   nächste Impfung 11.12.27",
        ],
        reportHeading: "Untersuchungsbericht", petNameSource: "Patient: MOCHI",
        dateSource: "Datum: 08.11.2026", weightSource: "Gew. 10,2 kg",
        diagnosis: Field(value: "Leichte atopische Dermatitis", source: "Diagnose: leichte atopische Dermatitis"),
        medicationField: Field(value: "Apoquel 5,4 mg", source: "Apoquel 5,4 mg Tbl."),
        dosageField: Field(value: "1 Tbl.", source: "1 Tbl."),
        frequencyField: Field(value: "1x tägl. mit Futter", source: "1x tägl. mit Futter"),
        vaccineField: Field(value: "SHPPi", source: "SHPPi Auffrischung erfolgt"),
        nextDueSource: "nächste Impfung 11.12.27",
        searchTerm: "Toll"
    )

    static let french = SampleCopy(
        clinicName: "Clinique Vétérinaire du Parc", vetName: "Dr Claire Martin", breed: "Shiba Inu",
        rabies: "Rage", combinedVaccine: "CHPPi", medication: "Apoquel",
        dosage: "Comprimé de 5,4 mg", frequency: "1 fois par jour avec le repas",
        visitTitle: "Bilan annuel", visitNotes: "Légère allergie cutanée. Contrôle dans 4 semaines.",
        allergy: "Protéine de poulet",
        rabiesBooster: "Rappel rage", medicationRefill: "Racheter Apoquel", skinRecheck: "Contrôle de la peau",
        certificateTitle: "Certificat antirabique",
        certificateLines: [
            "CLINIQUE VÉTÉRINAIRE DU PARC", "Certificat de vaccination", "",
            "Patient : MOCHI   Espèce : Chien   Race : Shiba Inu",
            "Rage - Nobivac Rabies      faite le 17/12/25",
            "Prochain rappel 17/12/26", "", "Dr Claire Martin",
        ],
        reportTitle: "Compte rendu de consultation",
        reportLines: [
            "CLINIQUE VÉTÉRINAIRE DU PARC", "Compte rendu de consultation", "",
            "Patient : MOCHI    Date : 08/11/2026", "Poids 10,2 kg",
            "Diag. : dermatite atopique légère",
            "Rx : Apoquel 5,4 mg cp - 1 cp 1x/j avec repas, 30 j",
            "Rappel CHPPi effectué", "Contrôle dans 4 sem.   prochain rappel 11/12/27",
        ],
        reportHeading: "Compte rendu de consultation", petNameSource: "Patient : MOCHI",
        dateSource: "Date : 08/11/2026", weightSource: "Poids 10,2 kg",
        diagnosis: Field(value: "Dermatite atopique légère", source: "Diag. : dermatite atopique légère"),
        medicationField: Field(value: "Apoquel 5,4 mg", source: "Apoquel 5,4 mg cp"),
        dosageField: Field(value: "1 cp", source: "1 cp"),
        frequencyField: Field(value: "1x/j avec repas", source: "1x/j avec repas"),
        vaccineField: Field(value: "CHPPi", source: "Rappel CHPPi effectué"),
        nextDueSource: "prochain rappel 11/12/27",
        searchTerm: "Rag"
    )

    static let japanese = SampleCopy(
        clinicName: "さくら動物病院", vetName: "獣医師 佐藤 花子", breed: "柴犬",
        rabies: "狂犬病", combinedVaccine: "5種混合", medication: "アポキル",
        dosage: "5.4mg錠", frequency: "1日1回 食事と一緒に",
        visitTitle: "年次健康診断", visitNotes: "軽度の皮膚アレルギー。4週間後に再診。",
        allergy: "鶏肉タンパク",
        rabiesBooster: "狂犬病ワクチン追加接種", medicationRefill: "アポキル補充", skinRecheck: "皮膚の再診",
        certificateTitle: "狂犬病予防注射済証",
        certificateLines: [
            "さくら動物病院", "狂犬病予防注射証明書", "",
            "患者: もち   種類: 犬   犬種: 柴犬",
            "狂犬病ワクチン      接種日 2025/12/17",
            "次回 2026/12/17", "", "獣医師 佐藤 花子",
        ],
        reportTitle: "診察報告書",
        reportLines: [
            "さくら動物病院", "診察報告書", "",
            "患者: もち    日付: 2026/11/08", "体重 10.2kg",
            "診断: 軽度のアトピー性皮膚炎",
            "処方: アポキル 5.4mg錠 1日1回 食事と一緒に 30日分",
            "5種混合ワクチン 追加接種済み", "4週間後に再診   次回接種 2027/12/11",
        ],
        reportHeading: "診察報告書", petNameSource: "患者: もち",
        dateSource: "日付: 2026/11/08", weightSource: "体重 10.2kg",
        diagnosis: Field(value: "軽度のアトピー性皮膚炎", source: "診断: 軽度のアトピー性皮膚炎"),
        medicationField: Field(value: "アポキル 5.4mg", source: "アポキル 5.4mg錠"),
        dosageField: Field(value: "1錠", source: "5.4mg錠"),
        frequencyField: Field(value: "1日1回 食事と一緒に", source: "1日1回 食事と一緒に"),
        vaccineField: Field(value: "5種混合", source: "5種混合ワクチン 追加接種済み"),
        nextDueSource: "次回接種 2027/12/11",
        searchTerm: "狂犬"
    )
}
