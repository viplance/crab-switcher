import Carbon
import Foundation

struct KeyboardLanguage {
    let id: String
    let name: String
}

enum LanguageCycle {
    static func nextID(currentID: String?, selectedIDs: Set<String>, availableIDs: [String]) -> String? {
        let selected = availableIDs.filter(selectedIDs.contains)
        guard let first = selected.first else { return nil }
        guard selected.count > 1,
              let currentID,
              let index = selected.firstIndex(of: currentID)
        else { return first }
        return selected[(index + 1) % selected.count]
    }
}

final class KeyboardLayoutSwitcher {
    private let selectedLanguagesKey = "selectedLanguageInputSourceIDs"

    var selectedLanguageIDs: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: selectedLanguagesKey) ?? [])
    }

    func availableLanguages() -> [KeyboardLanguage] {
        selectableSources().map {
            KeyboardLanguage(id: sourceID($0), name: localizedName($0))
        }
    }

    func toggleLanguageSelection(id: String) {
        var selected = selectedLanguageIDs
        if selected.remove(id) == nil { selected.insert(id) }
        UserDefaults.standard.set(Array(selected).sorted(), forKey: selectedLanguagesKey)
    }

    func selectNextLanguage() {
        let sources = selectableSources()
        let currentID = currentInputSource().map(sourceID)
        guard let nextID = LanguageCycle.nextID(
            currentID: currentID,
            selectedIDs: selectedLanguageIDs,
            availableIDs: sources.map(sourceID)
        ), let nextSource = sources.first(where: { sourceID($0) == nextID }) else { return }
        TISSelectInputSource(nextSource)
    }

    func currentShortTitle() -> String {
        guard let source = currentInputSource() else { return "??" }
        if let language = stringArrayProp(source, kTISPropertyInputSourceLanguages).first,
           let code = language.split(whereSeparator: { $0 == "-" || $0 == "_" }).first {
            return code.uppercased()
        }
        return String(localizedName(source).prefix(3)).uppercased()
    }

    private func currentInputSource() -> TISInputSource? {
        TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
    }

    private func selectableSources() -> [TISInputSource] {
        guard let sources = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource]
        else { return [] }
        return sources.filter {
            stringProp($0, kTISPropertyInputSourceCategory) == kTISCategoryKeyboardInputSource as String
                && boolProp($0, kTISPropertyInputSourceIsEnabled)
                && boolProp($0, kTISPropertyInputSourceIsSelectCapable)
                && !sourceID($0).isEmpty
        }.sorted {
            let comparison = localizedName($0).localizedStandardCompare(localizedName($1))
            return comparison == .orderedSame ? sourceID($0) < sourceID($1) : comparison == .orderedAscending
        }
    }

    private func localizedName(_ source: TISInputSource) -> String {
        stringProp(source, kTISPropertyLocalizedName) ?? sourceID(source)
    }

    private func sourceID(_ source: TISInputSource) -> String {
        stringProp(source, kTISPropertyInputSourceID) ?? ""
    }

    private func stringProp(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }

    private func stringArrayProp(_ source: TISInputSource, _ key: CFString) -> [String] {
        guard let raw = TISGetInputSourceProperty(source, key) else { return [] }
        return Unmanaged<CFArray>.fromOpaque(raw).takeUnretainedValue() as? [String] ?? []
    }

    private func boolProp(_ source: TISInputSource, _ key: CFString) -> Bool {
        guard let raw = TISGetInputSourceProperty(source, key) else { return false }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(raw).takeUnretainedValue())
    }
}
