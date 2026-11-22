import Foundation
import CoreLocation

/// Rasterised coverage of the planning area.
///
/// The area square is split into cells of roughly `footprint` meters. A cell becomes covered
/// when the moving position passes within the footprint of its centre. Between two consecutive
/// positions the footprint is swept along the segment, so coverage does not depend on the
/// tick rate or on step-by-step jumps. Coverage % = covered cells / cells inside the area.
struct CoverageGrid {
    let center: CLLocationCoordinate2D
    let radius: Double
    let footprint: Double
    let clipToCircle: Bool
    private(set) var cellSize: Double
    private(set) var side: Int
    private(set) var totalCells: Int = 0
    private(set) var coveredCells: Int = 0

    private let projection: LocalProjection
    private let extent: Double
    private var inArea: [Bool]
    private var covered: [Bool]
    private var lastPoint: SIMD2<Double>?

    init(center: CLLocationCoordinate2D, radius: Double, footprint: Double, clipToCircle: Bool, maxCells: Int = 90_000) {
        let areaRadius = max(radius, 1)
        let footprintRadius = max(footprint, 1)
        self.center = center
        self.radius = areaRadius
        self.footprint = footprintRadius
        self.clipToCircle = clipToCircle
        projection = LocalProjection(origin: center)

        // Cell side equals the footprint unless that would blow the memory budget.
        var size = footprintRadius
        while pow((2 * areaRadius / size).rounded(.up), 2) > Double(maxCells) {
            size *= 1.25
        }
        let cellsPerSide = max(1, Int((2 * areaRadius / size).rounded(.up)))
        let halfExtent = Double(cellsPerSide) * size / 2
        cellSize = size
        side = cellsPerSide
        extent = halfExtent

        var mask = [Bool](repeating: false, count: cellsPerSide * cellsPerSide)
        var total = 0
        for row in 0..<cellsPerSide {
            for col in 0..<cellsPerSide {
                let p = SIMD2(-halfExtent + (Double(col) + 0.5) * size, -halfExtent + (Double(row) + 0.5) * size)
                let inside = !clipToCircle || p.length <= areaRadius
                mask[row * cellsPerSide + col] = inside
                if inside { total += 1 }
            }
        }
        inArea = mask
        covered = [Bool](repeating: false, count: cellsPerSide * cellsPerSide)
        totalCells = total
    }

    var fraction: Double { totalCells > 0 ? Double(coveredCells) / Double(totalCells) : 0 }
    var coveredArea: Double { Double(coveredCells) * cellSize * cellSize }

    /// Marks the footprint swept from the previous position to `coordinate`.
    /// Returns true when at least one new cell was covered.
    @discardableResult
    mutating func mark(_ coordinate: CLLocationCoordinate2D) -> Bool {
        let p = projection.project(coordinate)
        let from = lastPoint ?? p
        lastPoint = p
        let delta = p - from
        let length = delta.length
        let steps = min(4_000, max(1, Int((length / (cellSize * 0.5)).rounded(.up))))
        var changed = false
        for step in 0...steps {
            let t = Double(step) / Double(steps)
            if stamp(from + delta * t) { changed = true }
        }
        return changed
    }

    /// Breaks the swept trail (e.g. after a pause in live tracking) so the next fix is not
    /// connected to the previous one.
    mutating func breakTrail() {
        lastPoint = nil
    }

    private mutating func stamp(_ p: SIMD2<Double>) -> Bool {
        // A cell is covered when its centre is inside the footprint. When cells had to be
        // enlarged beyond the footprint, use the half-diagonal so the containing cell counts.
        let threshold = max(footprint, cellSize * 0.7072)
        let minCol = max(0, Int(((p.x - threshold + extent) / cellSize).rounded(.down)))
        let maxCol = min(side - 1, Int(((p.x + threshold + extent) / cellSize).rounded(.down)))
        let minRow = max(0, Int(((p.y - threshold + extent) / cellSize).rounded(.down)))
        let maxRow = min(side - 1, Int(((p.y + threshold + extent) / cellSize).rounded(.down)))
        guard minCol <= maxCol, minRow <= maxRow else { return false }
        var changed = false
        for row in minRow...maxRow {
            for col in minCol...maxCol {
                let index = row * side + col
                guard inArea[index], !covered[index] else { continue }
                let c = SIMD2(-extent + (Double(col) + 0.5) * cellSize, -extent + (Double(row) + 0.5) * cellSize)
                if (c - p).length <= threshold {
                    covered[index] = true
                    coveredCells += 1
                    changed = true
                }
            }
        }
        return changed
    }

    /// Covered cells merged into horizontal runs, one rectangle per run, as map polygons.
    /// Run-length merging keeps the overlay count proportional to rows, not cells.
    func coveredPolygons(limit: Int = 3_000) -> [[CLLocationCoordinate2D]] {
        var result: [[CLLocationCoordinate2D]] = []
        for row in 0..<side {
            var col = 0
            while col < side {
                if covered[row * side + col] {
                    let startCol = col
                    while col < side && covered[row * side + col] { col += 1 }
                    let x0 = -extent + Double(startCol) * cellSize
                    let x1 = -extent + Double(col) * cellSize
                    let y0 = -extent + Double(row) * cellSize
                    let y1 = y0 + cellSize
                    result.append([
                        projection.unproject(SIMD2(x0, y0)),
                        projection.unproject(SIMD2(x1, y0)),
                        projection.unproject(SIMD2(x1, y1)),
                        projection.unproject(SIMD2(x0, y1))
                    ])
                    if result.count >= limit { return result }
                } else {
                    col += 1
                }
            }
        }
        return result
    }
}
