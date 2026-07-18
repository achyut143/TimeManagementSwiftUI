import Foundation
import UIKit

// Follows the same UIGraphicsPDFRenderer + NSLayoutManager wrapping conventions as
// HabitNotesPDFGenerator, applied to a project's activities/notes within a date range.
enum ProjectPDFExporter {
    static func generatePDF(project: Project, from: Date, to: Date) -> URL? {
        let pdfMetaData = [
            kCGPDFContextCreator: "FocusFlow",
            kCGPDFContextTitle: "\(project.name) - Activities"
        ]
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData as [String: Any]

        let pageWidth = 8.5 * 72.0
        let pageHeight = 11 * 72.0
        let margin: CGFloat = 40
        let contentWidth = pageWidth - margin * 2
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        let titleAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 24), .foregroundColor: UIColor.black]
        let rangeAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12), .foregroundColor: UIColor.gray]
        let dayHeaderAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 14), .foregroundColor: UIColor.black]
        let itemAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 12), .foregroundColor: UIColor.darkGray]
        let metaAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor.gray]
        let noteAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.italicSystemFont(ofSize: 11), .foregroundColor: UIColor.darkGray]

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium

        let cal = Calendar.current
        let startDay = cal.startOfDay(for: from)
        let endDay = cal.startOfDay(for: to)

        var byDate: [Date: (activities: [ProjectActivity], direct: [ProjectTimeEntry])] = [:]
        for activity in project.activities where activity.date >= startDay && activity.date <= endDay {
            byDate[activity.date, default: ([], [])].activities.append(activity)
        }
        for entry in project.directTimeEntries where entry.date >= startDay && entry.date <= endDay {
            byDate[entry.date, default: ([], [])].direct.append(entry)
        }
        let days = byDate.keys.sorted()

        let data = renderer.pdfData { context in
            var y: CGFloat = 60
            context.beginPage()

            project.name.draw(at: CGPoint(x: margin, y: y), withAttributes: titleAttrs)
            y += 32
            let rangeText = "\(dateFormatter.string(from: startDay)) – \(dateFormatter.string(from: endDay))"
            rangeText.draw(at: CGPoint(x: margin, y: y), withAttributes: rangeAttrs)
            y += 28

            func newPageIfNeeded(_ height: CGFloat) {
                if y + height > pageHeight - margin {
                    context.beginPage()
                    y = 60
                }
            }

            // Draws text wrapped to `width`, spilling onto new pages if it runs past
            // the bottom margin (mirrors HabitNotesPDFGenerator's note-drawing loop).
            func drawWrapped(_ text: String, attributes: [NSAttributedString.Key: Any], x: CGFloat, width: CGFloat) {
                let attrString = NSAttributedString(string: text, attributes: attributes)
                let textStorage = NSTextStorage(attributedString: attrString)
                let layoutManager = NSLayoutManager()
                textStorage.addLayoutManager(layoutManager)
                var charIndex = 0
                let totalChars = text.utf16.count
                while charIndex < totalChars {
                    if pageHeight - y - margin < 20 {
                        context.beginPage()
                        y = 60
                    }
                    let textContainer = NSTextContainer(size: CGSize(width: width, height: pageHeight - y - margin))
                    textContainer.lineFragmentPadding = 0
                    layoutManager.addTextContainer(textContainer)
                    layoutManager.ensureLayout(for: textContainer)
                    let glyphRange = layoutManager.glyphRange(for: textContainer)
                    let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
                    layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: CGPoint(x: x, y: y))
                    let usedRect = layoutManager.usedRect(for: textContainer)
                    y += usedRect.height
                    charIndex += charRange.length
                    if charIndex < totalChars {
                        context.beginPage()
                        y = 60
                    }
                }
            }

            if days.isEmpty {
                newPageIfNeeded(20)
                "No activity logged in this range.".draw(at: CGPoint(x: margin, y: y), withAttributes: rangeAttrs)
            }

            for day in days {
                guard let bucket = byDate[day] else { continue }
                newPageIfNeeded(26)
                dateFormatter.string(from: day).draw(at: CGPoint(x: margin, y: y), withAttributes: dayHeaderAttrs)
                y += 22

                let sortedActivities = bucket.activities.sorted { a, b in
                    switch (a.startMinutes, b.startMinutes) {
                    case let (m1?, m2?): return m1 < m2
                    case (nil, nil): return a.createdAt < b.createdAt
                    case (nil, _?): return false
                    case (_?, nil): return true
                    }
                }

                for activity in sortedActivities {
                    newPageIfNeeded(18)
                    var line = activity.name
                    if let category = activity.category { line += "  [\(category.rawValue)]" }
                    line += "  —  \(DurationInput.string(from: activity.totalMinutes))"
                    line.draw(at: CGPoint(x: margin + 12, y: y), withAttributes: itemAttrs)
                    y += 16

                    if let start = activity.startTime {
                        newPageIfNeeded(14)
                        var timeLine = start
                        if let end = activity.endTime { timeLine += " – \(end)" }
                        timeLine.draw(at: CGPoint(x: margin + 12, y: y), withAttributes: metaAttrs)
                        y += 14
                    }

                    if let notes = activity.notes, !notes.isEmpty {
                        newPageIfNeeded(16)
                        drawWrapped(notes, attributes: noteAttrs, x: margin + 12, width: contentWidth - 12)
                        y += 6
                    }
                    y += 6
                }

                for entry in bucket.direct {
                    newPageIfNeeded(18)
                    let line = "Project time  —  \(DurationInput.string(from: entry.durationMinutes))"
                    line.draw(at: CGPoint(x: margin + 12, y: y), withAttributes: itemAttrs)
                    y += 16
                    if !entry.note.isEmpty {
                        newPageIfNeeded(16)
                        drawWrapped(entry.note, attributes: noteAttrs, x: margin + 12, width: contentWidth - 12)
                        y += 6
                    }
                    y += 6
                }

                y += 10
                if y < pageHeight - margin {
                    let path = UIBezierPath()
                    path.move(to: CGPoint(x: margin, y: y))
                    path.addLine(to: CGPoint(x: pageWidth - margin, y: y))
                    UIColor.lightGray.setStroke()
                    path.lineWidth = 0.5
                    path.stroke()
                    y += 14
                }
            }
        }

        let sanitizedName = project.name
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "*", with: "_")
            .replacingOccurrences(of: "?", with: "_")
            .replacingOccurrences(of: "\"", with: "_")
            .replacingOccurrences(of: "<", with: "_")
            .replacingOccurrences(of: ">", with: "_")
            .replacingOccurrences(of: "|", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        let fileName = "\(sanitizedName)_Activities_\(Int(Date().timeIntervalSince1970)).pdf"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try data.write(to: tempURL)
            return tempURL
        } catch {
            print("Error saving project PDF: \(error)")
            return nil
        }
    }
}
