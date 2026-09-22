import CoreLocation
import MapKit
import SwiftUI

private struct CityMapPin: Identifiable {
    let city: WrappedCityCount
    let coordinate: CLLocationCoordinate2D
    var id: String { city.id }
}

struct MonthlyCityMap: View {
    let cities: [WrappedCityCount]
    var interactive = true
    @State private var pins: [CityMapPin] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !pins.isEmpty {
                Map(initialPosition: .automatic) {
                    ForEach(pins) { pin in
                        Marker("\(pin.city.city) · \(pin.city.count)", coordinate: pin.coordinate)
                            .tint(Color(red: 0.82, green: 0.58, blue: 0.02))
                    }
                }
                .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
                .allowsHitTesting(interactive)
                .frame(minHeight: 210)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay { RoundedRectangle(cornerRadius: 4).stroke(.black, lineWidth: 1.5) }
                .accessibilityLabel("Map of cities represented this month")
            }

            ForEach(cities) { city in
                HStack {
                    Label(city.displayName, systemImage: "mappin.and.ellipse")
                    Spacer()
                    Text("\(city.count) \(city.count == 1 ? "Blurb" : "Blurbs")")
                        .foregroundStyle(.secondary)
                }
                .font(.system(.caption, design: .serif).weight(.semibold))
            }
        }
        .task(id: cities) { await resolvePins() }
    }

    @MainActor
    private func resolvePins() async {
        var resolved: [CityMapPin] = []
        for city in cities {
            let query = [city.city, city.region, city.countryCode].compactMap { $0 }.joined(separator: ", ")
            if let coordinate = try? await CLGeocoder().geocodeAddressString(query).first?.location?.coordinate {
                resolved.append(CityMapPin(city: city, coordinate: coordinate))
            }
        }
        pins = resolved
    }
}
