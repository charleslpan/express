import TransitKit

/// The alert screens pushed onto the home sheet's stack (``AppRouter/homePath``); ``HomeSheet`` shows each with
/// ``AlertsDestinationView``.
enum AlertsDestination: Hashable {
    /// Every subway line, then the bus routes near the rider, each with its current alerts or "Good service".
    case lineStatus(nearbyBuses: [LineStatusLine])
    /// The full text of a line's alerts, as the MTA wrote them.
    case alerts([ServiceAlert], line: LineStatusLine?)
}

extension AppRouter {
    /// Opens line status from the home sheet's alert chip, with the sheet at full height.
    func showLineStatus(nearbyBuses: [LineStatusLine]) {
        homePath.append(AlertsDestination.lineStatus(nearbyBuses: nearbyBuses))
        homeDetent = .full
    }

    /// Opens the full text of `alerts` on `line`, from a banner on a departure row or in line status; the sheet rises
    /// from its peek to half height so there's room to read.
    func showAlerts(_ alerts: [ServiceAlert], on line: LineStatusLine?) {
        homePath.append(AlertsDestination.alerts(alerts, line: line))
        if homeDetent == .peek {
            homeDetent = .half
        }
    }
}
