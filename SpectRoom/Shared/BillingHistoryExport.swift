import Foundation
import UIKit

enum BillingHistoryExport {
    private static let pageWidth: CGFloat = 612
    private static let pageHeight: CGFloat = 792
    private static let margin: CGFloat = 48

    static func writePDFFile(
        accountEmail: String,
        invoices: [Invoice]
    ) throws -> URL {
        let dateStamp = fileDateFormatter.string(from: Date())
        let fileName = "SpectRoom-Billing-History-\(dateStamp).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        let titleFont = UIFont.boldSystemFont(ofSize: 18)
        let bodyFont = UIFont.systemFont(ofSize: 12)
        let boldFont = UIFont.boldSystemFont(ofSize: 12)

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: UIColor.black
        ]
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: UIColor.black
        ]
        let boldAttrs: [NSAttributedString.Key: Any] = [
            .font: boldFont,
            .foregroundColor: UIColor.black
        ]
        let secondaryAttrs: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: UIColor.darkGray
        ]

        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let contentWidth = pageWidth - margin * 2
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        try renderer.writePDF(to: url) { context in
            var y = margin
            let bottomLimit = pageHeight - margin

            func beginPage() {
                context.beginPage()
                y = margin
            }

            func ensureSpace(_ needed: CGFloat) {
                if y + needed > bottomLimit {
                    beginPage()
                }
            }

            func draw(_ text: NSAttributedString, x: CGFloat, maxWidth: CGFloat) -> CGFloat {
                let rect = CGRect(x: x, y: y, width: maxWidth, height: .greatestFiniteMagnitude)
                let bounding = text.boundingRect(
                    with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                )
                text.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                return ceil(bounding.height)
            }

            beginPage()

            let title = NSAttributedString(
                string: "billing.invoices.export.title".localized,
                attributes: titleAttrs
            )
            y += draw(title, x: margin, maxWidth: contentWidth) + 8

            let exported = NSAttributedString(
                string: String(
                    format: "billing.invoices.export.exported.at".localized,
                    exportedAtFormatter.string(from: Date())
                ),
                attributes: secondaryAttrs
            )
            y += draw(exported, x: margin, maxWidth: contentWidth) + 4

            if !accountEmail.isEmpty {
                let account = NSAttributedString(
                    string: String(
                        format: "billing.invoices.export.account".localized,
                        accountEmail
                    ),
                    attributes: secondaryAttrs
                )
                y += draw(account, x: margin, maxWidth: contentWidth) + 4
            }

            let rangeNote = NSAttributedString(
                string: "billing.invoices.export.range".localized,
                attributes: secondaryAttrs
            )
            y += draw(rangeNote, x: margin, maxWidth: contentWidth) + 16

            if invoices.isEmpty {
                let empty = NSAttributedString(
                    string: "billing.invoices.empty".localized,
                    attributes: bodyAttrs
                )
                _ = draw(empty, x: margin, maxWidth: contentWidth)
                return
            }

            let amountColumnWidth: CGFloat = 100
            let leftColumnWidth = contentWidth - amountColumnWidth - 12

            for invoice in invoices {
                let dateText = NSAttributedString(
                    string: invoice.date.formatted(date: .abbreviated, time: .omitted),
                    attributes: secondaryAttrs
                )
                let titleText = NSAttributedString(
                    string: invoice.displayTitle,
                    attributes: boldAttrs
                )
                let amountText = NSAttributedString(
                    string: invoice.formattedAmount(),
                    attributes: boldAttrs
                )

                let dateHeight = dateText.boundingRect(
                    with: CGSize(width: leftColumnWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                ).height
                let titleHeight = titleText.boundingRect(
                    with: CGSize(width: leftColumnWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                ).height
                let amountHeight = amountText.boundingRect(
                    with: CGSize(width: amountColumnWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                ).height
                let rowHeight = max(dateHeight + 2 + titleHeight, amountHeight) + 14

                ensureSpace(rowHeight)

                let rowTop = y
                dateText.draw(
                    with: CGRect(x: margin, y: y, width: leftColumnWidth, height: dateHeight + 2),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                )
                y += dateHeight + 2
                titleText.draw(
                    with: CGRect(x: margin, y: y, width: leftColumnWidth, height: titleHeight + 2),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                )

                let amountRect = CGRect(
                    x: margin + leftColumnWidth + 12,
                    y: rowTop,
                    width: amountColumnWidth,
                    height: amountHeight + 2
                )
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .right
                let rightAlignedAmount = NSMutableAttributedString(attributedString: amountText)
                rightAlignedAmount.addAttribute(
                    .paragraphStyle,
                    value: paragraph,
                    range: NSRange(location: 0, length: rightAlignedAmount.length)
                )
                rightAlignedAmount.draw(
                    with: amountRect,
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                )

                y = rowTop + rowHeight - 8
                let separatorY = y + 4
                context.cgContext.setStrokeColor(UIColor.separator.cgColor)
                context.cgContext.setLineWidth(0.5)
                context.cgContext.move(to: CGPoint(x: margin, y: separatorY))
                context.cgContext.addLine(to: CGPoint(x: pageWidth - margin, y: separatorY))
                context.cgContext.strokePath()
                y = separatorY + 10
            }
        }

        return url
    }

    private static let fileDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    private static let exportedAtFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
