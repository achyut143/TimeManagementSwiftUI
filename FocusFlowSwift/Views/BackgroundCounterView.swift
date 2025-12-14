import SwiftUI

struct BackgroundCounterView: View {
    @ObservedObject var counterManager = BackgroundCounterManager.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(.blue)
                Text("Background Counter")
                    .font(.headline)
                
                Spacer()
                
                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                        .font(.title2)
                }
                .buttonStyle(PlainButtonStyle())
                
                Toggle("", isOn: $counterManager.isEnabled)
                    .labelsHidden()
            }
            
            if counterManager.isEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Current Session:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(counterManager.formattedTime(counterManager.currentSessionTime))
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.semibold)
                    }
                    
                    HStack {
                        Text("Total Time:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(counterManager.formattedTime(counterManager.totalBackgroundTime))
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.semibold)
                    }
                    
                    if counterManager.isCountingInBackground {
                        HStack {
                            Image(systemName: "circle.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 8))
                            Text("Counting in background...")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                    
                    HStack(spacing: 12) {
                        Button(action: {
                            counterManager.resetCurrentSession()
                        }) {
                            Text("Reset Session")
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.orange.opacity(0.2))
                                .foregroundColor(.orange)
                                .cornerRadius(8)
                        }
                        
                        Button(action: {
                            counterManager.resetTotal()
                        }) {
                            Text("Reset All")
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.red.opacity(0.2))
                                .foregroundColor(.red)
                                .cornerRadius(8)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

#Preview {
    BackgroundCounterView()
        .padding()
}
