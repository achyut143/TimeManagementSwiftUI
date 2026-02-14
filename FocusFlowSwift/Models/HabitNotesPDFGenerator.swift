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
            for task in filteredTasks {
                guard let notes = task.notes, !notes.isEmpty else { continue }
                
                // Check if we need a new page
                if yPosition > pageHeight - 100 {
                    context.beginPage()
                    yPosition = 60
                }
                
                // Date header
                if let taskDate = task.date {
                    let dateHeaderAttributes: [NSAttributedString.Key: Any] = [
                        .font: UIFont.boldSystemFont(ofSize: 14),
                        .foregroundColor: UIColor.black
                    ]
                    let dateHeader = dateFormatter.string(from: taskDate)
                    dateHeader.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: dateHeaderAttributes)
                    yPosition += 25
                }
                
                // Notes content
                let notesAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 12),
                    .foregroundColor: UIColor.darkGray
                ]
                
                let notesRect = CGRect(x: margin, y: yPosition, width: contentWidth, height: pageHeight - yPosition - margin)
                let notesSize = notes.boundingRect(
                    with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: notesAttributes,
                    context: nil
                )
                
                notes.draw(in: notesRect, withAttributes: notesAttributes)
                yPosition += notesSize.height + 20
                
                // Separator
                if yPosition < pageHeight - 100 {
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
