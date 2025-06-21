//
//  KeyModApp.swift
//  KeyMod
//
//  Created by 彭志坚 on 2025/6/19.
//

import SwiftUI
import UIKit

@main
struct KeyModApp: App {
    init() {
        UIDevice.current.setValue(UIInterfaceOrientation.landscapeLeft.rawValue, forKey: "orientation")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
