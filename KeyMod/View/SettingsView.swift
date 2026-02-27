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
                    Text("General").tag("general")
                    Text("Voice Input").tag("voice_input")
                    Text("AI Settings").tag("ai_settings")
                    Text("History").tag("history")
                }
                .pickerStyle(.segmented)
                .padding()
                
                // Content
                if selectedSettingsTab == "history" {
                    AIRequestHistoryView()
                } else {
                    Form {
                        if selectedSettingsTab == "general" {
                            GeneralSettingsView()
                        } else if selectedSettingsTab == "voice_input" {
                            WhisperSettingsView()
                        } else if selectedSettingsTab == "ai_settings" {
                            AISettingsView(
                                tempAPIKey: $tempAPIKey,
                                showAPIKeyField: $showAPIKeyField,
                                isTestingAPI: $isTestingAPI,
                                testResult: $testResult,
                                testError: $testError
                            )
                        }
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
