import CoreLocation
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
    @State private var zoom: CGFloat = 1
    @State private var settledZoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var settledPan: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                Image("WorldMapSilhouette")
                    .resizable()
                    .renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(Color(red: 1, green: 0.78, blue: 0.02))
                    .scaleEffect(zoom)
                    .offset(pan)

                ForEach(pins) { pin in
                    ZStack {
                        Circle().fill(.black)
                        Circle().stroke(Color(red: 1, green: 0.78, blue: 0.02), lineWidth: 2)
                        Text("\(pin.city.count)")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 30, height: 30)
                    .position(transformedPoint(for: pin.coordinate, in: size))
                    .accessibilityLabel("\(pin.city.displayName), \(pin.city.count) \(pin.city.count == 1 ? "response" : "responses")")
                }
            }
            .contentShape(Rectangle())
            .clipped()
            .simultaneousGesture(panGesture)
            .simultaneousGesture(zoomGesture)
            .onTapGesture(count: 2) {
                guard interactive else { return }
                resetWorld()
            }
            .allowsHitTesting(interactive)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(2.16, contentMode: .fit)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Map of cities represented this month")
        .task(id: cities) { await resolvePins() }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard interactive else { return }
                pan = CGSize(width: settledPan.width + value.translation.width, height: settledPan.height + value.translation.height)
            }
            .onEnded { _ in
                guard interactive else { return }
                settledPan = pan
            }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard interactive else { return }
                zoom = min(max(settledZoom * value.magnification, 1), 6)
            }
            .onEnded { _ in
                guard interactive else { return }
                settledZoom = zoom
                if zoom == 1 { pan = .zero; settledPan = .zero }
            }
    }

    private func resetWorld() {
        withAnimation(.spring(response: 0.3)) {
            zoom = 1
            settledZoom = 1
            pan = .zero
            settledPan = .zero
        }
    }

    private func transformedPoint(for coordinate: CLLocationCoordinate2D, in size: CGSize) -> CGPoint {
        let base = WorldMapProjection.point(
            longitude: CGFloat(coordinate.longitude),
            latitude: CGFloat(coordinate.latitude),
            in: CGRect(origin: .zero, size: size)
        )
        return CGPoint(
            x: (base.x - size.width / 2) * zoom + size.width / 2 + pan.width,
            y: (base.y - size.height / 2) * zoom + size.height / 2 + pan.height
        )
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

private enum WorldMapProjection {
    static let north: CGFloat = 83
    static let south: CGFloat = -58

    static func point(longitude: CGFloat, latitude: CGFloat, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + (longitude + 180) / 360 * rect.width,
            y: rect.minY + (north - latitude) / (north - south) * rect.height
        )
    }
}
