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

        /// Each role's sample text and the text style it's built on.
        private static let specimens: [Typography: (sample: String, style: String)] = [
            .screenTitle: ("Express", "Large Title, bold"),
            .sectionTitle: ("Nearby stops", "Title 2, bold"),
            .cardTitle: ("Times Sq–42 St", "Headline"),
            .body: ("Walk to 7 Av, then take the uptown train.", "Body"),
            .bodyEmphasized: ("Exit at the rear of the train.", "Body, semibold"),
            .secondary: ("Uptown · 2 min walk", "Subheadline"),
            .caption: ("Updated 18:30", "Caption"),
            .captionEmphasized: ("Delayed", "Caption, semibold"),
            .time: ("4 min · 18:42", "Title 3, rounded, tabular"),
            .timeLarge: ("18:42", "Large Title, rounded, tabular"),
            .badge: ("M15 SBS", "Subheadline, rounded, bold"),
            .button: ("Start trip", "Body, semibold"),
        ]

        private func sample(for role: Typography) -> String {
            Self.specimens[role]?.sample ?? role.rawValue
        }

        private func description(of role: Typography) -> String {
            Self.specimens[role]?.style ?? ""
        }
    }
#endif
