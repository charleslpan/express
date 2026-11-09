#if DEBUG
    import SwiftUI

    /// Mode icons and every sample line's pill, regular and compact, and how text colour is picked.
    struct LinesGallery: View {
        var body: some View {
            VStack(spacing: Spacing.md) {
                GalleryCard(title: "Mode icons") {
                    FlowLayout(spacing: Spacing.sm) {
                        ForEach([TravelMode.walk, .bus, .subway, .rail]) { mode in
                            HStack(spacing: Spacing.xs) {
                                ModeIcon(mode, style: .tile)
                                ModeIcon(mode)
                                    .foregroundStyle(.textPrimary)
                            }
                        }
                    }
                }
                GalleryCard(title: "Subway") {
                    FlowLayout(spacing: Spacing.xs) {
                        ForEach(TransitLine.samples.filter { $0.mode == .subway }) { LinePill($0) }
                    }
                }
                GalleryCard(title: "Bus and SIR") {
                    FlowLayout(spacing: Spacing.xs) {
                        ForEach(TransitLine.samples.filter { $0.mode != .subway }) { LinePill($0) }
                    }
                }
                GalleryCard(title: "Compact") {
                    FlowLayout(spacing: Spacing.xxs) {
                        ForEach(TransitLine.samples) { LinePill($0, size: .compact) }
                    }
                }
                GalleryCard(title: "Text colour without the feed's") {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        ForEach(Self.contrastSamples, id: \.self) { hex in
                            contrastRow(hex)
                        }
                    }
                }
            }
        }

        /// Yellow and light blue take black; red and dark blue take white.
        private static let contrastSamples = ["FCCC0A", "00AEEF", "EE352E", "0039A6"]

        private func contrastRow(_ hex: String) -> some View {
            let color = LineColor(hex: hex) ?? .black
            let line = TransitLine(name: "Q", mode: .subway, color: color)
            let text = color.legibleText == .white ? "white" : "black"
            return AdaptiveRow {
                LinePill(line)
                TokenName(
                    "#\(hex) → \(text), \(String(format: "%.1f", color.contrastRatio(with: color.legibleText))):1"
                )
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("#\(hex), \(text) text")
        }
    }

    /// Journeys as segment bars, with each leg's minutes underneath.
    struct JourneysGallery: View {
        var body: some View {
            GalleryCard(title: "Segment bars") {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    ForEach(JourneyLeg.sampleJourneys.indices, id: \.self) { index in
                        let legs = JourneyLeg.sampleJourneys[index]
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            JourneySegmentBar(legs: legs)
                            Text(summary(legs))
                                .typography(.caption)
                                .foregroundStyle(.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
        }

        private func summary(_ legs: [JourneyLeg]) -> String {
            let total = legs.map(\.minutes).reduce(0, +)
            let parts = legs.map { leg -> String in
                switch leg.kind {
                case .walk: "walk \(leg.minutes)"
                case let .ride(line): "\(line.name)\(line.isExpress ? "X" : "") \(leg.minutes)"
                }
            }
            return "\(total) min · " + parts.joined(separator: " → ")
        }
    }

    /// Realtime states one by one, then departure rows as a stop's card shows them.
    struct DeparturesGallery: View {
        private static let states: [(title: String, departure: DepartureTime)] = [
            ("Live", DepartureTime(minutes: 3, status: .live)),
            ("Scheduled", DepartureTime(minutes: 12, status: .scheduled)),
            ("Delayed", DepartureTime(minutes: 7, status: .delayed(minutes: 4))),
            ("Cancelled", DepartureTime(minutes: 5, status: .cancelled)),
            ("May not be real time", DepartureTime(minutes: 8, status: .uncertain)),
        ]

        var body: some View {
            VStack(spacing: Spacing.md) {
                GalleryCard(title: "Departures") {
                    VStack(spacing: 0) {
                        let rows = DepartureRow.samples
                        ForEach(rows.indices, id: \.self) { index in
                            rows[index]
                            if index != rows.indices.last {
                                Divider()
                            }
                        }
                    }
                }
                GalleryCard(title: "Service alerts") {
                    VStack(spacing: Spacing.xs) {
                        ServiceAlertBanner(
                            level: .severe,
                            header: "No [6] trains between 3 Av-138 St and Pelham Bay Park"
                        )
                        ServiceAlertBanner(level: .warning, header: "[L] trains are running with delays")
                        ServiceAlertBanner(level: .info, header: "Enter 5 Av/53 St [E][F] Station at 5 Av only")
                    }
                }
                GalleryCard(title: "Realtime") {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        ForEach(Self.states, id: \.title) { state in
                            AdaptiveRow {
                                RealtimeBadge(state.departure)
                                RealtimeBadge(state.departure, prominence: .secondary)
                                Text(state.title)
                                    .typography(.caption)
                                    .foregroundStyle(.textSecondary)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
            }
        }
    }
#endif
