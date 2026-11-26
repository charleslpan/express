import TransitKit

/// The alert screens pushed onto the home sheet's stack (``AppRouter/homePath``); ``HomeSheet`` shows each with
/// ``AlertsDestinationView``.
enum AlertsDestination: Hashable {
    /// The full text of a line's alerts, as the MTA wrote them.
    case alerts([ServiceAlert], line: LineStatusLine?)
}

extension AppRouter {
    /// Opens the full text of `alerts` on `line`, from a banner on a departure row; the sheet rises
    /// from its peek to half height so there's room to read.
    func showAlerts(_ alerts: [ServiceAlert], on line: LineStatusLine?) {
        homePath.append(AlertsDestination.alerts(alerts, line: line))
        if homeDetent == .peek {
            homeDetent = .half
        }
    }
}
