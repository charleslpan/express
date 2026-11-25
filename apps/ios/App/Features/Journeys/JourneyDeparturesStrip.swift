import GlassUI
import SwiftUI
import TransitKit

/// A route's next departures in its plan, side by side: when each leaves, how long until then, and how it stands on
/// live times. Tapping one opens that departure's plan and map. The open one is outlined, as the selected option is on
/// the list. A plain fill rather than glass, since the plan sits in the sheet's glass.
struct JourneyDeparturesStrip: View {
    let departures: [JourneySummary]
    /// The id of the departure open.
    let selectedID: String
    let now: Date
    /// Whether the plan says its times may not be real time, which mutes live times.
    let mayNotBeRealTime: Bool
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Next departures")
                .typography(.captionEmphasized)
                .foregroundStyle(.textSecondary)
                .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Spacing.xs) {
                    ForEach(departures) { departure in
                        chip(departure)
                    }
                }
                // Room for the selected outline, which the scroll view would otherwise clip.
                .padding(2)
            }
            .scrollClipDisabled()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("journey.departures")
    }

    private func chip(_ departure: JourneySummary) -> some View {
        let isSelected = departure.id == selectedID
        let status = status(of: departure)
        return Button {
            onSelect(departure.id)
        } label: {
            VStack(alignment: .leading, spacing: Spacing.xxxs) {
                Text(JourneyClock.time(leaves(departure)))
                    .typography(.bodyEmphasized)
                    .monospacedDigit()
                    .foregroundStyle(.textPrimary)
                Text(countdown(departure))
                    .typography(.caption)
                    .foregroundStyle(.textSecondary)
                if let note = note(for: status) {
                    Text(note)
                        .typography(.captionEmphasized)
                        .foregroundStyle(JourneyText.color(of: status))
                }
            }
            .multilineTextAlignment(.leading)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .frame(minWidth: 88, alignment: .leading)
            .background(
                isSelected ? AnyShapeStyle(Color.brand.opacity(0.14)) : AnyShapeStyle(.fill.quaternary),
                in: Radius.shape(Radius.md)
            )
            .overlay {
                if isSelected {
                    Radius.shape(Radius.md).strokeBorder(Color.brand, lineWidth: 2)
                }
            }
            .contentShape(Radius.shape(Radius.md))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(departure, status: status))
        .accessibilityHint(isSelected ? "" : String(localized: "Shows this departure step by step, and on the map"))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("journey.departure")
    }

    private func leaves(_ departure: JourneySummary) -> Date {
        departure.firstRideDeparture ?? departure.departure
    }

    /// "Now" or "4 min": the wait for the first ride, as the options list counts it.
    private func countdown(_ departure: JourneySummary) -> String {
        CountdownFormat.string(minutes: departure.minutesUntilDeparture(from: now))
    }

    private func status(of departure: JourneySummary) -> DepartureStatus {
        DepartureStatus(
            delayMinutes: departure.firstRideDelayMinutes,
            isRealtime: departure.isRealtime,
            isCancelled: false,
            realtimeIsStale: mayNotBeRealTime
        )
    }

    /// What the status adds to the time: "3 min late", "2 min early", or that it may not be real time. Nothing for
    /// a time on schedule or on the timetable alone, so the strip stays quiet.
    private func note(for status: DepartureStatus) -> String? {
        switch status {
        case .scheduled, .onTime: nil
        default: status.text
        }
    }

    private func accessibilityLabel(_ departure: JourneySummary, status: DepartureStatus) -> String {
        let minutes = departure.minutesUntilDeparture(from: now)
        let when = minutes <= 0 ? String(localized: "now") : String(localized: "in \(minutes) minutes")
        return [String(localized: "Leaves at \(JourneyClock.time(leaves(departure)))"), when, note(for: status)]
            .compactMap(\.self)
            .joined(separator: ", ")
    }
}
