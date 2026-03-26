import SwiftUI
import UIKit

struct RichTextEditor: View {
    @Binding var text: String
    
    var body: some View {
        RichTextEditorRepresentable(text: $text)
    }
}

struct RichTextEditorRepresentable: UIViewRepresentable {
    @Binding var text: String
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> UIView {
        let containerView = UIView()
        
        // Toolbar
        let toolbar = UIView()
        toolbar.backgroundColor = UIColor.secondarySystemGroupedBackground
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        // Format buttons
        let boldBtn = createButton(title: "B", tag: 0, isBold: true, coordinator: context.coordinator)
        let italicBtn = createButton(title: "I", tag: 1, isItalic: true, coordinator: context.coordinator)
        let underlineBtn = createButton(title: "U", tag: 2, isUnderline: true, coordinator: context.coordinator)
        let strikeBtn = createButton(title: "S", tag: 3, isStrike: true, coordinator: context.coordinator)
        
        let bulletBtn = createButton(title: "•", tag: 4, coordinator: context.coordinator)
        let numberBtn = createButton(title: "1.", tag: 5, coordinator: context.coordinator)
        let checkBtn = createButton(title: "☐", tag: 6, coordinator: context.coordinator)
        
        [boldBtn, italicBtn, underlineBtn, strikeBtn, bulletBtn, numberBtn, checkBtn].forEach {
            stackView.addArrangedSubview($0)
        }
        
        scrollView.addSubview(stackView)
        toolbar.addSubview(scrollView)
        
        // Text View
        let textView = UITextView()
        textView.font = UIFont.systemFont(ofSize: 16)
        textView.textColor = .label
        textView.backgroundColor = .systemGroupedBackground
        textView.delegate = context.coordinator
        textView.translatesAutoresizingMaskIntoConstraints = false
        
        // Convert markdown to attributed string
        textView.attributedText = markdownToAttributed(text)
        context.coordinator.textView = textView
        
        containerView.addSubview(toolbar)
        containerView.addSubview(textView)
        
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: containerView.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 50),
            
