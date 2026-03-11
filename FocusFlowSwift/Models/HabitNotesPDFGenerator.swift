import Foundation
import PDFKit
import UIKit

class HabitNotesPDFGenerator {
    static func generatePDF(habitName: String, tasks: [Task], fromDate: Date, toDate: Date) -> URL? {
        // Filter tasks for this habit within date range with notes
        let filteredTasks = tasks.filter { task in
            guard task.title == habitName,
                  let taskDate = task.date,
                  taskDate >= fromDate && taskDate <= toDate,
                  let notes = task.notes,
                  !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return false
            }
            return true
        }.sorted { ($0.date ?? Date()) < ($1.date ?? Date()) }
        
        // Create PDF
        let pdfMetaData = [
            kCGPDFContextCreator: "FocusFlow",
            kCGPDFContextTitle: "\(habitName) - Notes"
        ]
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData as [String: Any]
        
        let pageWidth = 8.5 * 72.0
        let pageHeight = 11 * 72.0
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        
        let data = renderer.pdfData { context in
            var yPosition: CGFloat = 60
            let margin: CGFloat = 40
            let contentWidth = pageWidth - (2 * margin)
            
            context.beginPage()
            
            // Title
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 24),
                .foregroundColor: UIColor.black
            ]
            let title = "\(habitName) - Notes"
            title.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: titleAttributes)
            yPosition += 40
            
            // Date range
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            let dateRangeText = "\(dateFormatter.string(from: fromDate)) - \(dateFormatter.string(from: toDate))"
            let dateAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12),
                .foregroundColor: UIColor.gray
            ]
            dateRangeText.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: dateAttributes)
            yPosition += 30
            
            // Notes
            let notesFont = UIFont.systemFont(ofSize: 12)
            let notesAttributes: [NSAttributedString.Key: Any] = [
                .font: notesFont,
                .foregroundColor: UIColor.darkGray
            ]
            let dateHeaderAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 14),
                .foregroundColor: UIColor.black
            ]

            for task in filteredTasks {
                guard let notes = task.notes, !notes.isEmpty else { continue }

                // Check if we need a new page before drawing the date header
                if yPosition > pageHeight - 100 {
                    context.beginPage()
                    yPosition = 60
                }

                // Date header
                if let taskDate = task.date {
                    let dateHeader = dateFormatter.string(from: taskDate)
                    dateHeader.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: dateHeaderAttributes)
                    yPosition += 25
                }

                // Multi-page notes drawing using NSLayoutManager
                let attrString = NSAttributedString(string: notes, attributes: notesAttributes)
                let textStorage = NSTextStorage(attributedString: attrString)
                let layoutManager = NSLayoutManager()
                textStorage.addLayoutManager(layoutManager)

                var charIndex = 0
                let totalChars = notes.utf16.count

                while charIndex < totalChars {
                    let availableHeight = pageHeight - yPosition - margin
                    let textContainer = NSTextContainer(size: CGSize(width: contentWidth, height: availableHeight))
                    textContainer.lineFragmentPadding = 0
                    layoutManager.addTextContainer(textContainer)

                    layoutManager.ensureLayout(for: textContainer)

                    let glyphRange = layoutManager.glyphRange(for: textContainer)
                    let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

                    // Draw this slice of text
                    layoutManager.drawBackground(forGlyphRange: glyphRange, at: CGPoint(x: margin, y: yPosition))
                    layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: CGPoint(x: margin, y: yPosition))

                    let usedRect = layoutManager.usedRect(for: textContainer)
                    yPosition += usedRect.height + 4

                    charIndex += charRange.length

                    // If there's more text, start a new page
                    if charIndex < totalChars {
                        context.beginPage()
                        yPosition = 60
                    }
                }

                yPosition += 16

                // Separator
                if yPosition < pageHeight - 60 {
                    let separatorPath = UIBezierPath()
                    separatorPath.move(to: CGPoint(x: margin, y: yPosition))
                    separatorPath.addLine(to: CGPoint(x: pageWidth - margin, y: yPosition))
                    UIColor.lightGray.setStroke()
                    separatorPath.lineWidth = 0.5
                    separatorPath.stroke()
                    yPosition += 15
                }
            }
        }
        
        // Save to temporary directory
        // Sanitize the filename by removing/replacing invalid characters
        let sanitizedHabitName = habitName
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
        
        let fileName = "\(sanitizedHabitName)_Notes_\(Date().timeIntervalSince1970).pdf"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        do {
            try data.write(to: tempURL)
            return tempURL
        } catch {
            print("Error saving PDF: \(error)")
            return nil
        }
    }
}
