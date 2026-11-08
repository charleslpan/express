import Foundation
import GlassUI
import SwiftUI
import TransitKit

// What the stop and trip screens share: TransitKit's values as GlassUI's, the station clock, and the cards that stand
// in for departures (a message, the "may not be real time" notice).

extension TransitLine {
    /// A line from its bullet, in the feed's own colours: a bullet or diamond for subway lines, a pill for buses
    /// ("M14A SBS").
    init(bullet: LineBullet, mode: TransitMode, id: String? = nil) {
        self.init(
            id: id,
            name: bullet.text.replacingOccurrences(of: "-SBS", with: " SBS"),
            mode: TravelMode(mode),
            color: bullet.color.map(LineColor.init) ?? .unknownLine,
            textColor: bullet.textColor.map(LineColor.init),
            isExpress: bullet.shape == .diamond
        )
    }
}

extension FormatStyle where Self == Date.FormatStyle {
    /// Times as on the station's clock: New York's, wherever the phone is set ("6:42 PM").
    static var stationClock: Date.FormatStyle {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        return style
    }
}

extension DepartureStatus {
    /// The colour the status reads in: green on time or early, amber late, red cancelled, else secondary.
    var color: Color {
        switch self {
        case .onTime, .early: .statusOnTime
        case .late: .statusDelayed
        case .cancelled: .statusDisrupted
        case .scheduled, .uncertain: .textSecondary
        }
    }
}

/// A message in place of a stop's departures or a trip's stops, such as "You're Offline", with what the rider can
/// do about it. A plain fill, since it sits inside the sheet's glass.
struct StopsMessage<Actions: View>: View {
    private let title: LocalizedStringKey
    private let systemImage: String
    private let message: Text
    private let actions: Actions

    init(
        _ title: LocalizedStringKey,
        systemImage: String,
        message: Text,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.systemImage = systemImage
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Label {
                    Text(title)
                        .foregroundStyle(.textPrimary)
                } icon: {
                    Image(systemName: systemImage)
                        .foregroundStyle(.textSecondary)
                }
                .typography(.cardTitle)
                message
                    .typography(.secondary)
                    .foregroundStyle(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            actions
                .typography(.button)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
        }
        .padding(Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.tertiary, in: Radius.shape(Radius.lg))
    }
}

extension StopsMessage where Actions == EmptyView {
    init(_ title: LocalizedStringKey, systemImage: String, message: Text) {
        self.init(title, systemImage: systemImage, message: message) {}
    }
}

/// The message for a failed fetch: offline, or the server couldn't be reached, with Try Again.
struct StopsFailureMessage: View {
    let error: TransitError
    /// What's missing, for the message: "Departures" or "This trip".
    let subject: LocalizedStringKey
    let retry: () -> Void

    var body: some View {
        StopsMessage(
            error == .offline ? "You're Offline" : "Can't Load Times",
            systemImage: error == .offline ? "wifi.slash" : "exclamationmark.triangle",
            message: error == .offline
                ? Text("\(Text(subject)) will show once you're connected.")
                : Text("Express couldn't reach its server. Try again in a moment.")
        ) {
            Button("Try Again", action: retry)
        }
    }
}

/// The notice the MTA's terms require while times may not be real time: the data is over a minute old.
struct StopsNotRealTimeNotice: View {
    /// The accessibility identifier the screenshot harness waits on, such as `stop.not-real-time`.
    let identifier: String

    var body: some View {
        Label {
            Text("Times may not be real time")
                .foregroundStyle(.textPrimary)
        } icon: {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .foregroundStyle(.statusDelayed)
        }
        .typography(.captionEmphasized)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(.fill.tertiary, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

/// What a pushed stop or trip screen refreshes by: whether it may refresh now, and the rider's Try Again count,
/// which restarts it.
struct StopsRefreshKey: Equatable {
    var isActive: Bool
    var attempt: Int
}
