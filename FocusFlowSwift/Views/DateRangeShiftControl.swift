import SwiftUI

// Reusable "< range >" control for from/to date filters that aren't backed by the
// Projects module's `DateRange` type. Tapping an arrow shifts both dates together by
// the current span length (a week stays a week, 30 days stays 30 days, etc), so
// consecutive windows tile back-to-back.
struct DateRangeShiftControl: View {
    @Binding var start: Date
    @Binding var end: Date
    var onShift: (() -> Void)? = nil

    var body: some View {
        HStack {
            Button {
                shift(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
            }
            .buttonStyle(.plain)

            Spacer()

            Text(rangeLabel)
                .font(.subheadline)
                .fontWeight(.medium)

            Spacer()

            Button {
                shift(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.headline)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private var dayCount: Int {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: start), to: cal.startOfDay(for: end)).day ?? 0
        return max(days + 1, 1)
    }

    private func shift(by direction: Int) {
        let cal = Calendar.current
        let offset = dayCount * direction
        guard let newStart = cal.date(byAdding: .day, value: offset, to: start),
              let newEnd = cal.date(byAdding: .day, value: offset, to: end) else { return }
        start = newStart
        end = newEnd
        onShift?()
    }

    private var rangeLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        if Calendar.current.isDate(start, inSameDayAs: end) {
            return formatter.string(from: start)
        }
        return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
    }
}
