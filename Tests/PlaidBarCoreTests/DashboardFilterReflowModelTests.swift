import Foundation
@testable import PlaidBarCore
import Testing

@Suite("DashboardFilterReflowModel Tests")
struct DashboardFilterReflowModelTests {
    // MARK: - Geometry id stability

    @Test("Each filter kind maps to a distinct, stable geometry id")
    func geometryIdsAreDistinctAndStable() {
        let kinds = DashboardAccountFilterKind.allCases
        let ids = kinds.map { DashboardFilterReflowModel.geometryID(for: $0) }

        // Distinct: the glide pill must never share an id between two segments,
        // otherwise matchedGeometryEffect would fuse them and the pill would
        // not know which segment to settle on.
        #expect(Set(ids).count == kinds.count)

        // Stable: the id is derived only from the kind's raw value, so a given
        // kind yields the same id across renders (and across processes/windows).
        for kind in kinds {
            #expect(
                DashboardFilterReflowModel.geometryID(for: kind)
                    == DashboardFilterReflowModel.geometryID(for: kind)
            )
        }
    }

    @Test("Geometry id is namespaced and contains the raw value")
    func geometryIdNamespacedByRawValue() {
        // The id stays human-debuggable and collision-resistant against any
        // other matchedGeometryEffect namespace by carrying a fixed prefix plus
        // the filter's stable raw value.
        #expect(DashboardFilterReflowModel.geometryID(for: .all) == "dashboard.filter.pill.All")
        #expect(DashboardFilterReflowModel.geometryID(for: .status) == "dashboard.filter.pill.Status")
        #expect(DashboardFilterReflowModel.geometryID(for: .credit) == "dashboard.filter.pill.Credit")
    }

    // MARK: - Reduce Motion gate

    @Test("Glide animates only when Reduce Motion is off")
    func glideGatedByReduceMotion() {
        // Reduce Motion off => the pill glides (animated reflow).
        #expect(DashboardFilterReflowModel.shouldAnimateGlide(reduceMotion: false))
        // Reduce Motion on => no geometry animation; the pill snaps instantly,
        // exactly as the native control behaved before this change. This is the
        // additive/reversible guarantee.
        #expect(!DashboardFilterReflowModel.shouldAnimateGlide(reduceMotion: true))
    }

    @Test("Selected predicate is true only for the active kind")
    func selectionPredicate() {
        for selected in DashboardAccountFilterKind.allCases {
            for candidate in DashboardAccountFilterKind.allCases {
                #expect(
                    DashboardFilterReflowModel.isSelected(candidate, selected: selected)
                        == (candidate == selected)
                )
            }
        }
    }
}
