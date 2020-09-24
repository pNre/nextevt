//
//  Preferences.swift
//  NextEvt
//
//  Created by Pierluigi D'Andrea on 16/09/2020.
//

import Foundation

struct Preferences {
    var showEventDuration: Bool {
        get { UserDefaults.standard.bool(forKey: "showEventDuration") }
        set { UserDefaults.standard.set(newValue, forKey: "showEventDuration") }
    }

    var useSmallerFont: Bool {
        get { UserDefaults.standard.bool(forKey: "useSmallerFont") }
        set { UserDefaults.standard.set(newValue, forKey: "useSmallerFont") }
    }
}
