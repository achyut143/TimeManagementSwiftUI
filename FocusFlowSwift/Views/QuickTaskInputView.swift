import SwiftUI

struct QuickTaskInputView: View {
    @Binding var input: String
    let onSubmit: (QuickTaskParser.ParsedTask) -> Void
    var onOpenFullForm: (() -> Void)? = nil
    @State private var showHelp = false

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "bolt.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                Text("Quick Task")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Spacer()

                Button(action: { showHelp.toggle() }) {
                    Image(systemName: showHelp ? "questionmark.circle.fill" : "questionmark.circle")
                        .font(.title3)
                        .foregroundStyle(.blue)
                }

                if let openFull = onOpenFullForm {
                    Button(action: openFull) {
                        HStack(spacing: 4) {
                            Text("Full Form")
                                .font(.subheadline)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                        }
                        .foregroundStyle(.indigo)
                    }
                }
            }
            
            if showHelp {
                VStack(alignment: .leading, spacing: 8) {
                    Text(QuickTaskParser.helpText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(12)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    
                    Text("Examples:")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    
                    ForEach(QuickTaskParser.exampleFormats, id: \.self) { example in
                        Text("• \(example)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 8)
                    }
                }
                .transition(.opacity)
            }
            
            VStack(spacing: 12) {
                TextEditor(text: $input)
                    .frame(minHeight: 90)
                    .padding(12)
                    .background(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.systemGray4), lineWidth: 1)
                    )
                    .cornerRadius(12)
                    .overlay(
                        Group {
                            if input.isEmpty {
                                Text("15:30 - 16:30 - task name - 2 - r2")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary.opacity(0.5))
                                    .padding(.leading, 16)
                                    .padding(.top, 20)
                                    .allowsHitTesting(false)
                            }
                        },
                        alignment: .topLeading
                    )
                
                HStack(spacing: 16) {
                    Spacer()
                    
                    Button("Create Task") {
                        if let parsed = QuickTaskParser.parse(input), parsed.isValid {
                            onSubmit(parsed)
                            input = ""
                        }
                    }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(input.isEmpty ? Color.gray : Color.blue)
                    .cornerRadius(20)
                    .disabled(input.isEmpty)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
        .padding(.horizontal)
    }
}
