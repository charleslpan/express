import GlassUI
import SwiftUI
import TransitKit

/// When to travel: leave now, depart at a time, or arrive by one, on New York's clock. Done hands back the new time;
/// Cancel hands back nil.
struct JourneyTimePicker: View {
    private enum Mode: Hashable {
        case now
        case departAt
        case arriveBy
    }

    let now: Date
    let onDone: (PlanRequest.Time?) -> Void

    @State private var mode: Mode
    @State private var date: Date
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(time: PlanRequest.Time, now: Date, onDone: @escaping (PlanRequest.Time?) -> Void) {
        self.now = now
        self.onDone = onDone
        switch time {
        case .now:
            _mode = State(initialValue: .now)
            _date = State(initialValue: now)
        case let .departAt(date):
            _mode = State(initialValue: .departAt)
            _date = State(initialValue: date)
        case let .arriveBy(date):
            _mode = State(initialValue: .arriveBy)
            _date = State(initialValue: date)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("When")
                .typography(.cardTitle)
                .foregroundStyle(.textPrimary)
                .accessibilityAddTraits(.isHeader)
            modePicker
            if mode != .now {
                DatePicker(
                    mode == .arriveBy ? "Arrive by" : "Depart at",
                    selection: $date,
                    in: now...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .environment(\.timeZone, JourneyClock.timeZone)
                .accessibilityIdentifier("journeys.time-wheel")
            }
            AdaptiveStack(spacing: Spacing.xs) {
                Button("Cancel") {
                    onDone(nil)
                }
                .buttonStyle(.bordered)
                Button("Done") {
                    onDone(time)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("journeys.time-done")
            }
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .typography(.button)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("journeys.time-picker")
    }

    @ViewBuilder
    private var modePicker: some View {
        let picker = Picker("When", selection: $mode) {
            Text("Leave Now").tag(Mode.now)
            Text("Depart At").tag(Mode.departAt)
            Text("Arrive By").tag(Mode.arriveBy)
        }
        // Three segments can't fit their titles at accessibility sizes; a menu can.
        if dynamicTypeSize.isAccessibilitySize {
            picker.pickerStyle(.menu)
        } else {
            picker.pickerStyle(.segmented)
        }
    }

    private var time: PlanRequest.Time {
        switch mode {
        case .now: .now
        case .departAt: .departAt(max(date, now))
        case .arriveBy: .arriveBy(max(date, now))
        }
    }
}
