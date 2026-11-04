import GlassUI
import SwiftUI

/// The About sheet: the app's version, where its data comes from, and the notices its data and SDK licenses ask for.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    header
                }
                Section {
                    realtimeNote
                } header: {
                    Text("Times")
                }
                Section {
                    attribution(
                        "Metropolitan Transportation Authority",
                        detail: """
                        Subway, bus, and Staten Island Railway schedules, live times, and service alerts are \
                        provided by the MTA. Express is not endorsed by or affiliated with the MTA.
                        """,
                        link: "https://www.mta.info/developers"
                    )
                    attribution(
                        "OpenStreetMap",
                        detail: "Walking directions use map data © OpenStreetMap contributors, under the ODbL.",
                        link: "https://www.openstreetmap.org/copyright"
                    )
                    attribution(
                        "Google Maps Platform",
                        detail: "Maps and place search are provided by Google. Map data © Google.",
                        link: "https://cloud.google.com/maps-platform/terms"
                    )
                } header: {
                    Text("Data")
                }
                Section {
                    notice("Google Maps SDK for iOS", license: "Google Maps Platform Terms of Service")
                    notice("Google Places SDK for iOS", license: "Google Maps Platform Terms of Service")
                    notice("MOTIS", license: "MIT License")
                    Link(destination: URL(string: "https://policies.google.com/privacy")!) {
                        Label("Google Privacy Policy", systemImage: "hand.raised")
                    }
                } header: {
                    Text("Open-Source and Legal Notices")
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            // The screenshot harness waits for the sheet before it captures.
            .accessibilityIdentifier("about.sheet")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text("Express")
                .typography(.sectionTitle)
                .foregroundStyle(.textPrimary)
            Text("Version \(Self.version)")
                .typography(.secondary)
                .foregroundStyle(.textSecondary)
            Text("An ad-free way around New York City.")
                .typography(.secondary)
                .foregroundStyle(.textSecondary)
        }
        .padding(.vertical, Spacing.xxs)
        .accessibilityElement(children: .combine)
    }

    /// The MTA's terms ask apps to say when times may not be real time.
    private var realtimeNote: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            RealtimeBadge(DepartureTime(minutes: 6, status: .uncertain))
            Text("""
            Times marked this way may not be real time: they come from the timetable, or from live data that \
            hasn't updated recently. Check signs in the station when it matters.
            """)
            .typography(.secondary)
            .foregroundStyle(.textSecondary)
        }
        .padding(.vertical, Spacing.xxs)
        .accessibilityElement(children: .combine)
    }

    private func attribution(_ title: LocalizedStringKey, detail: LocalizedStringKey, link: String) -> some View {
        Link(destination: URL(string: link)!) {
            VStack(alignment: .leading, spacing: Spacing.xxxs) {
                Text(title)
                    .typography(.bodyEmphasized)
                    .foregroundStyle(.textPrimary)
                Text(detail)
                    .typography(.secondary)
                    .foregroundStyle(.textSecondary)
            }
            .padding(.vertical, Spacing.xxs)
        }
        .accessibilityHint("Opens their terms in Safari.")
    }

    private func notice(_ name: LocalizedStringKey, license: LocalizedStringKey) -> some View {
        LabeledContent {
            Text(license)
                .typography(.secondary)
                .foregroundStyle(.textSecondary)
        } label: {
            Text(name)
                .typography(.body)
                .foregroundStyle(.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }

    /// The marketing version and build number, such as "0.1.0 (42)".
    static var version: String {
        let info = Bundle.main.infoDictionary
        let marketing = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(marketing) (\(build))"
    }
}

#Preview {
    Text(verbatim: "")
        .sheet(isPresented: .constant(true)) {
            AboutView()
        }
}
