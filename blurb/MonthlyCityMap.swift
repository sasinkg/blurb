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
                WorldLandShape()
                    .fill(Color(red: 1, green: 0.78, blue: 0.02))
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
            .gesture(panGesture)
            .simultaneousGesture(zoomGesture)
            .onTapGesture(count: 2) {
                guard interactive else { return }
                zoom > 1.05 ? resetWorld() : setZoom(2)
            }
            .overlay(alignment: .bottomTrailing) {
                if interactive { mapControls.padding(8) }
            }
            .allowsHitTesting(interactive)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1.9, contentMode: .fit)
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

    private var mapControls: some View {
        VStack(spacing: 5) {
            mapButton("plus") { setZoom(zoom + 0.75) }
            mapButton("minus") { setZoom(zoom - 0.75) }
            mapButton("globe.americas.fill") { resetWorld() }
        }
    }

    private func mapButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(.black, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func setZoom(_ value: CGFloat) {
        withAnimation(.spring(response: 0.3)) {
            zoom = min(max(value, 1), 6)
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
        let base = CGPoint(
            x: (coordinate.longitude + 180) / 360 * size.width,
            y: (90 - coordinate.latitude) / 180 * size.height
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

private struct WorldLandShape: Shape {
    private let polygons: [[CGPoint]] = [
        [CGPoint(x: -168, y: 72), CGPoint(x: -145, y: 70), CGPoint(x: -128, y: 55), CGPoint(x: -105, y: 50), CGPoint(x: -82, y: 25), CGPoint(x: -97, y: 15), CGPoint(x: -117, y: 31), CGPoint(x: -126, y: 49), CGPoint(x: -150, y: 58)],
        [CGPoint(x: -73, y: 82), CGPoint(x: -20, y: 81), CGPoint(x: -18, y: 62), CGPoint(x: -45, y: 58), CGPoint(x: -62, y: 65)],
        [CGPoint(x: -81, y: 12), CGPoint(x: -62, y: 9), CGPoint(x: -35, y: -6), CGPoint(x: -49, y: -55), CGPoint(x: -70, y: -52), CGPoint(x: -77, y: -16)],
        [CGPoint(x: -11, y: 36), CGPoint(x: 5, y: 58), CGPoint(x: 29, y: 71), CGPoint(x: 46, y: 54), CGPoint(x: 31, y: 37), CGPoint(x: 12, y: 35)],
        [CGPoint(x: -18, y: 35), CGPoint(x: 10, y: 37), CGPoint(x: 40, y: 15), CGPoint(x: 51, y: -12), CGPoint(x: 30, y: -35), CGPoint(x: 9, y: -35), CGPoint(x: -17, y: 5)],
        [CGPoint(x: 30, y: 71), CGPoint(x: 90, y: 78), CGPoint(x: 178, y: 65), CGPoint(x: 145, y: 48), CGPoint(x: 127, y: 30), CGPoint(x: 104, y: 2), CGPoint(x: 78, y: 8), CGPoint(x: 57, y: 28), CGPoint(x: 31, y: 38), CGPoint(x: 46, y: 54)],
        [CGPoint(x: 67, y: 28), CGPoint(x: 90, y: 25), CGPoint(x: 105, y: 8), CGPoint(x: 121, y: 1), CGPoint(x: 108, y: -9), CGPoint(x: 92, y: 7), CGPoint(x: 78, y: 8)],
        [CGPoint(x: 112, y: -11), CGPoint(x: 154, y: -10), CGPoint(x: 153, y: -39), CGPoint(x: 132, y: -44), CGPoint(x: 113, y: -31)],
        [CGPoint(x: 137, y: 46), CGPoint(x: 146, y: 42), CGPoint(x: 142, y: 30), CGPoint(x: 135, y: 34)],
        [CGPoint(x: -11, y: 59), CGPoint(x: 2, y: 58), CGPoint(x: 1, y: 50), CGPoint(x: -9, y: 51)],
        [CGPoint(x: 47, y: -13), CGPoint(x: 51, y: -26), CGPoint(x: 45, y: -25)],
        [CGPoint(x: 166, y: -34), CGPoint(x: 178, y: -46), CGPoint(x: 170, y: -48)],
        [CGPoint(x: 95, y: 5), CGPoint(x: 141, y: 1), CGPoint(x: 130, y: -11), CGPoint(x: 102, y: -7)]
    ]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for polygon in polygons {
            guard let first = polygon.first else { continue }
            path.move(to: project(first, in: rect))
            for vertex in polygon.dropFirst() { path.addLine(to: project(vertex, in: rect)) }
            path.closeSubpath()
        }
        return path
    }

    private func project(_ coordinate: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + (coordinate.x + 180) / 360 * rect.width,
            y: rect.minY + (90 - coordinate.y) / 180 * rect.height
        )
    }
}
