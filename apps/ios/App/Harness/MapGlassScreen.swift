import SwiftUI
import TransitKit

/// A debug screen for judging Liquid Glass over the Google map: the map over New York with glass buttons, a glass
/// status chip, and a glass sheet on top. Only the screenshot harness shows it (`-screenshot map-glass`).
struct MapGlassScreen: View {
    @State private var camera = MapCamera.newYork
    @State private var tilesRendered = false

    var body: some View {
        MapView(
            camera: $camera,
            polylines: [Self.lexingtonAvenue],
            markers: Self.stops,
            onTilesRendered: { tilesRendered = true }
        )
        .ignoresSafeArea()
        .overlay(alignment: .topLeading) {
            StatusChip(isConfigured: GoogleMapsServices.isConfigured, tilesRendered: tilesRendered)
                .padding()
        }
        .overlay(alignment: .topTrailing) {
            MapControls()
                .padding()
        }
        .sheet(isPresented: .constant(true)) {
            NearbySheet()
                .presentationDetents([.fraction(0.35), .medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .interactiveDismissDisabled()
        }
    }

    /// The 4/5/6 along Lexington Avenue, roughly, so a polyline shows under the glass.
    private static let lexingtonAvenue = MapPolyline(
        id: "lex",
        coordinates: [
            Coordinate(latitude: 40.7046, longitude: -74.0141),
            Coordinate(latitude: 40.7134, longitude: -74.0040),
            Coordinate(latitude: 40.7306, longitude: -73.9913),
            Coordinate(latitude: 40.7519, longitude: -73.9770),
            Coordinate(latitude: 40.7625, longitude: -73.9675),
        ],
        color: .green
    )

    private static let stops = [
        MapMarker(
            id: "union-sq",
            coordinate: Coordinate(latitude: 40.7359, longitude: -73.9906),
            title: "14 St–Union Sq"
        ),
        MapMarker(
            id: "gct",
            coordinate: Coordinate(latitude: 40.7519, longitude: -73.9770),
            title: "Grand Central–42 St"
        ),
    ]
}

/// Says whether the map has drawn, which the screenshot test waits on (`map.settled`) before capturing.
private struct StatusChip: View {
    let isConfigured: Bool
    let tilesRendered: Bool

    var body: some View {
        Label(text, systemImage: isConfigured ? "map" : "key.slash")
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassOrOpaque(in: Capsule())
            .accessibilityIdentifier(tilesRendered ? "map.settled" : "map.loading")
    }

    private var text: String {
        if !isConfigured {
            return "No Maps key"
        }
        return tilesRendered ? "Tiles rendered" : "Loading tiles…"
    }
}

/// A column of glass buttons, the kind every map screen will float over the map.
private struct MapControls: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(spacing: 12) {
                button("Show my location", systemImage: "location.fill")
                button("Map layers", systemImage: "square.3.layers.3d")
                button("Service alerts", systemImage: "exclamationmark.triangle.fill")
            }
        }
    }

    @ViewBuilder
    private func button(_ title: String, systemImage: String) -> some View {
        let button = Button(title, systemImage: systemImage) {}
            .labelStyle(.iconOnly)
            .font(.title3)
            .buttonBorderShape(.circle)
            .controlSize(.large)
        if reduceTransparency {
            button.buttonStyle(.borderedProminent).tint(Color(uiColor: .secondarySystemBackground))
                .foregroundStyle(.primary)
        } else {
            button.buttonStyle(.glass)
        }
    }
}

/// Stand-in content for the glass sheet: a few departures, so text over glass over map can be judged.
private struct NearbySheet: View {
    private struct Departure: Identifiable {
        var route: String
        var headsign: String
        var wait: String
        var id: String {
            route
        }
    }

    private let departures = [
        Departure(route: "4", headsign: "Woodlawn", wait: "2 min"),
        Departure(route: "5", headsign: "Eastchester–Dyre Av", wait: "5 min"),
        Departure(route: "6", headsign: "Pelham Bay Park", wait: "7 min"),
        Departure(route: "L", headsign: "8 Av", wait: "3 min"),
    ]

    var body: some View {
        NavigationStack {
            List(departures) { departure in
                HStack(spacing: 12) {
                    Text(departure.route)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(minWidth: 32, minHeight: 32)
                        .background(departure.route == "L" ? Color.gray : Color.green, in: Circle())
                        .accessibilityLabel("\(departure.route) train")
                    Text(departure.headsign)
                    Spacer()
                    Text(departure.wait)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Union Square")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private extension View {
    /// Liquid Glass in `shape`, or an opaque background when Reduce Transparency is on.
    func glassOrOpaque(in shape: some Shape) -> some View {
        modifier(GlassOrOpaque(shape: shape))
    }
}

private struct GlassOrOpaque<S: Shape>: ViewModifier {
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(uiColor: .secondarySystemBackground), in: shape)
        } else {
            content.glassEffect(.regular, in: shape)
        }
    }
}

#Preview {
    MapGlassScreen()
}
