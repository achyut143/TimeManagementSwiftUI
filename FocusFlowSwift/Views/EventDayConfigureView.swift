import SwiftUI
import SwiftData

struct EventDayConfigureView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var eventDays: [EventDay]
    
    @Binding var selectedDate: Date
    @State private var showingEventConfig = false
    @State private var currentEventDay: EventDay?
    @State private var newEventText = ""
    
    private var eventDayForSelectedDate: EventDay? {
        eventDays.first { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
    }
    
    var body: some View {
        Button(action: {
            showingEventConfig = true
            currentEventDay = eventDayForSelectedDate
        }) {
            HStack(spacing: 4) {
                // Different icons based on event state
                if let eventDay = eventDayForSelectedDate, eventDay.hasAnyEvent {
                    Image(systemName: "calendar.badge.checkmark")
                        .foregroundColor(.blue)
                } else {
                    Image(systemName: "calendar.badge.plus")
                        .foregroundColor(.gray)
                }
                
                if let eventDay = eventDayForSelectedDate, eventDay.hasAnyEvent {
                    // Show event type indicators with better styling
                    HStack(spacing: 2) {
                        ForEach(eventDay.eventTypes, id: \.self) { type in
                            Circle()
                                .fill(type.color)
                                .frame(width: 8, height: 8)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: 1)
                                )
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.1))
                    .cornerRadius(8)
                }
            }
        }
        .buttonStyle(.bordered)
        .sheet(isPresented: $showingEventConfig) {
            EventDayConfigSheet(
                selectedDate: selectedDate,
                eventDay: currentEventDay,
                onSave: saveEventDay
            )
        }
    }
    
    private func saveEventDay(_ eventDay: EventDay) {
        print("🔍 Saving EventDay:")
        print("   - Date: \(eventDay.date)")
        print("   - isFullDay: \(eventDay.isFullDay)")
        print("   - isMorning: \(eventDay.isMorning)")
        print("   - isAfternoon: \(eventDay.isAfternoon)")
        print("   - isEvening: \(eventDay.isEvening)")
        print("   - events: \(eventDay.events)")
        print("   - hasAnyEvent: \(eventDay.hasAnyEvent)")
        print("   - eventTypes: \(eventDay.eventTypes.map { $0.rawValue })")
        
        if let existing = eventDayForSelectedDate {
            existing.isFullDay = eventDay.isFullDay
            existing.isMorning = eventDay.isMorning
            existing.isAfternoon = eventDay.isAfternoon
            existing.isEvening = eventDay.isEvening
            existing.events = eventDay.events
            print("🔍 Updated existing EventDay")
        } else {
            modelContext.insert(eventDay)
            print("🔍 Inserted new EventDay")
        }
        
        try? modelContext.save()
        print("🔍 EventDay saved successfully")
    }
}

struct EventDayConfigSheet: View {
    let selectedDate: Date
    let eventDay: EventDay?
    let onSave: (EventDay) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var isFullDay = false
    @State private var isMorning = false
    @State private var isAfternoon = false
    @State private var isEvening = false
    @State private var events: [String] = []
    @State private var newEventText = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section("Event Types") {
                    Toggle("Full Day Event", isOn: $isFullDay)
                    Toggle("Morning Event", isOn: $isMorning)
                    Toggle("Afternoon Event", isOn: $isAfternoon)
                    Toggle("Evening Event", isOn: $isEvening)
                }
                
                Section("Custom Events") {
                    HStack {
                        TextField("Add event", text: $newEventText)
                        Button("Add") {
                            if !newEventText.isEmpty {
                                events.append(newEventText)
                                newEventText = ""
                            }
                        }
                        .disabled(newEventText.isEmpty)
                    }
                    
                    ForEach(events, id: \.self) { event in
                        HStack {
                            Text(event)
                            Spacer()
                            Button("Remove") {
                                events.removeAll { $0 == event }
                            }
                            .foregroundColor(.red)
                        }
                    }
                }
            }
            .navigationTitle("Configure Event Day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        let eventDay = EventDay(
                            date: selectedDate,
                            isFullDay: isFullDay,
                            isMorning: isMorning,
                            isAfternoon: isAfternoon,
                            isEvening: isEvening,
                            events: events
                        )
                        onSave(eventDay)
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            if let eventDay = eventDay {
                isFullDay = eventDay.isFullDay
                isMorning = eventDay.isMorning
                isAfternoon = eventDay.isAfternoon
                isEvening = eventDay.isEvening
                events = eventDay.events
            }
        }
    }
}

#Preview {
    EventDayConfigureView(selectedDate: .constant(Date()))
}