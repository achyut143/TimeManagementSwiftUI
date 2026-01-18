import SwiftUI
import SwiftData

struct EventDetailView: View {
    let date: Date
    let eventDay: EventDay?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Date Header
                VStack(spacing: 8) {
                    Text(date.formatted(date: .complete, time: .omitted))
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    if let eventDay = eventDay, eventDay.hasAnyEvent {
                        Text("Event Day")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                    } else {
                        Text("No Events")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                }
                .padding(.top)
                
                if let eventDay = eventDay, eventDay.hasAnyEvent {
                    ScrollView {
                        VStack(spacing: 16) {
                            // Event Types Section
                            if !eventDay.eventTypes.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Event Types")
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                    
                                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                                        ForEach(eventDay.eventTypes, id: \.self) { eventType in
                                            HStack {
                                                Circle()
                                                    .fill(eventType.color)
                                                    .frame(width: 12, height: 12)
                                                
                                                Text(eventType.rawValue)
                                                    .font(.subheadline)
                                                    .fontWeight(.medium)
                                                
                                                Spacer()
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(eventType.color.opacity(0.1))
                                            .cornerRadius(8)
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                            
                            // Custom Events Section
                            if !eventDay.events.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Custom Events")
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                    
                                    ForEach(eventDay.events, id: \.self) { event in
                                        HStack {
                                            Image(systemName: "calendar")
                                                .foregroundColor(.blue)
                                            
                                            Text(event)
                                                .font(.subheadline)
                                            
                                            Spacer()
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color.gray.opacity(0.1))
                                        .cornerRadius(8)
                                    }
                                }
                                .padding(.horizontal)
                            }
                            
                            // Impact Information
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Event Day Impact")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                
                                Text("Event days provide context for habit tracking. Habits not completed on event days are tracked separately from regular missed days, helping you understand patterns in your habit performance.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                            .padding(.horizontal)
                        }
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "calendar")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("No events configured for this day")
                            .font(.body)
                            .foregroundColor(.secondary)
                        
                        Text("Tap the event configuration button in the calendar view to add events for this day.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }
                
                Spacer()
            }
            .navigationTitle("Event Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    let sampleEventDay = EventDay(
        date: Date(),
        isFullDay: true,
        isMorning: false,
        isAfternoon: true,
        isEvening: false,
        events: ["Team Meeting", "Doctor Appointment"]
    )
    
    return EventDetailView(date: Date(), eventDay: sampleEventDay)
}