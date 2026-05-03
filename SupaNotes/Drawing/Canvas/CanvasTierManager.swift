import Foundation

// Pure-function module for the 3-tier canvas rendering policy.
//
//   Tier 1 — LIVE:     interactive, accept Apple Pencil (visible pages)
//   Tier 2 — ADJACENT: display-only, vector-sharp (±1 from visible range)
//   Tier 3 — BITMAP:   lightweight raster snapshots (everything else)
//
// This module decides WHICH pages get WHICH tier. The Coordinator
// executes the mount/unmount. Fully testable without UIKit.

enum CanvasTierManager {

    // MARK: Full Reconciliation (scroll settled)

    // Given visible page indices and total page count, returns the target tier assignment.
    static func assignTiers(visible: Set<Int>, pageCount: Int) -> TierAssignment {
        guard !visible.isEmpty, pageCount > 0 else {
            return TierAssignment(live: [], adjacent: [])
        }

        // Adjacent = ±1 from the visible range edges, excluding pages that are already live.
        let minVisible = visible.min()!
        let maxVisible = visible.max()!
        let adjacent = Set([minVisible - 1, maxVisible + 1]
            .filter { $0 >= 0 && $0 < pageCount && !visible.contains($0) })

        return TierAssignment(live: visible, adjacent: adjacent)
    }

    // MARK: Mid-Scroll Eviction (cheap — no new mounts)

    // Returns which mounted canvases should be torn down during active scrolling.
    // Only removes — never adds — so the scroll stays smooth.
    static func evictionTargets(
        visible: Set<Int>,
        mountedLive: Set<Int>,
        mountedAdjacent: Set<Int>
    ) -> EvictionPlan {
        // Evict live canvases that scrolled out of the visible set.
        let evictLive = mountedLive.subtracting(visible)

        // Keep adjacent canvases within ±1 of visible; evict the rest.
        var evictAdjacent = Set<Int>()
        if let minVisible = visible.min(), let maxVisible = visible.max() {
            for index in mountedAdjacent where !visible.contains(index) {
                if index < minVisible - 1 || index > maxVisible + 1 {
                    evictAdjacent.insert(index)
                }
            }
        }

        return EvictionPlan(live: evictLive, adjacent: evictAdjacent)
    }

    // MARK: Bitmap Cleanup (after settle)

    // Returns bitmap slot indices that should be cleared (off-screen, no canvas).
    static func bitmapsToClear(
        visible: Set<Int>,
        canvasIndices: Set<Int>,
        slotCount: Int,
        hasBitmap: (Int) -> Bool
    ) -> Set<Int> {
        var result = Set<Int>()
        for i in 0 ..< slotCount {
            if hasBitmap(i) && !canvasIndices.contains(i) && !visible.contains(i) {
                result.insert(i)
            }
        }
        return result
    }
}

// MARK: - Data Types

// Target state from a full reconciliation pass.
struct TierAssignment: Equatable {
    // Pages that should have interactive (Tier 1) canvases.
    let live: Set<Int>
    // Pages that should have display-only (Tier 2) canvases.
    let adjacent: Set<Int>
}

// Which mounted canvases to tear down during mid-scroll eviction.
struct EvictionPlan: Equatable {
    // Live canvases to unmount.
    let live: Set<Int>
    // Adjacent canvases to unmount.
    let adjacent: Set<Int>
}
