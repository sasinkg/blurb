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
            .simultaneousGesture(panGesture)
            .simultaneousGesture(zoomGesture)
            .onTapGesture(count: 2) {
                guard interactive else { return }
                resetWorld()
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

private struct WorldLandShape: Shape {
    private let polygons: [[CGPoint]] = [
        // North America, drawn as a single editorial silhouette without borders.
        [CGPoint(x: -168, y: 72), CGPoint(x: -151, y: 71), CGPoint(x: -140, y: 60), CGPoint(x: -126, y: 54), CGPoint(x: -124, y: 42), CGPoint(x: -117, y: 32), CGPoint(x: -107, y: 23), CGPoint(x: -97, y: 18), CGPoint(x: -88, y: 19), CGPoint(x: -83, y: 25), CGPoint(x: -80, y: 31), CGPoint(x: -75, y: 36), CGPoint(x: -66, y: 44), CGPoint(x: -53, y: 47), CGPoint(x: -59, y: 56), CGPoint(x: -73, y: 62), CGPoint(x: -89, y: 69), CGPoint(x: -108, y: 72), CGPoint(x: -124, y: 73), CGPoint(x: -142, y: 69), CGPoint(x: -157, y: 60)],
        // Greenland.
        [CGPoint(x: -73, y: 77), CGPoint(x: -50, y: 83), CGPoint(x: -20, y: 80), CGPoint(x: -18, y: 63), CGPoint(x: -43, y: 59), CGPoint(x: -61, y: 66)],
        // Central America.
        [CGPoint(x: -97, y: 20), CGPoint(x: -88, y: 18), CGPoint(x: -83, y: 10), CGPoint(x: -78, y: 8), CGPoint(x: -80, y: 2), CGPoint(x: -88, y: 10)],
        // South America.
        [CGPoint(x: -81, y: 12), CGPoint(x: -71, y: 12), CGPoint(x: -61, y: 7), CGPoint(x: -50, y: 2), CGPoint(x: -36, y: -7), CGPoint(x: -39, y: -19), CGPoint(x: -47, y: -29), CGPoint(x: -53, y: -39), CGPoint(x: -66, y: -55), CGPoint(x: -73, y: -43), CGPoint(x: -72, y: -29), CGPoint(x: -78, y: -12)],
        // Europe and Asia.
        [CGPoint(x: -11, y: 36), CGPoint(x: -10, y: 44), CGPoint(x: -3, y: 50), CGPoint(x: 8, y: 55), CGPoint(x: 20, y: 59), CGPoint(x: 31, y: 68), CGPoint(x: 48, y: 72), CGPoint(x: 70, y: 72), CGPoint(x: 91, y: 77), CGPoint(x: 116, y: 73), CGPoint(x: 139, y: 61), CGPoint(x: 161, y: 61), CGPoint(x: 178, y: 52), CGPoint(x: 163, y: 45), CGPoint(x: 143, y: 47), CGPoint(x: 134, y: 39), CGPoint(x: 127, y: 34), CGPoint(x: 121, y: 23), CGPoint(x: 110, y: 20), CGPoint(x: 105, y: 9), CGPoint(x: 96, y: 6), CGPoint(x: 80, y: 7), CGPoint(x: 71, y: 20), CGPoint(x: 59, y: 24), CGPoint(x: 51, y: 29), CGPoint(x: 41, y: 37), CGPoint(x: 30, y: 40), CGPoint(x: 20, y: 35), CGPoint(x: 10, y: 36), CGPoint(x: 2, y: 42), CGPoint(x: -5, y: 43)],
        // Africa.
        [CGPoint(x: -17, y: 36), CGPoint(x: 4, y: 37), CGPoint(x: 22, y: 32), CGPoint(x: 34, y: 25), CGPoint(x: 43, y: 12), CGPoint(x: 51, y: 2), CGPoint(x: 43, y: -12), CGPoint(x: 36, y: -21), CGPoint(x: 29, y: -33), CGPoint(x: 17, y: -35), CGPoint(x: 8, y: -31), CGPoint(x: 1, y: -18), CGPoint(x: -8, y: 4), CGPoint(x: -17, y: 15)],
        // Arabian Peninsula and India.
        [CGPoint(x: 35, y: 30), CGPoint(x: 57, y: 25), CGPoint(x: 56, y: 15), CGPoint(x: 48, y: 12), CGPoint(x: 41, y: 20)],
        [CGPoint(x: 68, y: 24), CGPoint(x: 79, y: 29), CGPoint(x: 89, y: 22), CGPoint(x: 80, y: 7), CGPoint(x: 73, y: 9)],
        // Southeast Asian peninsula and islands.
        [CGPoint(x: 96, y: 22), CGPoint(x: 107, y: 18), CGPoint(x: 109, y: 7), CGPoint(x: 104, y: 1), CGPoint(x: 100, y: 8)],
        [CGPoint(x: 95, y: 5), CGPoint(x: 108, y: 4), CGPoint(x: 119, y: -3), CGPoint(x: 130, y: -5), CGPoint(x: 140, y: -8), CGPoint(x: 128, y: -11), CGPoint(x: 112, y: -8), CGPoint(x: 101, y: -6)],
        // Japan, Great Britain, Madagascar, and New Zealand.
        [CGPoint(x: 138, y: 46), CGPoint(x: 146, y: 42), CGPoint(x: 142, y: 31), CGPoint(x: 136, y: 35)],
        [CGPoint(x: -8, y: 59), CGPoint(x: 1, y: 57), CGPoint(x: 0, y: 50), CGPoint(x: -6, y: 51)],
        [CGPoint(x: 47, y: -13), CGPoint(x: 51, y: -25), CGPoint(x: 45, y: -26), CGPoint(x: 43, y: -18)],
        // Australia and New Zealand.
        [CGPoint(x: 112, y: -11), CGPoint(x: 124, y: -15), CGPoint(x: 138, y: -12), CGPoint(x: 153, y: -19), CGPoint(x: 151, y: -35), CGPoint(x: 140, y: -40), CGPoint(x: 129, y: -37), CGPoint(x: 116, y: -32)],
        [CGPoint(x: 166, y: -34), CGPoint(x: 178, y: -42), CGPoint(x: 173, y: -48), CGPoint(x: 167, y: -45)]
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
        WorldMapProjection.point(
            longitude: coordinate.x,
            latitude: coordinate.y,
            in: rect
        )
    }
}
