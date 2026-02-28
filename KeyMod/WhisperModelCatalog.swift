//
//  WhisperModelCatalog.swift
//  KeyMod
//
//  Created on 2026/2/28.
//

import Foundation

// MARK: - Data Models

/// A single Whisper model entry as defined in WhisperModelsCatalog.json (or a remote equivalent).
struct WhisperModelSpec: Codable, Identifiable, Equatable, Hashable {
    /// Stable identifier stored in UserDefaults to remember the user's selection (e.g. "en", "multi", "yue").
    let id: String
    /// Human-readable name shown in the settings UI.
    let displayName: String
    /// Local filename inside the `whisper_models/` directory.
    let fileName: String
    /// Remote URL used to download the model binary.
    let downloadURL: String
    /// Approximate file size in bytes – used for disk-space checks and progress estimation.
    let expectedFileSize: Int
    /// BCP-47 / whisper.cpp language tag (e.g. "en", "auto", "yue").
    let language: String
}

/// Top-level structure of the catalog JSON.
struct WhisperModelCatalogData: Codable {
    /// Schema version – increment when the format changes in a breaking way.
    let version: Int
    /// Optional HTTPS URL for the live catalog. When set, `WhisperModelCatalog` will
    /// attempt to refresh models at launch and cache the result for offline use.
    let remoteCatalogURL: String?
    let models: [WhisperModelSpec]
}

// MARK: - Catalog Manager

/// Loads the list of available Whisper models from the bundled JSON and, optionally, from a
/// remote server URL specified inside that JSON.  Views and managers should read from
/// `WhisperModelCatalog.shared.models` rather than hard-coding model details.
class WhisperModelCatalog: ObservableObject {

    static let shared = WhisperModelCatalog()

    /// All available models. Initialised from the bundled JSON; updated if a remote catalog
    /// is fetched successfully.
    @Published private(set) var models: [WhisperModelSpec] = []
    /// True while a remote refresh is in progress.
    @Published private(set) var isRefreshing: Bool = false
    /// Non-nil if the last remote refresh attempt failed.
    @Published private(set) var refreshError: String? = nil

    private let logger = LogManager.shared
    private let cacheKey = "WhisperModelCatalog.cachedRemoteCatalog"

    private init() {
        // 1. Start with bundled models immediately (synchronous, always works offline).
        models = loadBundled().models
        // 2. Overlay any previously cached remote catalog (also synchronous).
        if let cached = loadCachedRemote() {
            models = cached.models
            logger.log("Whisper catalog loaded from cache: \(models.count) model(s)", category: "WhisperCatalog")
        }
    }

    // MARK: - Public API

    /// Returns the model with the given id, or the first model in the list as a fallback.
    func spec(for id: String) -> WhisperModelSpec? {
        models.first { $0.id == id } ?? models.first
    }

    /// Fetches the remote catalog URL (defined inside the bundled JSON) and updates `models`.
    /// Caches the result in UserDefaults so it is available offline on next launch.
    /// Safe to call multiple times – concurrent calls are serialised.
    @MainActor
    func refreshFromRemoteIfNeeded() async {
        guard !isRefreshing else { return }

        let bundled = loadBundled()
        guard let urlString = bundled.remoteCatalogURL, let url = URL(string: urlString) else {
            logger.log("No remoteCatalogURL configured – skipping remote refresh", category: "WhisperCatalog")
            return
        }

        isRefreshing = true
        refreshError = nil
        defer { isRefreshing = false }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let catalog = try JSONDecoder().decode(WhisperModelCatalogData.self, from: data)
            guard !catalog.models.isEmpty else {
                throw NSError(domain: "WhisperModelCatalog", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "Remote catalog contained no models"])
            }
            // Persist and apply
            UserDefaults.standard.set(data, forKey: cacheKey)
            models = catalog.models
            logger.log("Whisper catalog refreshed from remote: \(models.count) model(s) (v\(catalog.version))",
                       category: "WhisperCatalog")
        } catch {
            refreshError = error.localizedDescription
            logger.log("Whisper catalog remote refresh failed: \(error)", category: "WhisperCatalog")
        }
    }

    // MARK: - Private helpers

    private func loadBundled() -> WhisperModelCatalogData {
        guard
            let url = Bundle.main.url(forResource: "WhisperModelsCatalog", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let catalog = try? JSONDecoder().decode(WhisperModelCatalogData.self, from: data)
        else {
            logger.log("WhisperModelsCatalog.json missing or malformed – using empty catalog",
                       category: "WhisperCatalog")
            return WhisperModelCatalogData(version: 1, remoteCatalogURL: nil, models: [])
        }
        return catalog
    }

    private func loadCachedRemote() -> WhisperModelCatalogData? {
        guard
            let data = UserDefaults.standard.data(forKey: cacheKey),
            let catalog = try? JSONDecoder().decode(WhisperModelCatalogData.self, from: data)
        else { return nil }
        return catalog
    }
}
