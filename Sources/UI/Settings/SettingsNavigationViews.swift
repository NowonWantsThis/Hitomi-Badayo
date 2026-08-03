import SwiftUI

struct SettingsSidebarView: View {
    let title: String
    let searchPlaceholder: String
    let clearSearchHelp: String
    let categories: [SettingsWindowCategory]
    @Binding var filter: String
    @Binding var selectedCategory: SettingsWindowCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                TextField(searchPlaceholder, text: $filter)
                    .textFieldStyle(.roundedBorder)
                if !filter.trimmed.isEmpty {
                    Button {
                        filter = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .help(clearSearchHelp)
                }
            }

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(categories) { category in
                        SettingsCategorySidebarButton(
                            category: category,
                            isSelected: selectedCategory == category
                        ) {
                            selectedCategory = category
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 190, alignment: .topLeading)
        .background(.bar)
    }
}

struct SettingsHeaderView: View {
    let category: SettingsWindowCategory
    let closeHelp: String
    let close: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            SettingsCategoryIcon(category: category, size: 18)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(category.label)
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(category.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: close) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .help(closeHelp)
            .accessibilityIdentifier("settings.close")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.bar)
    }
}

struct SettingsCategorySidebarButton: View {
    let category: SettingsWindowCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                SettingsCategoryIcon(category: category, size: 17)
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? .primary : .secondary)

                Text(category.label)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.001))
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .overlay {
            Rectangle()
                .fill(Color.primary.opacity(0.001))
                .contentShape(Rectangle())
                .onTapGesture(perform: action)
                .accessibilityHidden(true)
        }
        .help(category.label)
        .accessibilityLabel(category.label)
        .accessibilityHint(category.detail)
        .accessibilityIdentifier("settings.category.\(category.rawValue)")
    }
}

struct SettingsCategoryIcon: View {
    let category: SettingsWindowCategory
    let size: CGFloat

    @ViewBuilder
    var body: some View {
        if let letter = category.iconLetter {
            ZStack {
                Circle()
                    .strokeBorder(lineWidth: max(1, size * 0.075))
                Text(letter)
                    .font(.system(size: size * 0.64, weight: .semibold, design: .rounded))
            }
            .frame(width: size, height: size)
        } else {
            Image(systemName: category.systemImage)
                .font(.system(size: size))
        }
    }
}
