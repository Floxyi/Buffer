import Foundation

protocol SettingsPersisting {
    func object(for key: SettingsKey) -> Any?
    func bool(for key: SettingsKey) -> Bool
    func integer(for key: SettingsKey) -> Int
    func string(for key: SettingsKey) -> String?
    func array(for key: SettingsKey) -> [Any]?
    func data(for key: SettingsKey) -> Data?
    func set(_ value: Any?, for key: SettingsKey)
    func removeObject(for key: SettingsKey)
}

struct UserDefaultsSettingsStore: SettingsPersisting {
    let defaults: UserDefaults

    func object(for key: SettingsKey) -> Any? {
        defaults.object(forKey: key.rawValue)
    }

    func bool(for key: SettingsKey) -> Bool {
        defaults.bool(forKey: key.rawValue)
    }

    func integer(for key: SettingsKey) -> Int {
        defaults.integer(forKey: key.rawValue)
    }

    func string(for key: SettingsKey) -> String? {
        defaults.string(forKey: key.rawValue)
    }

    func array(for key: SettingsKey) -> [Any]? {
        defaults.array(forKey: key.rawValue)
    }

    func data(for key: SettingsKey) -> Data? {
        defaults.data(forKey: key.rawValue)
    }

    func set(_ value: Any?, for key: SettingsKey) {
        defaults.set(value, forKey: key.rawValue)
    }

    func removeObject(for key: SettingsKey) {
        defaults.removeObject(forKey: key.rawValue)
    }
}
