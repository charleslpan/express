import GlassUI
import SwiftUI
import TransitKit

/// The journey's from, to, and time: each end a menu (current location, or search for a place), a button that swaps
/// them, and the time ("Leave now", "Depart 7:15 PM", "Arrive by 8:00 PM") as a chip that opens the time picker.
/// Filled rather than glass, since it sits in the sheet's glass.
struct JourneyControls: View {
    enum End {
        case from
        case to
    }

    let query: JourneyQuery
    let now: Date
    let onChooseFrom: () -> Void
    let onChooseTo: () -> Void
    let onUseCurrentLocation: (End) -> Void
    let onSwap: () -> Void
    let onChooseTime: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // At accessibility sizes the ends take the full width, and the swap button goes under them.
            if dynamicTypeSize.isAccessibilitySize {
                ends
                swapButton
            } else {
                HStack(spacing: Spacing.xs) {
                    ends
                    swapButton
                }
            }
            Button(action: onChooseTime) {
                Label(timeTitle, systemImage: "clock")
                    .typography(.button)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .accessibilityHint("Choose when to leave or when to arrive")
            .accessibilityIdentifier("journeys.time")
        }
    }

    private var ends: some View {
        VStack(spacing: 0) {
            endRow(.from)
            Divider()
                .padding(.leading, Spacing.md)
            endRow(.to)
        }
        .background(.fill.tertiary, in: Radius.shape(Radius.md))
    }

    private var swapButton: some View {
        Button("Swap start and end", systemImage: "arrow.up.arrow.down", action: onSwap)
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .accessibilityIdentifier("journeys.swap")
    }

    private func endRow(_ end: End) -> some View {
        let endpoint = end == .from ? query.from : query.to
        let title: LocalizedStringKey = end == .from ? "From" : "To"
        return Menu {
            Button("Current Location", systemImage: "location.fill") {
                onUseCurrentLocation(end)
            }
            Button("Search for a Place", systemImage: "magnifyingglass") {
                end == .from ? onChooseFrom() : onChooseTo()
            }
        } label: {
            HStack(spacing: Spacing.sm) {
                // At accessibility sizes the icon sits by the label, leaving the name the row's whole width.
                if !dynamicTypeSize.isAccessibilitySize {
                    icon(for: endpoint)
                }
                VStack(alignment: .leading, spacing: Spacing.xxxs) {
                    HStack(spacing: Spacing.xxs) {
                        if dynamicTypeSize.isAccessibilitySize {
                            icon(for: endpoint)
                        }
                        Text(title)
                    }
                    .typography(.caption)
                    .foregroundStyle(.textSecondary)
                    Text(name(of: endpoint))
                        .typography(.body)
                        .foregroundStyle(.textPrimary)
                        .multilineTextAlignment(.leading)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title) + Text(verbatim: ", ") + Text(name(of: endpoint)))
        .accessibilityHint(end == .from ? "Choose where to start" : "Choose where to go")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(end == .from ? "journeys.from" : "journeys.to")
    }

    private func icon(for endpoint: JourneyEndpoint) -> some View {
        Image(systemName: endpoint.isCurrentLocation ? "location.fill" : "mappin.circle.fill")
            .foregroundStyle(endpoint.isCurrentLocation ? Color.brand : Color.red)
            .accessibilityHidden(true)
    }

    private func name(of endpoint: JourneyEndpoint) -> String {
        switch endpoint {
        case .currentLocation: String(localized: "Current Location")
        case let .place(place): place.name
        }
    }

    private var timeTitle: String {
        switch query.time {
        case .now: String(localized: "Leave now")
        case let .departAt(date): String(localized: "Depart \(JourneyClock.dayAndTime(date, relativeTo: now))")
        case let .arriveBy(date): String(localized: "Arrive by \(JourneyClock.dayAndTime(date, relativeTo: now))")
        }
    }
}
