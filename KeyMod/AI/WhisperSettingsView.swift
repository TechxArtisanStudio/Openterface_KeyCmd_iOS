//
//  WhisperSettingsView.swift
//  KeyMod
//
//  Created on 2026/2/27.
//

import SwiftUI

struct WhisperSettingsView: View {
    @ObservedObject private var aiSettings = AISettings.shared
    @ObservedObject private var modelManager = WhisperModelManager.shared
    @ObservedObject private var catalog = WhisperModelCatalog.shared
    @State private var showRestartAlert = false
    @State private var showDownloadConfirm = false
    @State private var showDeleteConfirm = false

    var body: some View {
        Group {
            enginePickerSection
            languageSection
            whisperModelSection
            whisperInfoSection
        }
        .alert("Restart App Required", isPresented: $showRestartAlert) {
            Button("OK") { }
        } message: {
            Text("Please restart the app to apply the speech engine change.")
        }
        .confirmationDialog("Download Whisper Model?", isPresented: $showDownloadConfirm) {
            Button("Download") { downloadModel() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will download approximately \(modelManager.selectedModel.expectedFileSize / 1_000_000) MB. Make sure you have sufficient storage and a good network connection.")
        }
        .confirmationDialog("Delete Whisper Model?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { deleteModel() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will delete the downloaded model file and free up approximately \(modelManager.selectedModel.expectedFileSize / 1_000_000) MB of storage.")
        }
    }
    
    private var enginePickerSection: some View {
        let engineBinding = Binding(
            get: { aiSettings.sttEngine },
            set: { aiSettings.sttEngine = $0 }
        )
        
        return Section("Speech Recognition Engine") {
            Picker("STT Engine", selection: engineBinding) {
                Text("Apple Voice Input").tag(SpeechEngineType.apple)
                Text("Whisper (Local)").tag(SpeechEngineType.whisper)
            }
            .pickerStyle(.segmented)
            .onChange(of: engineBinding.wrappedValue) { _ in
                showRestartAlert = true
            }
            
            if aiSettings.sttEngine == .whisper {
                Text("Whisper requires the model to be downloaded. Restart the app after switching to use the new engine.")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.top, 8)
            }
        }
    }

    private var languageSection: some View {
        Section("Recognition Language") {
            Picker("Language", selection: Binding(
                get: { aiSettings.sttLocale },
                set: { aiSettings.sttLocale = $0 }
            )) {
                ForEach(STTLanguage.supported) { lang in
                    Text(lang.displayName).tag(lang.id)
                }
            }
            .pickerStyle(.menu)

            // Warn when Whisper multilingual model is needed for the selected language
            if aiSettings.sttEngine == .whisper
                && aiSettings.currentSTTLanguage.whisperCode != "en"
                && modelManager.selectedModel.language != "auto"
                && modelManager.selectedModel.language != aiSettings.currentSTTLanguage.whisperCode {
                Text("The selected language requires a multilingual Whisper model. Please select the \"Multilingual\" model below.")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private var whisperModelSection: some View {
        if aiSettings.sttEngine == .whisper {
            Section("Whisper Model") {
                VStack(spacing: 12) {
                    // Model type picker – populated from the catalog (bundle or remote)
                    Picker("Model", selection: Binding(
                        get: { modelManager.selectedModel },
                        set: { modelManager.selectedModel = $0 }
                    )) {
                        ForEach(catalog.models) { model in
                            Text(model.displayName).tag(model)
                        }
                    }
                    .pickerStyle(.menu)

                    modelStatusDisplay
                    if let error = modelManager.downloadError {
                        downloadErrorView(error)
                    }
                    downloadButtonsRow
                }
                .padding(.vertical, 8)
            }
        }
    }
    
    private var modelStatusDisplay: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(modelManager.selectedModel.fileName)
                    .font(.headline)
                Text("Approx. \(modelManager.selectedModel.expectedFileSize / 1_000_000) MB")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            statusBadge
        }
    }
    
    @ViewBuilder
    private var statusBadge: some View {
        if modelManager.isDownloaded {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Downloaded")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        } else if modelManager.isDownloading {
            HStack(spacing: 4) {
                ProgressView(value: modelManager.downloadProgress)
                    .frame(width: 30)
                Text("\(Int(modelManager.downloadProgress * 100))%")
                    .font(.caption)
            }
        } else {
            Text("Not downloaded")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private func downloadErrorView(_ error: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.red)
            Text(error)
                .font(.caption)
                .foregroundColor(.red)
                .lineLimit(3)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.red.opacity(0.1))
        .cornerRadius(4)
    }
    
    private var downloadButtonsRow: some View {
        HStack(spacing: 10) {
            if !modelManager.isDownloaded && !modelManager.isDownloading {
                downloadButton
            }
            
            if modelManager.isDownloading {
                downloadingButton
            }
            
            if modelManager.isDownloaded {
                deleteButton
            }
        }
    }
    
    private var downloadButton: some View {
                Button(action: { showDownloadConfirm = true }) {
            HStack(spacing: 6) {
                Image(systemName: "icloud.and.arrow.down.fill")
                Text("Download Model")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(6)
        }
    }
    
    private var downloadingButton: some View {
        Button(action: {}) {
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Downloading...")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.3))
            .foregroundColor(.gray)
            .cornerRadius(6)
        }
        .disabled(true)
    }
    
    private var deleteButton: some View {
        Button(action: { showDeleteConfirm = true }) {
            HStack(spacing: 6) {
                Image(systemName: "trash.fill")
                Text("Delete")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.red.opacity(0.2))
            .foregroundColor(.red)
            .cornerRadius(6)
        }
    }
    
    @ViewBuilder
    private var whisperInfoSection: some View {
        if aiSettings.sttEngine == .whisper {
            Section("Why Whisper?") {
                VStack(alignment: .leading, spacing: 8) {
                    benefitRow(icon: "checkmark.circle.fill", color: .green, text: "Works offline with no internet required")
                    benefitRow(icon: "checkmark.circle.fill", color: .green, text: "Better accuracy for technical terms and accents")
                    benefitRow(icon: "checkmark.circle.fill", color: .green, text: "No transcription data sent to servers")
                }
            }
        } else {
            Section("Apple Voice Input") {
                VStack(alignment: .leading, spacing: 8) {
                    benefitRow(icon: "checkmark.circle.fill", color: .blue, text: "Fast and optimized for Apple devices")
                    benefitRow(icon: "checkmark.circle.fill", color: .blue, text: "No extra downloads required")
                    benefitRow(icon: "checkmark.circle.fill", color: .blue, text: "Uses Apple's advanced speech recognition")
                }
            }
        }
    }
    
    private func benefitRow(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.caption)
            Text(text)
                .font(.caption)
        }
    }
    
    private func downloadModel() {
        Task {
            do {
                try await modelManager.downloadModel()
            } catch {
                LogManager.shared.log("Model download failed: \(error)", category: "WhisperSettings")
            }
        }
    }
    
    private func deleteModel() {
        do {
            try modelManager.deleteModel()
        } catch {
            LogManager.shared.log("Model deletion failed: \(error)", category: "WhisperSettings")
        }
    }
}

struct WhisperSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        Form {
            WhisperSettingsView()
        }
    }
}
