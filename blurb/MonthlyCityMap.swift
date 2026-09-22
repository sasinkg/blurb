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
    @State private var fittedZoom: CGFloat = 1
    @State private var fittedPan: CGSize = .zero
    @State private var viewportSize: CGSize = .zero

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
                resetToRelevantCities()
            }
            .allowsHitTesting(interactive)
            .onAppear {
                viewportSize = size
                fitMap(to: pins, in: size, animated: false)
            }
            .onChange(of: size) { _, newSize in
                viewportSize = newSize
                fitMap(to: pins, in: newSize, animated: false)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(2, contentMode: .fit)
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

    private func resetToRelevantCities() {
        withAnimation(.spring(response: 0.3)) {
            zoom = fittedZoom
            settledZoom = fittedZoom
            pan = fittedPan
            settledPan = fittedPan
        }
    }

    private func fitMap(to mapPins: [CityMapPin], in size: CGSize, animated: Bool) {
        guard size.width > 0, size.height > 0, !mapPins.isEmpty else {
            fittedZoom = 1
            fittedPan = .zero
            return
        }

        let points = mapPins.map {
            WorldMapProjection.point(
                longitude: CGFloat($0.coordinate.longitude),
                latitude: CGFloat($0.coordinate.latitude),
                in: CGRect(origin: .zero, size: size)
            )
        }
        let minX = points.map(\.x).min() ?? size.width / 2
        let maxX = points.map(\.x).max() ?? size.width / 2
        let minY = points.map(\.y).min() ?? size.height / 2
        let maxY = points.map(\.y).max() ?? size.height / 2
        let spanX = max(maxX - minX, 1)
        let spanY = max(maxY - minY, 1)
        let edgePadding: CGFloat = 54
        let availableWidth = max(size.width - edgePadding * 2, 1)
        let availableHeight = max(size.height - edgePadding * 2, 1)
        let targetZoom = min(max(min(availableWidth / spanX, availableHeight / spanY), 1), 4.8)
        let center = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        let targetPan = CGSize(
            width: (size.width / 2 - center.x) * targetZoom,
            height: (size.height / 2 - center.y) * targetZoom
        )

        fittedZoom = targetZoom
        fittedPan = targetPan
        let update = {
            zoom = targetZoom
            settledZoom = targetZoom
            pan = targetPan
            settledPan = targetPan
        }
        if animated {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
                update()
            }
        } else {
            update()
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
        fitMap(to: resolved, in: viewportSize, animated: true)
    }
}

private enum WorldMapProjection {
    static let north: CGFloat = 90
    static let south: CGFloat = -90

    static func point(longitude: CGFloat, latitude: CGFloat, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + (longitude + 180) / 360 * rect.width,
            y: rect.minY + (north - latitude) / (north - south) * rect.height
        )
    }
}
