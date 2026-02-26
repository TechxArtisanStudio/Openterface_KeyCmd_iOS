//
//  AIRequestHistoryView.swift
//  KeyMod
//
//  Created on 2026/2/26.
//

import SwiftUI

struct AIRequestHistoryView: View {
    @State private var requests: [AIRequestLog] = AIRequestHistoryManager.shared.getAllRequests()
    @State private var statistics: AIRequestStatistics = AIRequestHistoryManager.shared.getStatistics()
    @State private var expandedIds: Set<UUID> = []
    @State private var showDeleteConfirmation = false
    @State private var requestToDelete: UUID? = nil
    
    var onDismiss: (() -> Void)?
    
    init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
        print("[AIRequestHistoryView] Init called - loaded \(AIRequestHistoryManager.shared.getAllRequests().count) requests")
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Header with Close Button
            HStack {
                Text("Request History")
                    .font(.headline)
                Spacer()
                if onDismiss != nil {
                    Button(action: { onDismiss?() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding()
            
            // Statistics Summary
            if statistics.totalRequests > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Summary")
                        .font(.headline)
                    
                    HStack(spacing: 16) {
                        StatisticBox(
                            label: "Total Requests",
                            value: "\(statistics.totalRequests)",
                            color: .blue
                        )
                        
                        StatisticBox(
                            label: "Success Rate",
                            value: String(format: "%.1f%%", statistics.successRate),
                            color: statistics.successRate > 90 ? .green : .orange
                        )
                        
                        StatisticBox(
                            label: "Tokens Used",
                            value: formatTokenCount(statistics.totalTokensUsed),
                            color: .purple
                        )
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
            
            // Request List
            if requests.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    
                    Text("No Request History")
                        .font(.headline)
                    
                    Text("AI requests will appear here")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                List {
                    ForEach(requests.reversed()) { request in
                        VStack(alignment: .leading, spacing: 8) {
                            // Header
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                                        Text("\(request.provider) - \(request.model)")
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                        
                                        Spacer()
                                        
                                        if request.success {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                                .font(.caption)
                                        } else {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundColor(.red)
                                                .font(.caption)
                                        }
                                    }
                                    
                                    Text(request.formattedDate)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                
                                Button(action: {
                                    if expandedIds.contains(request.id) {
                                        print("[AIRequestHistoryView] Collapsing request \(request.id)")
                                        expandedIds.remove(request.id)
                                    } else {
                                        print("[AIRequestHistoryView] Expanding request \(request.id)")
                                        expandedIds.insert(request.id)
                                    }
                                }) {
                                    Image(systemName: expandedIds.contains(request.id) ? "chevron.up" : "chevron.down")
                                        .foregroundColor(.blue)
                                }
                            }
                            
                            // Expandable Content
                            if expandedIds.contains(request.id) {
                                Divider()
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    if !request.inputText.isEmpty {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Input")
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                            
                                            Text(request.inputText)
                                                .font(.caption)
                                                .lineLimit(3)
                                                .padding(8)
                                                .background(Color(.systemGray6))
                                                .cornerRadius(4)
                                        }
                                    }
                                    
                                    if !request.outputText.isEmpty {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Output")
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                            
                                            Text(request.outputText)
                                                .font(.caption)
                                                .lineLimit(3)
                                                .padding(8)
                                                .background(Color(.systemGray6))
                                                .cornerRadius(4)
                                        }
                                    }
                                    
                                    // Token Info
                                    HStack(spacing: 12) {
                                        Text(request.tokensInfo)
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                        
                                        if !request.success, let error = request.errorMessage {
                                            Text("Error: \(error)")
                                                .font(.caption2)
                                                .foregroundColor(.red)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 8)
                        .contextMenu {
                            Button(role: .destructive) {
                                print("[AIRequestHistoryView] Context menu delete clicked for \(request.id)")
                                requestToDelete = request.id
                                showDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            
            Spacer()
            
            // Action Buttons
            HStack(spacing: 12) {
                Button(role: .destructive) {
                    print("[AIRequestHistoryView] Clear All button clicked")
                    showDeleteConfirmation = true
                    requestToDelete = nil  // nil means delete all
                } label: {
                    Text("Clear All")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                if onDismiss != nil {
                    Button("Done") {
                        print("[AIRequestHistoryView] Done button clicked - calling onDismiss()")
                        onDismiss?()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(12)
        }
        .alert("Confirm Deletion", isPresented: $showDeleteConfirmation) {
            if requestToDelete == nil {
                Button("Delete All", role: .destructive) {
                    print("[AIRequestHistoryView] Delete All confirmed")
                    AIRequestHistoryManager.shared.clearAllRequests()
                    loadData()
                }
                Button("Cancel", role: .cancel) {
                    print("[AIRequestHistoryView] Delete All cancelled")
                }
            } else {
                Button("Delete", role: .destructive) {
                    if let id = requestToDelete {
                        print("[AIRequestHistoryView] Delete single request: \(id)")
                        AIRequestHistoryManager.shared.deleteRequest(id)
                        loadData()
                    }
                }
                Button("Cancel", role: .cancel) {
                    print("[AIRequestHistoryView] Delete cancelled")
                }
            }
        } message: {
            if requestToDelete == nil {
                Text("This will delete all request history. This action cannot be undone.")
            } else {
                Text("Delete this request?")
            }
        }
    }


    private func loadData() {
        print("[AIRequestHistoryView] loadData() called")
        requests = AIRequestHistoryManager.shared.getAllRequests()
        statistics = AIRequestHistoryManager.shared.getStatistics()
        print("[AIRequestHistoryView] loadData() completed - loaded \(requests.count) requests")
    }
    
    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        } else {
            return "\(count)"
        }
    }
}

// MARK: - Statistic Box Component
struct StatisticBox: View {
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline)
                .foregroundColor(color)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    AIRequestHistoryView(onDismiss: {})
}
