#if DEBUG
    import SwiftUI

    /// Each type role with a sample of what it's for.
    struct TypographyGallery: View {
        var body: some View {
            GalleryCard {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Typography.allCases) { role in
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(sample(for: role))
                                .typography(role)
                                .foregroundStyle(.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            TokenName(".\(role.rawValue) · \(description(of: role))")
                        }
                        .padding(.vertical, Spacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                        if role != Typography.allCases.last {
                            Divider()
                        }
                    }
                }
            }
        }

        private func sample(for role: Typography) -> String {
            switch role {
            case .screenTitle: "Express"
            case .sectionTitle: "Nearby stops"
            case .cardTitle: "Times Sq–42 St"
            case .body: "Walk to 7 Av, then take the uptown train."
            case .bodyEmphasized: "Exit at the rear of the train."
            case .secondary: "Uptown · 2 min walk"
            case .caption: "Updated 18:30"
            case .captionEmphasized: "Delayed"
            case .time: "4 min · 18:42"
            case .timeLarge: "18:42"
            case .badge: "M15 SBS"
            case .button: "Start trip"
            }
        }

        private func description(of role: Typography) -> String {
            switch role {
            case .screenTitle: "Large Title, bold"
            case .sectionTitle: "Title 2, bold"
            case .cardTitle: "Headline"
            case .body: "Body"
            case .bodyEmphasized: "Body, semibold"
            case .secondary: "Subheadline"
            case .caption: "Caption"
            case .captionEmphasized: "Caption, semibold"
            case .time: "Title 3, rounded, tabular"
            case .timeLarge: "Large Title, rounded, tabular"
            case .badge: "Subheadline, rounded, bold"
            case .button: "Body, semibold"
            }
        }
    }
#endif