            scrollView.topAnchor.constraint(equalTo: toolbar.topAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -12),
            scrollView.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: -8),
            
            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.heightAnchor),
            
            textView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            textView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        return containerView
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Update the text view when the binding changes
        guard let textView = context.coordinator.textView else { return }
        
        let currentMarkdown = context.coordinator.attributedToMarkdown(textView.attributedText)
        
        // Only update if the text has actually changed (avoid infinite loops)
        if currentMarkdown != text {
            let newAttributedText = markdownToAttributed(text)
            textView.attributedText = newAttributedText
        }
    }
    
    private func createButton(title: String, tag: Int, isBold: Bool = false, isItalic: Bool = false, isUnderline: Bool = false, isStrike: Bool = false, coordinator: Coordinator) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.tag = tag
        button.backgroundColor = UIColor.tertiarySystemGroupedBackground
        button.layer.cornerRadius = 6
        button.titleLabel?.font = isBold ? UIFont.boldSystemFont(ofSize: 16) : (isItalic ? UIFont.italicSystemFont(ofSize: 16) : UIFont.systemFont(ofSize: 16))
        button.addTarget(coordinator, action: #selector(Coordinator.formatButtonTapped(_:)), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 36).isActive = true
        // Remove fixed height constraint to avoid conflicts with stack view
        button.setContentHuggingPriority(.required, for: .vertical)
        button.setContentCompressionResistancePriority(.required, for: .vertical)
        return button
    }
    
    private func markdownToAttributed(_ markdown: String) -> NSAttributedString {
        let attributed = NSMutableAttributedString(string: markdown)
        let fullRange = NSRange(location: 0, length: attributed.length)

        // Set base font and color (label adapts automatically to dark/light mode)
        attributed.addAttribute(.font, value: UIFont.systemFont(ofSize: 16), range: fullRange)
        attributed.addAttribute(.foregroundColor, value: UIColor.label, range: fullRange)
        
        // Parse bold **text**
        let boldPattern = "\\*\\*(.+?)\\*\\*"
        if let boldRegex = try? NSRegularExpression(pattern: boldPattern) {
            let matches = boldRegex.matches(in: markdown, range: fullRange)
            for match in matches.reversed() {
                let range = match.range(at: 1)
                let fullRange = match.range
                let text = (markdown as NSString).substring(with: range)
                attributed.replaceCharacters(in: fullRange, with: text)
                let newRange = NSRange(location: fullRange.location, length: text.count)
                attributed.addAttribute(.font, value: UIFont.boldSystemFont(ofSize: 16), range: newRange)
            }
        }
        
        // Parse italic *text*
        let italicPattern = "(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)"
        if let italicRegex = try? NSRegularExpression(pattern: italicPattern) {
            let matches = italicRegex.matches(in: attributed.string, range: NSRange(location: 0, length: attributed.length))
            for match in matches.reversed() {
                let range = match.range(at: 1)
                let fullRange = match.range
                let text = (attributed.string as NSString).substring(with: range)
                attributed.replaceCharacters(in: fullRange, with: text)
                let newRange = NSRange(location: fullRange.location, length: text.count)
                attributed.addAttribute(.font, value: UIFont.italicSystemFont(ofSize: 16), range: newRange)
            }
        }
        
        // Parse underline __text__
        let underlinePattern = "__(.+?)__"
        if let underlineRegex = try? NSRegularExpression(pattern: underlinePattern) {
            let matches = underlineRegex.matches(in: attributed.string, range: NSRange(location: 0, length: attributed.length))
            for match in matches.reversed() {
                let range = match.range(at: 1)
                let fullRange = match.range
                let text = (attributed.string as NSString).substring(with: range)
                attributed.replaceCharacters(in: fullRange, with: text)
                let newRange = NSRange(location: fullRange.location, length: text.count)
                attributed.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: newRange)
            }
        }
        
        // Parse strikethrough ~~text~~
        let strikePattern = "~~(.+?)~~"
        if let strikeRegex = try? NSRegularExpression(pattern: strikePattern) {
            let matches = strikeRegex.matches(in: attributed.string, range: NSRange(location: 0, length: attributed.length))
            for match in matches.reversed() {
                let range = match.range(at: 1)
                let fullRange = match.range
                let text = (attributed.string as NSString).substring(with: range)
                attributed.replaceCharacters(in: fullRange, with: text)
                let newRange = NSRange(location: fullRange.location, length: text.count)
                attributed.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: newRange)
            }
        }
        
        return attributed
    }
    
    class Coordinator: NSObject, UITextViewDelegate {
        var parent: RichTextEditorRepresentable
        weak var textView: UITextView?
        
        init(_ parent: RichTextEditorRepresentable) {
            self.parent = parent
        }
        
        func textViewDidChange(_ textView: UITextView) {
            parent.text = attributedToMarkdown(textView.attributedText)
        }
        
        @objc func formatButtonTapped(_ sender: UIButton) {
            guard let textView = textView else { return }
            
            let selectedRange = textView.selectedRange
            
            switch sender.tag {
            case 0: // Bold
                toggleFormat(textView: textView, trait: .traitBold, markdown: "**")
            case 1: // Italic
                toggleFormat(textView: textView, trait: .traitItalic, markdown: "*")
            case 2: // Underline
                toggleUnderline(textView: textView)
            case 3: // Strikethrough
                toggleStrikethrough(textView: textView)
            case 4: // Bullet
                insertText(textView: textView, text: "• ")
            case 5: // Number
                insertText(textView: textView, text: "1. ")
            case 6: // Checkbox
                insertText(textView: textView, text: "☐ ")
            default:
                break
            }
            
            textView.selectedRange = selectedRange
        }
        
        private func toggleFormat(textView: UITextView, trait: UIFontDescriptor.SymbolicTraits, markdown: String) {
            let selectedRange = textView.selectedRange
            guard selectedRange.length > 0 else { return }
            
            let attributedText = NSMutableAttributedString(attributedString: textView.attributedText)
            let currentFont = attributedText.attribute(.font, at: selectedRange.location, effectiveRange: nil) as? UIFont ?? UIFont.systemFont(ofSize: 16)
            
            var newFont: UIFont
            if currentFont.fontDescriptor.symbolicTraits.contains(trait) {
                // Remove trait
                if let descriptor = currentFont.fontDescriptor.withSymbolicTraits(currentFont.fontDescriptor.symbolicTraits.subtracting(trait)) {
                    newFont = UIFont(descriptor: descriptor, size: currentFont.pointSize)
                } else {
                    newFont = UIFont.systemFont(ofSize: currentFont.pointSize)
                }
            } else {
                // Add trait
                if let descriptor = currentFont.fontDescriptor.withSymbolicTraits(currentFont.fontDescriptor.symbolicTraits.union(trait)) {
                    newFont = UIFont(descriptor: descriptor, size: currentFont.pointSize)
                } else {
                    newFont = currentFont
                }
            }
            
            attributedText.addAttribute(.font, value: newFont, range: selectedRange)
            textView.attributedText = attributedText
            parent.text = attributedToMarkdown(attributedText)
        }
        
        private func toggleUnderline(textView: UITextView) {
            let selectedRange = textView.selectedRange
            guard selectedRange.length > 0 else { return }
            
            let attributedText = NSMutableAttributedString(attributedString: textView.attributedText)
            let currentUnderline = attributedText.attribute(.underlineStyle, at: selectedRange.location, effectiveRange: nil) as? Int ?? 0
            
            if currentUnderline > 0 {
                attributedText.removeAttribute(.underlineStyle, range: selectedRange)
            } else {
                attributedText.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: selectedRange)
            }
            
            textView.attributedText = attributedText
            parent.text = attributedToMarkdown(attributedText)
        }
        
        private func toggleStrikethrough(textView: UITextView) {
            let selectedRange = textView.selectedRange
            guard selectedRange.length > 0 else { return }
            
            let attributedText = NSMutableAttributedString(attributedString: textView.attributedText)
            let currentStrike = attributedText.attribute(.strikethroughStyle, at: selectedRange.location, effectiveRange: nil) as? Int ?? 0
            
            if currentStrike > 0 {
                attributedText.removeAttribute(.strikethroughStyle, range: selectedRange)
            } else {
                attributedText.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: selectedRange)
            }
            
            textView.attributedText = attributedText
            parent.text = attributedToMarkdown(attributedText)
        }
        
        private func insertText(textView: UITextView, text: String) {
            let selectedRange = textView.selectedRange
            let attributedText = NSMutableAttributedString(attributedString: textView.attributedText)
            
            let insertText = (selectedRange.location == 0 || (textView.text as NSString).character(at: max(0, selectedRange.location - 1)) == 10) ? text : "\n\(text)"
            let insertAttributed = NSAttributedString(string: insertText, attributes: [.font: UIFont.systemFont(ofSize: 16), .foregroundColor: UIColor.label])
            
            attributedText.insert(insertAttributed, at: selectedRange.location)
            textView.attributedText = attributedText
            textView.selectedRange = NSRange(location: selectedRange.location + insertText.count, length: 0)
            parent.text = attributedToMarkdown(attributedText)
        }
        
        func attributedToMarkdown(_ attributed: NSAttributedString) -> String {
            var markdown = ""
            let string = attributed.string
            let length = attributed.length
            
            var index = 0
            while index < length {
                var range = NSRange(location: index, length: 0)
                let attributes = attributed.attributes(at: index, effectiveRange: &range)
                
                let substring = (string as NSString).substring(with: range)
                
                // Handle strikethrough specially for multi-line content
                if attributes[.strikethroughStyle] != nil {
                    // Split by lines and apply strikethrough to each non-empty line
                    let lines = substring.components(separatedBy: .newlines)
                    let formattedLines = lines.map { line in
                        if line.trimmingCharacters(in: .whitespaces).isEmpty {
                            return line // Keep empty lines as-is
                        } else {
                            var formattedLine = line
                            
                            // Apply other formatting first
                            if let font = attributes[.font] as? UIFont {
                                let traits = font.fontDescriptor.symbolicTraits
                                if traits.contains(.traitBold) {
                                    formattedLine = "**\(formattedLine)**"
                                }
                                if traits.contains(.traitItalic) {
                                    formattedLine = "*\(formattedLine)*"
                                }
                            }
                            
                            if attributes[.underlineStyle] != nil {
                                formattedLine = "__\(formattedLine)__"
                            }
                            
                            // Apply strikethrough last
                            return "~~\(formattedLine)~~"
                        }
                    }
                    markdown += formattedLines.joined(separator: "\n")
                } else {
                    // Handle non-strikethrough text normally
                    var formattedText = substring
                    
                    if let font = attributes[.font] as? UIFont {
                        let traits = font.fontDescriptor.symbolicTraits
                        if traits.contains(.traitBold) {
                            formattedText = "**\(formattedText)**"
                        }
                        if traits.contains(.traitItalic) {
                            formattedText = "*\(formattedText)*"
                        }
                    }
                    
                    if attributes[.underlineStyle] != nil {
                        formattedText = "__\(formattedText)__"
                    }
                    
                    markdown += formattedText
                }
                
                index = range.location + range.length
            }
            
            return markdown
        }
    }
}

// Markdown-style text renderer for display
struct MarkdownText: View {
    let text: String
    
    var body: some View {
        Text(parseMarkdown(text))
    }
    
    private func parseMarkdown(_ text: String) -> AttributedString {
        var result = text
        
        // Remove markdown markers for display
        result = result.replacingOccurrences(of: "**", with: "")
        result = result.replacingOccurrences(of: "__", with: "")
        result = result.replacingOccurrences(of: "~~", with: "")
        
        // Handle italic (single asterisk) - more complex to avoid removing from bold
        let italicPattern = "(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)"
        if let regex = try? NSRegularExpression(pattern: italicPattern) {
            let nsString = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: nsString.length))
            for match in matches.reversed() {
                let range = match.range
                let text = nsString.substring(with: range)
                let cleaned = text.replacingOccurrences(of: "*", with: "")
                result = (result as NSString).replacingCharacters(in: range, with: cleaned)
            }
        }
        
        return AttributedString(result)
    }
}

#Preview {
    VStack {
        RichTextEditor(text: .constant("Sample text"))
            .frame(height: 200)
            .padding()
        
        Spacer()
    }
}
