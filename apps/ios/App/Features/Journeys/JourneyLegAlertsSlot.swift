import SwiftUI
import TransitKit

/// The spot at the top of each leg in a journey's plan where its service alerts go: empty until A4 fills it with a
/// banner per alert on the leg's line or stops (MOTIS sends them on the leg and its places).
///
/// It draws nothing yet, so it takes no room; give it a banner and each walk and ride card shows it above the rest.
struct JourneyLegAlertsSlot: View {
    /// The leg the alerts are for, as MOTIS planned it (and as the latest refresh left it).
    let leg: Leg

    var body: some View {
        EmptyView()
    }
}
