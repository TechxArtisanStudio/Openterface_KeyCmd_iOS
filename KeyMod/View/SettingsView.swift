//
//  SettingsView.swift
//  KeyMod
//
//  Created by System on 2025/7/15.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.presentationMode) var presentationMode
    
    @State private var tempAPIKey = ""
    @State private var showAPIKeyField = false
    @State private var isTestingAPI = false
    @State private var testResult: String?
    @State private var testError: String?
    @State private var selectedSettingsTab: String = "general"
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Tab Switcher
                Picker("Settings Tab", selection: $selectedSettingsTab) {
                    Text("General Settings").tag("general")
                    Text("AI Settings").tag("ai_settings")
                }
                .pickerStyle(.segmented)
                .padding()
                
                // Content Form
                Form {
                    if selectedSettingsTab == "general" {
                        GeneralSettingsView()
                    } else if selectedSettingsTab == "ai_settings" {
                        AITestingSettingsView(
                            tempAPIKey: $tempAPIKey,
                            showAPIKeyField: $showAPIKeyField,
                            isTestingAPI: $isTestingAPI,
                            testResult: $testResult,
                            testError: $testError
                        )
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarItems(
                trailing: Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
