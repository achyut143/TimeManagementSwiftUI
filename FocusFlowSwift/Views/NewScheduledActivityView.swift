import SwiftUI
import SwiftData

struct NewScheduledActivityView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var activityName = ""
    @State private var scheduledTimes: [Date] = []
    @State private var windowDuration: Double = 10 // minutes
    @State private var showingTimePicker = false
    @State private var newTime = Date()
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Activity Details") {
                    TextField("Activity Name", text: $activityName)
                        .textFieldStyle(.roundedBorder)
                }
                
                Section("Scheduled Times") {
                    ForEach(scheduledTimes.indices, id: \.self) { index in
                        HStack {
                            Text(scheduledTimes[index], style: .time)
                            Spacer()
                            Button("Remove") {
                                scheduledTimes.remove(at: index)
                            }
                            .foregroundColor(.red)
                        }
                    }
                    
                    Button {
                        showingTimePicker = true
                    } label: {
                        Label("Add Time", systemImage: "plus.circle")
                    }
                }
                
                Section("Window Duration") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(Int(windowDuration)) minutes")
                            .font(.headline)
                        
                        Slider(value: $windowDuration, in: 1...60, step: 1)
                    }
                    .padding(.vertical, 8)
                }
                
                Section {
                    Button {
                        createActivity()
                    } label: {
                        Text("Create Activity")
                            .frame(maxWidth: .infinity)
                            .fontWeight(.semibold)
                    }
                    .disabled(activityName.isEmpty || scheduledTimes.isEmpty)
                }
            }
            .navigationTitle("New Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingTimePicker) {
                TimePickerSheet(selectedTime: $newTime) {
                    scheduledTimes.append(newTime)
                    scheduledTimes.sort()
                    showingTimePicker = false
                }
            }
        }
    }
    
    private func createActivity() {
        let activity = ScheduledActivity(
            name: activityName,
            scheduledTimes: scheduledTimes,
            windowDuration: windowDuration * 60 // Convert minutes to seconds
        )
        
        modelContext.insert(activity)
        try? modelContext.save()
        dismiss()
    }
}

struct TimePickerSheet: View {
    @Binding var selectedTime: Date
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack {
                DatePicker("Select Time", selection: $selectedTime, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                
                Spacer()
            }
            .padding()
            .navigationTitle("Add Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        onSave()
                    }
                }
            }
        }
    }
}

#Preview {
    NewScheduledActivityView()
        .modelContainer(for: [ScheduledActivity.self], inMemory: true)
}