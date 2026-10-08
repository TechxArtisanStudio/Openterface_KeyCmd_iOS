//
//  KeyboardLayoutSettingsView.swift
//  KeyMod
//
//  Settings view for keyboard layout selection.
//

import SwiftUI

struct KeyboardLayoutSettingsView: View {
    @ObservedObject private var aiSettings = AISettings.shared
    @ObservedObject private var layoutManager = KeyboardLayoutManager.shared

    var body: some View {
        Form {
            // MARK: - Auto Detection Section
            Section(header: Text("自动检测")) {
                Toggle("自动检测键盘布局", isOn: $layoutManager.autoDetectLocale)

                if layoutManager.autoDetectLocale {
                    HStack {
                        Text("检测到的布局")
                        Spacer()
                        Text(layoutManager.currentKeyboardLocale.displayName)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // MARK: - Manual Selection Section
            Section(header: Text("手动选择")) {
                if !layoutManager.autoDetectLocale {
                    Picker("键盘布局", selection: $layoutManager.currentKeyboardLocale) {
                        ForEach(KeyboardLocale.allCases) { locale in
                            HStack {
                                Text(locale.displayName)
                                Text("(\(locale.rawValue))")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                            .tag(locale)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
            }

            // MARK: - Current Layout Info Section
            Section(header: Text("当前布局")) {
                HStack {
                    Text("布局名称")
                    Spacer()
                    Text(layoutManager.activeLayoutName)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("目标系统")
                    Spacer()
                    Text(aiSettings.targetOS.displayName)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("物理标准")
                    Spacer()
                    Text(layoutManager.currentKeyboardLocale.physicalStandard.rawValue)
                        .foregroundColor(.secondary)
                }

                if layoutManager.currentKeyboardLocale.physicalStandard == .iso {
                    HStack {
                        Text("AltGr 支持")
                        Spacer()
                        Text(layoutManager.activeLayout.metadata.hasAltGr ? "是" : "否")
                            .foregroundColor(.secondary)
                    }
                }
            }

            // MARK: - Preview Section
            Section(header: Text("布局预览")) {
                KeyboardLayoutPreviewView(layout: layoutManager.activeLayout)
                    .frame(height: 200)
            }

            // MARK: - Info Section
            Section(footer: Text("键盘布局决定了按键的物理排列和标签。选择与您实际使用的物理键盘匹配的布局，以确保正确的按键映射。")) {
                NavigationLink("查看所有支持的布局") {
                    SupportedLayoutsListView()
                }
            }
        }
        .navigationTitle("键盘布局")
    }
}

// MARK: - Keyboard Layout Preview

struct KeyboardLayoutPreviewView: View {
    let layout: KeyboardLayoutDefinition

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 4) {
                ForEach(Array(layout.rows.enumerated()), id: \.offset) { rowIndex, row in
                    HStack(spacing: 4) {
                        ForEach(Array(row.enumerated()), id: \.offset) { keyIndex, key in
                            KeyPreviewView(key: key)
                                .frame(
                                    width: calculateKeyWidth(key: key, availableWidth: geometry.size.width),
                                    height: calculateRowHeight(rowIndex: rowIndex, availableHeight: geometry.size.height)
                                )
                        }
                    }
                }
            }
            .padding(8)
        }
        .background(Color(UIColor.systemGray6))
        .cornerRadius(8)
    }

    private func calculateKeyWidth(key: KeyDefinition, availableWidth: CGFloat) -> CGFloat {
        let baseWidth = (availableWidth - 8 * 2 - CGFloat(key.keyName.count) * 4) / CGFloat(layout.rows.first?.count ?? 14)
        return baseWidth * (key.widthMultiplier ?? 1.0)
    }

    private func calculateRowHeight(rowIndex: Int, availableHeight: CGFloat) -> CGFloat {
        let totalHeight = availableHeight - 8 * 2
        if let rowHeights = layout.metadata.rowHeights {
            return totalHeight * CGFloat(rowHeights[rowIndex])
        }
        return totalHeight / CGFloat(layout.rows.count)
    }
}

struct KeyPreviewView: View {
    let key: KeyDefinition

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(UIColor.systemGray5))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color(UIColor.systemGray4), lineWidth: 1)
                )

            VStack(spacing: 2) {
                if let shiftLabel = key.shiftLabel {
                    Text(shiftLabel)
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                }

                Text(key.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.primary)

                if let altGrLabel = key.altGrLabel {
                    Text(altGrLabel)
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                }
            }
            .padding(2)
        }
    }
}

// MARK: - Supported Layouts List

struct SupportedLayoutsListView: View {
    var body: some View {
        List {
            ForEach(KeyboardLocale.allCases) { locale in
                Section(header: Text(locale.displayName)) {
                    HStack {
                        Text("代码")
                        Spacer()
                        Text(locale.rawValue)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("物理标准")
                        Spacer()
                        Text(locale.physicalStandard.rawValue)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("支持的系统")
                        Spacer()
                        Text("Windows, macOS, Linux")
                            .foregroundColor(.secondary)
                    }

                    if let description = getLayoutDescription(for: locale) {
                        HStack {
                            Text("特点")
                            Spacer()
                            Text(description)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }
        }
        .navigationTitle("支持的布局")
    }

    private func getLayoutDescription(for locale: KeyboardLocale) -> String? {
        switch locale {
        case .us:
            return "标准美式 QWERTY 布局"
        case .uk:
            return "英式布局，£ 在 3 键上"
        case .de:
            return "德式 QWERTZ 布局，Z 和 Y 互换"
        case .fr:
            return "法式 AZERTY 布局"
        case .es:
            return "西班牙式布局，带 Ñ 键"
        case .it:
            return "意大利式布局，支持重音符号"
        case .pt:
            return "葡萄牙式布局，带 Ç 键"
        case .jp:
            return "日式 JIS 布局，带特殊键"
        case .cn:
            return "中文美式布局（同 US）"
        case .ca:
            return "加拿大布局"
        case .au:
            return "澳大利亚布局（同 UK）"
        case .be:
            return "比利时 AZERTY 布局"
        case .ch:
            return "瑞士 QWERTZ 布局"
        case .nordic:
            return "北欧布局，带 Å, Ä, Ö"
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationView {
        KeyboardLayoutSettingsView()
    }
}
