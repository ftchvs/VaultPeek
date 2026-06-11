import Foundation

/// Conservative point-height budget for the dashboard-first popover overview.
///
/// The SwiftUI popover can scroll, but the first-glance overview should fit the
/// normal menu-bar window height with the heatmap, filters, a useful account
/// row set, and the selected-row drill-in visible before lower summary panels.
public struct DashboardOverviewHeightBudget: Equatable, Sendable {
    public static let realisticPopoverHeight: Double = 660
    public static let scrollChromeAndFooterReserve: Double = 56
    public static let firstGlanceVisibleHeight: Double = realisticPopoverHeight - scrollChromeAndFooterReserve

    public let headerHeight: Double
    public let statusStripHeight: Double
    public let overviewStackSpacing: Double
    public let heatmapHeight: Double
    public let captionAndFilterHeight: Double
    public let accountsHeaderHeight: Double
    public let accountRowHeight: Double
    public let selectedDrillInHeight: Double
    public let receiptHeight: Double
    public let verticalPadding: Double
    public let lowerSectionReserve: Double

    public init(
        headerHeight: Double = 42,
        statusStripHeight: Double = 34,
        receiptHeight: Double = 28,
        overviewStackSpacing: Double = 14,
        heatmapHeight: Double = 96,
        captionAndFilterHeight: Double = 36,
        accountsHeaderHeight: Double = 20,
        accountRowHeight: Double = 44,
        selectedDrillInHeight: Double = 250,
        verticalPadding: Double = 16,
        lowerSectionReserve: Double = 40
    ) {
        self.headerHeight = headerHeight
        self.statusStripHeight = statusStripHeight
        self.receiptHeight = receiptHeight
        self.overviewStackSpacing = overviewStackSpacing
        self.heatmapHeight = heatmapHeight
        self.captionAndFilterHeight = captionAndFilterHeight
        self.accountsHeaderHeight = accountsHeaderHeight
        self.accountRowHeight = accountRowHeight
        self.selectedDrillInHeight = selectedDrillInHeight
        self.verticalPadding = verticalPadding
        self.lowerSectionReserve = lowerSectionReserve
    }

    public func estimatedFirstGlanceHeight(
        visibleAccountRows: Int,
        includesSelectedDrillIn: Bool,
        includesChangeReceipt: Bool = false
    ) -> Double {
        let safeRows = max(0, visibleAccountRows)
        let drillInHeight = includesSelectedDrillIn ? selectedDrillInHeight : 0
        let localReceiptHeight = includesChangeReceipt ? receiptHeight : 0

        return headerHeight
            + statusStripHeight
            + localReceiptHeight
            + overviewStackSpacing
            + heatmapHeight
            + captionAndFilterHeight
            + accountsHeaderHeight
            + (Double(safeRows) * accountRowHeight)
            + drillInHeight
            + verticalPadding
            + lowerSectionReserve
    }

    public func fitsFirstGlance(
        visibleAccountRows: Int,
        includesSelectedDrillIn: Bool,
        includesChangeReceipt: Bool = false,
        availableHeight: Double = Self.firstGlanceVisibleHeight
    ) -> Bool {
        estimatedFirstGlanceHeight(
            visibleAccountRows: visibleAccountRows,
            includesSelectedDrillIn: includesSelectedDrillIn,
            includesChangeReceipt: includesChangeReceipt
        ) <= availableHeight
    }
}
