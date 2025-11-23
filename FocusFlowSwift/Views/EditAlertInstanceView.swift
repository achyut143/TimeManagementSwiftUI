import SwiftUI
import SwiftData

struct EditAlertInstanceView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var instance: AlertInstance
    
    @State private var tempName: String = ""
    @State private var tempIntervalMinutes: Int = 5
    @State private var tempIntervalSeconds: Int = 0
    @State private var tempRestMinutes: Int = 0
    @State private var tempRestSeconds: Int = 0
    @State private var tempWorkIntervalText: String = ""
    @State private var tempRestIntervalText: String = ""
    @State private var tempUseCycles: Bool = false
    @State private var tempTargetIntervals: Int? = nil
    @State private var showingCycleConfiguration = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Basic Settings") {
                    TextField("Alert Name", text: $tempName)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Interval Duration")
                            .font(.subheadline)
                        HStack {
                            TextField("0", text: Binding(
                                get: { String(tempIntervalMinutes) },
                                set: { if let value = Int($0) { tempIntervalMinutes = max(0, value) } else if $0.isEmpty { tempIntervalMinutes = 0 } }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .keyboardType(.numberPad)
                            Text("min")
                            
                            TextField("0", text: Binding(
                                get: { String(tempIntervalSeconds) },
                                set: { if let value = Int($0) { tempIntervalSeconds = max(0, min(59, value)) } else if $0.isEmpty { tempIntervalSeconds = 0 } }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .keyboardType(.numberPad)
                            Text("sec")
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Rest Period (Optional)")
                            .font(.subheadline)
                        HStack {
                            TextField("0", text: Binding(
                                get: { String(tempRestMinutes) },
                                set: { if let value = Int($0) { tempRestMinutes = max(0, value) } else if $0.isEmpty { tempRestMinutes = 0 } }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .keyboardType(.numberPad)
                            Text("min")
                            
                            TextField("0", text: Binding(
                                get: { String(tempRestSeconds) },
                                set: { if let value = Int($0) { tempRestSeconds = max(0, min(59, value)) } else if $0.isEmpty { tempRestSeconds = 0 } }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .keyboardType(.numberPad)
                            Text("sec")
                        }
                    }
                    
                    Toggle("Use Cycles", isOn: $tempUseCycles)
                }
                
                Section("Speech Announcements (Optional)") {
                    TextField("Work interval text", text: $tempWorkIntervalText)
                    TextField("Rest period text", text: $tempRestIntervalText)
                }
                
                if !tempUseCycles {
                    Section("Target") {
                        HStack {
                            Text("Target Intervals")
                            Spacer()
                            TextField("Optional", value: Binding(
                                get: { tempTargetIntervals ?? 0 },
                                set: { tempTargetIntervals = $0 > 0 ? $0 : nil }
                            ), format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .keyboardType(.numberPad)
                        }
                    }
                }
                
                if tempUseCycles {
                    Section("Cycles") {
                        Button("Configure Cycles") {
                            showingCycleConfiguration = true
                        }
                        
                        if !instance.cyclePhases.isEmpty {
                            ForEach(instance.orderedCyclePhases, id: \.id) { phase in
                                HStack {
                                    Text(phase.name)
                                    Spacer()
                                    Text("\(phase.totalMinutes) min")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                
                Section("Status") {
                    HStack {
                        Text("Current State")
                        Spacer()
                        Text(instance.isRunning ? "Running" : (instance.isPaused ? "Paused" : "Stopped"))
                            .foregroundStyle(instance.isRunning ? .green : (instance.isPaused ? .orange : .secondary))
                    }
                    
                    if instance.counter > 0 {
                        HStack {
                            Text("Intervals Completed")
                            Spacer()
                            Text("\(instance.counter)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Edit Alert")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveChanges()
                        dismiss()
                    }
                    .disabled(tempName.isEmpty)
                }
            }
            .onAppear {
                loadCurrentValues()
            }
            .sheet(isPresented: $showingCycleConfiguration) {
                AlertInstanceCycleConfigurationView(instance: instance)
            }
        }
    }
    
    private func loadCurrentValues() {
        tempName = instance.name
        tempIntervalMinutes = instance.intervalMinutes
        tempIntervalSeconds = instance.intervalSeconds
        tempRestMinutes = instance.restMinutes
        tempRestSeconds = instance.restSeconds
        tempWorkIntervalText = instance.workIntervalText
        tempRestIntervalText = instance.restIntervalText
        tempUseCycles = instance.useCycles
        tempTargetIntervals = instance.targetIntervals
    }
    
    private func saveChanges() {
        instance.name = tempName
        instance.intervalMinutes = tempIntervalMinutes
        instance.intervalSeconds = tempIntervalSeconds
        instance.restMinutes = tempRestMinutes
        instance.restSeconds = tempRestSeconds
        instance.workIntervalText = tempWorkIntervalText
        instance.restIntervalText = tempRestIntervalText
        instance.useCycles = tempUseCycles
        instance.targetIntervals = tempTargetIntervals
        
        if tempUseCycles && instance.cyclePhases.isEmpty {
            // Setup default cycles if switching to cycles mode
            instance.cyclePhases = [
                CyclePhase(name: "Focus", totalMinutes: 25, order: 0),
                CyclePhase(name: "Break", totalMinutes: 5, order: 1)
            ]
        }
    }
}

struct AlertInstanceCycleConfigurationView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var instance: AlertInstance
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 8) {
                        Text("Configure Cycles")
                            .font(.headline)
                        
                        Text("Base interval: \(instance.intervalMinutes) minutes")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top)
                    
                    VStack(spacing: 12) {
                        HStack {
                            Text("Cycles (\(instance.cyclePhases.count))")
                                .font(.headline)
                            Spacer()
                            Button("Add Cycle") {
                                addNewCycle()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        
                        if instance.cyclePhases.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "plus.circle.dashed")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                                Text("No cycles configured")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                Button("Add First Cycle") {
                                    addNewCycle()
                                }
                                .buttonStyle(.bordered)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else {
                            LazyVStack(spacing: 12) {
                                let orderedPhases = instance.orderedCyclePhases
                                ForEach(0..<orderedPhases.count, id: \.self) { index in
                                    AlertInstanceCycleRow(
                                        phase: orderedPhases[index],
                                        index: index,
                                        onDelete: { deleteCycle(at: index) }
                                    )
                                }
                            }
                        }
                    }
                    
                    Color.clear.frame(height: 20)
                }
                .padding()
            }
            .navigationTitle("Configure Cycles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    
    private func addNewCycle() {
        let newCycle = CyclePhase(
            name: "Cycle \(instance.cyclePhases.count + 1)",
            totalMinutes: 10,
            order: instance.cyclePhases.count
        )
        instance.cyclePhases.append(newCycle)
    }
    
    private func deleteCycle(at index: Int) {
        guard instance.cyclePhases.count > 1 else { return }
        
        let orderedCycles = instance.orderedCyclePhases
        guard index < orderedCycles.count else { return }
        
        let cycleToDelete = orderedCycles[index]
        
        if let actualIndex = instance.cyclePhases.firstIndex(where: { $0.id == cycleToDelete.id }) {
            instance.cyclePhases.remove(at: actualIndex)
        }
        
        // Reorder remaining cycles
        let remainingCycles = instance.orderedCyclePhases
        for (i, cycle) in remainingCycles.enumerated() {
            cycle.order = i
        }
        
        if instance.currentCycleIndex >= instance.cyclePhases.count {
            instance.currentCycleIndex = 0
        }
    }
}

struct AlertInstanceCycleRow: View {
    @Bindable var phase: CyclePhase
    let index: Int
    let onDelete: () -> Void
    
    @State private var cycleName: String = ""
    @State private var cycleMinutes: String = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Cycle \(index + 1)")
                    .font(.headline)
                
                Spacer()
                
                Button("Remove") {
                    onDelete()
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.red)
                .font(.caption)
            }
            
            VStack(spacing: 8) {
                HStack {
                    Text("Name:")
                        .frame(width: 60, alignment: .leading)
                    TextField("Cycle name", text: $cycleName)
                        .textFieldStyle(.roundedBorder)
                        .onAppear {
                            cycleName = phase.name
                        }
                        .onChange(of: cycleName) { _, newValue in
                            phase.name = newValue
                        }
                }
                
                HStack {
                    Text("Duration:")
                        .frame(width: 60, alignment: .leading)
                    TextField("Minutes", text: $cycleMinutes)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .keyboardType(.numberPad)
                        .onAppear {
                            cycleMinutes = "\(phase.totalMinutes)"
                        }
                        .onChange(of: cycleMinutes) { _, newValue in
                            if let minutes = Int(newValue), minutes > 0 {
                                phase.totalMinutes = minutes
                            }
                        }
                    Text("min")
                    Spacer()
                }
            }
        }
        .padding()
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    let instance = AlertInstance(name: "Test Alert", intervalMinutes: 5, useCycles: true)
    return EditAlertInstanceView(instance: instance)
}