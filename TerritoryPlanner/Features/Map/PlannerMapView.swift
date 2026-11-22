import SwiftUI
import MapKit

struct PlannerMapView: View {
    @Environment(PlannerViewModel.self) private var vm

    var body: some View {
        @Bindable var vm = vm
        MapReader { proxy in
            Map(position: $vm.cameraPosition, interactionModes: .all) {
                UserAnnotation()

                // Planning area.
                if let center = vm.areaCenter {
                    MapCircle(center: center, radius: vm.settings.areaRadius)
                        .foregroundStyle(Theme.accent.opacity(0.07))
                        .stroke(Theme.accent.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))

                    Annotation("Центр", coordinate: center, anchor: .center) {
                        AreaCenterMarker()
                    }
                    .annotationTitles(.hidden)
                }

                // Covered cells (run-length merged rectangles).
                if vm.preferences.showCoverage {
                    ForEach(vm.coveredPolygons) { polygon in
                        MapPolygon(coordinates: polygon.coordinates)
                            .foregroundStyle(Theme.accent.opacity(0.26))
                    }
                }

                // Planned route.
                if vm.routeCoordinates.count > 1 {
                    MapPolyline(coordinates: vm.routeCoordinates)
                        .stroke(Theme.accentSecondary.opacity(0.85), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                }

                // Travelled path.
                if vm.trail.count > 1 {
                    MapPolyline(coordinates: vm.trail)
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }

                ForEach(vm.waypointMarkers) { marker in
                    Annotation("P\(marker.index + 1)", coordinate: marker.coordinate, anchor: .center) {
                        WaypointDot(marker: marker)
                            .onTapGesture { vm.selectedPointID = marker.id }
                    }
                    .annotationTitles(.hidden)
                }

                // Anchors of a custom route while drawing it.
                if vm.settings.pattern == .custom && vm.tapMode == .customPoint {
                    ForEach(vm.customAnchorMarkers) { anchor in
                        Annotation("C\(anchor.index + 1)", coordinate: anchor.coordinate, anchor: .center) {
                            AnchorMarker(number: anchor.index + 1)
                        }
                        .annotationTitles(.hidden)
                    }
                }

                if let start = vm.startPoint {
                    Annotation("Старт", coordinate: start, anchor: .bottom) {
                        StartMarker()
                    }
                    .annotationTitles(.hidden)
                }

                if let marker = vm.markerCoordinate {
                    Annotation("Позиция", coordinate: marker, anchor: .center) {
                        PlaybackMarker(isRunning: vm.playbackState == .running)
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(vm.preferences.mapAppearance.mapStyle)
            .mapControls {
                MapCompass()
                MapScaleView()
                MapPitchToggle()
                MapUserLocationButton()
            }
            .onTapGesture(coordinateSpace: .local) { point in
                if let coordinate = proxy.convert(point, from: .local) {
                    withAnimation(Theme.spring) {
                        vm.handleMapTap(coordinate)
                    }
                }
            }
        }
    }
}

// MARK: - Markers

private struct AreaCenterMarker: View {
    var body: some View {
        ZStack {
            Circle().fill(Theme.accent.opacity(0.25)).frame(width: 26, height: 26)
            Circle().strokeBorder(Theme.accent, lineWidth: 2).frame(width: 26, height: 26)
            Image(systemName: "plus").font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.accent)
        }
    }
}

private struct StartMarker: View {
    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "flag.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Theme.start))
                .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 2))
            Triangle()
                .fill(Theme.start)
                .frame(width: 10, height: 7)
        }
        .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
    }
}

private struct AnchorMarker: View {
    let number: Int
    var body: some View {
        Text("\(number)")
            .font(.system(size: 10, weight: .bold).monospacedDigit())
            .foregroundStyle(.black)
            .frame(minWidth: 20, minHeight: 20)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.warning))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.white.opacity(0.8), lineWidth: 1.5))
    }
}

private struct WaypointDot: View {
    let marker: WaypointMarker

    var body: some View {
        let size: CGFloat = marker.isSelected ? 14 : 8
        Circle()
            .fill(marker.isReached ? Theme.accent : Color.white.opacity(0.85))
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(marker.hasPause ? Theme.warning : Color.black.opacity(0.5), lineWidth: marker.hasPause ? 2 : 1))
            .padding(6) // larger hit area
            .contentShape(Circle())
            .animation(Theme.spring, value: marker.isSelected)
    }
}

/// Current simulated / live position with a breathing halo.
private struct PlaybackMarker: View {
    let isRunning: Bool
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.accent.opacity(0.3))
                .frame(width: 44, height: 44)
                .scaleEffect(pulse ? 1.25 : 0.7)
                .opacity(pulse ? 0 : 0.9)
            Circle()
                .fill(.white)
                .frame(width: 20, height: 20)
            Circle()
                .fill(Theme.accent)
                .frame(width: 14, height: 14)
        }
        .shadow(color: Theme.accent.opacity(0.6), radius: 8)
        .onAppear { updatePulse() }
        .onChange(of: isRunning) { updatePulse() }
    }

    private func updatePulse() {
        if isRunning {
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse = true }
        } else {
            withAnimation(.easeOut(duration: 0.2)) { pulse = false }
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
