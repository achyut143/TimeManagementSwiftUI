import SwiftUI
import SwiftData

struct EditScheduledActivityView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let activity: ScheduledActivity
    
    @State private var activityName = ""
    @State private var scheduledTimes: [Date] = []
    @State private var windowDuration: Double = 10 // minutes
    @State private var isActive = true
    @State private var showingTimePicker = false
    @State private var newTime = Date()
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Activity Details") {
                    TextField("Activity Name", text: $activityName)
                        .textFieldStyle(.roundedBorder)
                    
                    Toggle("Active", isOn: $isActive)
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
                        saveChanges()
                    } label: {
                        Text("Save Changes")
                            .frame(maxWidth: .infinity)
                            .fontWeight(.semibold)
                    }
                    .disabled(activityName.isEmpty || scheduledTimes.isEmpty)
                }
            }
            .navigationTitle("Edit Activity")
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
            .onAppear {
                loadActivityData()
            }
        }
    }
    
    private func loadActivityData() {
        activityName = activity.name
        scheduledTimes = activity.scheduledTimes
        windowDuration = activity.windowDuration / 60 // Convert seconds to minutes
        isActive = activity.isActive
    }
    
    private func saveChanges() {
        activity.name = activityName
        activity.scheduledTimes = scheduledTimes
        activity.windowDuration = windowDuration * 60 // Convert minutes to seconds
        activity.isActive = isActive
        
        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    EditScheduledActivityView(
        activity: ScheduledActivity(
            name: "Instagram",
            scheduledTimes: [Date()],
            windowDuration: 600
        )
    )
    .modelContainer(for: [ScheduledActivity.self], inMemory: true)
}