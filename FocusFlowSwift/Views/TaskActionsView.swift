import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import QuickLook
import PhotosUI

struct TaskRewardActionsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Reward.name) private var allRewards: [Reward]
    
    @Bindable var task: Task
    var onTaskDeleted: () -> Void
    
    @State private var showAddRewardLink = false
    @State private var showDeleteConfirmation = false
    @State private var linkToDelete: TaskRewardLink?
    
    var activeRewardLinks: [TaskRewardLink] {
        task.rewardLinks?.filter { $0.isActive } ?? []
    }
    
    var body: some View {
        NavigationView {
            List {
                // Task Info Section
                Section("Task Details") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(task.title)
                            .font(.headline)
                        
                        if !task.taskDescription.isEmpty {
                            Text(task.taskDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        HStack {
                            Label("Weight: \(String(format: "%.1f", task.weight))", systemImage: "star.fill")
                                .font(.caption)
                            
                            Spacer()
                            
                            if task.completed {
                                Label("Completed", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
                
                // Reward Workflows Section
                Section {
                    if activeRewardLinks.isEmpty {
                        ContentUnavailableView(
                            "No Reward Workflows",
                            systemImage: "gift.fill",
                            description: Text("Add rewards to automatically earn points when this task is completed")
                        )
                    } else {
                        ForEach(activeRewardLinks) { link in
                            RewardLinkRow(link: link, onDelete: {
                                linkToDelete = link
                                showDeleteConfirmation = true
                            })
                        }
                    }
                } header: {
                    HStack {
                        Text("Reward Workflows")
                        Spacer()
                        Button {
                            showAddRewardLink = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                    }
                } footer: {
                    Text("When this task is completed, points will be automatically added to the linked rewards")
                }
                

                
                // Quick Actions Section
                Section("Quick Actions") {
                    Button {
                        processTaskCompletion()
                    } label: {
                        Label("Complete & Add Points", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    .disabled(task.completed || activeRewardLinks.isEmpty)
                    
                    Button {
                        task.completed = false
                        try? modelContext.save()
                    } label: {
                        Label("Mark as Incomplete", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(!task.completed)
                }
                
                // Delete Task
                Section {
                    Button(role: .destructive) {
                        modelContext.delete(task)
                        try? modelContext.save()
                        onTaskDeleted()
                        dismiss()
                    } label: {
                        Label("Delete Task", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Task Actions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showAddRewardLink) {
                AddRewardLinkView(task: task, availableRewards: allRewards)
            }
            .alert("Delete Workflow", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    if let link = linkToDelete {
                        link.isActive = false
                        try? modelContext.save()
                    }
                }
            } message: {
                Text("Are you sure you want to remove this reward workflow?")
            }
        }
    }
    
    private func processTaskCompletion() {
        task.completed = true
        
        if !activeRewardLinks.isEmpty {
            // Add points to all linked rewards
            print("🎁 Task has \(activeRewardLinks.count) reward link(s)")
            for link in activeRewardLinks {
                if let reward = link.reward {
                    print("➕ Adding \(link.pointsToAdd) points to '\(reward.name)'")
                    reward.addAmount(link.pointsToAdd, context: modelContext, taskTitle: task.title)
                }
            }
        } else {
            // No reward links - add to Unclaimed Points
            print("➕ No reward links, adding \(task.effectiveWeight) points to Unclaimed Points")
            Reward.addUnclaimedPoints(task.effectiveWeight, context: modelContext)
        }
        
        try? modelContext.save()
    }
}

struct RewardLinkRow: View {
    let link: TaskRewardLink
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(link.reward?.name ?? "Unknown Reward")
                    .font(.headline)
                
                Text("\(String(format: "%.1f", link.pointsToAdd)) points")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if let reward = link.reward {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(reward.computedStatus.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(statusColor(reward.computedStatus))
                        .foregroundStyle(.white)
                        .cornerRadius(4)
                    
                    if let goal = reward.goalAmount {
                        Text("\(String(format: "%.0f", reward.currentAmount))/\(String(format: "%.0f", goal))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
        }
    }
    
    private func statusColor(_ status: RewardStatus) -> Color {
        switch status {
        case .needPoints: return .orange
        case .readyToUse: return .green
        case .utilized: return .gray
        }
    }
}

struct AddRewardLinkView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    let task: Task
    let availableRewards: [Reward]
    
    @State private var selectedReward: Reward?
    @State private var showCreateReward = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("Select Reward") {
                    if availableRewards.isEmpty {
                        Text("No rewards available")
                            .foregroundStyle(.secondary)
                        
                        Button("Create New Reward") {
                            showCreateReward = true
                        }
                    } else {
                        Picker("Reward", selection: $selectedReward) {
                            Text("Select a reward").tag(nil as Reward?)
                            ForEach(availableRewards) { reward in
                                Text(reward.name).tag(reward as Reward?)
                            }
                        }
                        
                        Button("Create New Reward") {
                            showCreateReward = true
                        }
                    }
                }
                
                if let reward = selectedReward {
                    Section("Reward Info") {
                        HStack {
                            Text("Current:")
                            Spacer()
                            Text(reward.formattedAmount())
                        }
                        
                        if let goal = reward.goalAmount {
                            HStack {
                                Text("Goal:")
                                Spacer()
                                Text(reward.formattedAmount(goal))
                            }
                            
                            HStack {
                                Text("Progress:")
                                Spacer()
                                Text("\(String(format: "%.0f", reward.progressPercentage))%")
                            }
                        }
                        
                        HStack {
                            Text("Status:")
                            Spacer()
                            Text(reward.computedStatus.rawValue)
                                .foregroundStyle(statusColor(reward.computedStatus))
                        }
                    }
                }
                
                Section("Points from Task") {
                    HStack {
                        Text("Base Weight:")
                        Spacer()
                        Text(String(format: "%.1f pts", task.weight))
                            .font(.headline)
                            .foregroundStyle(.blue)
                    }
                    
                    if let timeSpent = task.timeSpent, task.allocatedTimeInMinutes > 0 {
                        HStack {
                            Text("Time Spent:")
                            Spacer()
                            Text(String(format: "%.0f / %.0f min", timeSpent, task.allocatedTimeInMinutes))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        HStack {
                            Text("Effective Points:")
                            Spacer()
                            Text(String(format: "%.1f pts", task.effectiveWeight))
                                .font(.headline)
                                .foregroundStyle(.green)
                        }
                    }
                    
                    Text("Points are proportional to time spent. Complete the full allocated time to earn all points.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add Reward Workflow")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        saveRewardLink()
                    }
                    .disabled(selectedReward == nil || task.weight <= 0)
                }
            }
            .sheet(isPresented: $showCreateReward) {
                AddRewardView()
            }
        }
    }
    
    private func saveRewardLink() {
        guard let reward = selectedReward,
              task.weight > 0 else { return }
        
        let link = TaskRewardLink(task: task, reward: reward)
        modelContext.insert(link)
        
        try? modelContext.save()
        dismiss()
    }
    
    private func statusColor(_ status: RewardStatus) -> Color {
        switch status {
        case .needPoints: return .orange
        case .readyToUse: return .green
        case .utilized: return .gray
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Task.self, Reward.self, configurations: config)
    let context = container.mainContext
    
    let task = Task(title: "Sample Task", weight: 10.0)
    context.insert(task)
    
    return TaskRewardActionsView(task: task, onTaskDeleted: {})
        .modelContainer(container)
}

struct TaskAttachmentsManagementView: View {
    @Bindable var task: Task
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var fileManager = FileAttachmentManager.shared
    
    @State private var showingFilePicker = false
    @State private var showingPhotoPicker = false
    @State private var showingPreview = false
    @State private var previewURL: URL?
    @State private var dragOver = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var currentPreviewIndex = 0
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Upload Section
                    uploadSection
                    
                    // Attachments Grid
                    if let attachments = task.attachments, !attachments.isEmpty {
                        attachmentsGrid(attachments)
                    } else {
                        emptyStateView
                    }
                }
                .padding()
            }
            .navigationTitle("File Attachments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            showingFilePicker = true
                        } label: {
                            Label("Browse Files", systemImage: "folder")
                        }
                        
                        Button {
                            showingPhotoPicker = true
                        } label: {
                            Label("Photo Library", systemImage: "photo.on.rectangle")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $dragOver) { providers in
                handleDrop(providers: providers)
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.image, .pdf, .text, .data],
                allowsMultipleSelection: true
            ) { result in
                handleFileSelection(result: result)
            }
            .photosPicker(
                isPresented: $showingPhotoPicker,
                selection: $selectedPhotoItems,
                maxSelectionCount: 10,
                matching: .images
            )
            .onChange(of: selectedPhotoItems) { _, newItems in
                handlePhotoSelection(items: newItems)
            }
            .quickLookPreview($previewURL)
            .sheet(isPresented: $showingPreview) {
                if let attachments = task.attachments, !attachments.isEmpty {
                    SwipeableFilePreviewView(
                        attachments: attachments,
                        currentIndex: $currentPreviewIndex
                    )
                }
            }
        }
    }
    
    private var uploadSection: some View {
        VStack(spacing: 12) {
            Text("Upload Files")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            RoundedRectangle(cornerRadius: 12)
                .fill(dragOver ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                .frame(height: 100)
                .overlay(
                    VStack(spacing: 8) {
                        Image(systemName: dragOver ? "doc.badge.plus.fill" : "doc.badge.plus")
                            .font(.title2)
                            .foregroundColor(dragOver ? .blue : .gray)
                        
                        Text(dragOver ? "Drop files here" : "Drag & drop files or tap to browse")
                            .font(.subheadline)
                            .foregroundColor(dragOver ? .blue : .gray)
                        
                        Text("Supports: PNG, JPEG, PDF")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                )
                .onTapGesture {
                    showingFilePicker = true
                }
            
            // Quick action buttons
            HStack(spacing: 12) {
                Button {
                    showingFilePicker = true
                } label: {
                    Label("Browse Files", systemImage: "folder")
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.blue)
                        .cornerRadius(8)
                }
                
                Button {
                    showingPhotoPicker = true
                } label: {
                    Label("Photo Library", systemImage: "photo.on.rectangle")
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.green)
                        .cornerRadius(8)
                }
                
                Spacer()
            }
        }
    }
    
    private func attachmentsGrid(_ attachments: [TaskAttachment]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Attached Files (\(attachments.count))")
                .font(.headline)
            
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 120, maximum: 150))
            ], spacing: 16) {
                    ForEach(attachments.indices, id: \.self) { index in
                        let attachment = attachments[index]
                        AttachmentCard(
                            attachment: attachment,
                            onPreview: { previewAttachment(attachment, at: index) },
                            onDelete: { deleteAttachment(attachment) }
                        )
                    }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            
            Text("No Files Attached")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("Add files or photos to keep important documents with this task")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            HStack(spacing: 12) {
                Button {
                    showingFilePicker = true
                } label: {
                    Label("Add Files", systemImage: "folder")
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding()
                        .background(.blue)
                        .cornerRadius(10)
                }
                
                Button {
                    showingPhotoPicker = true
                } label: {
                    Label("Add Photos", systemImage: "photo.on.rectangle")
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding()
                        .background(.green)
                        .cornerRadius(10)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                    if let data = item as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil) {
                        DispatchQueue.main.async {
                            addAttachment(from: url)
                        }
                    }
                }
            }
        }
        return true
    }
    
    private func handleFileSelection(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                addAttachment(from: url)
            }
        case .failure(let error):
            print("File selection error: \(error)")
        }
    }
    
    private func handlePhotoSelection(items: [PhotosPickerItem]) {
        for item in items {
            _Concurrency.Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    // Create a temporary file from the photo data
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension("jpg")
                    
                    do {
                        try data.write(to: tempURL)
                        
                        // Add the attachment on the main thread
                        await MainActor.run {
                            addAttachment(from: tempURL)
                        }
                        
                        // Clean up temporary file
                        try? FileManager.default.removeItem(at: tempURL)
                    } catch {
                        print("Error processing photo: \(error)")
                    }
                }
            }
        }
        
        // Clear the selection
        selectedPhotoItems = []
    }
    
    private func addAttachment(from url: URL) {
        do {
            let attachment = try fileManager.saveFile(from: url, for: task.id)
            attachment.task = task
            
            modelContext.insert(attachment)
            try modelContext.save()
        } catch {
            print("Error adding attachment: \(error)")
        }
    }
    
    private func deleteAttachment(_ attachment: TaskAttachment) {
        fileManager.deleteAttachment(attachment)
        modelContext.delete(attachment)
        try? modelContext.save()
    }
    
    private func previewAttachment(_ attachment: TaskAttachment, at index: Int) {
        if attachment.canPreview {
            currentPreviewIndex = index
            showingPreview = true
        }
    }
}

struct AttachmentCard: View {
    let attachment: TaskAttachment
    let onPreview: () -> Void
    let onDelete: () -> Void
    
    @StateObject private var fileManager = FileAttachmentManager.shared
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                // Thumbnail or icon
                Group {
                    if attachment.isImage, let thumbnailData = attachment.thumbnailData,
                       let uiImage = UIImage(data: thumbnailData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 100, height: 100)
                            .clipped()
                            .cornerRadius(8)
                    } else if attachment.isPDF, let thumbnailData = attachment.thumbnailData,
                              let uiImage = UIImage(data: thumbnailData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 100, height: 100)
                            .clipped()
                            .cornerRadius(8)
                            .overlay(
                                Image(systemName: "doc.fill")
                                    .foregroundColor(.red)
                                    .background(Color.white.opacity(0.8))
                                    .cornerRadius(4)
                                    .padding(4),
                                alignment: .bottomTrailing
                            )
                    } else {
                        Image(uiImage: fileManager.getFileIcon(for: attachment.fileType))
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 60, height: 60)
                            .padding(20)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
                .onTapGesture {
                    onPreview()
                }
                
                // Delete button
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .background(Color.white)
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
                .offset(x: 5, y: -5)
            }
            
            // File info
            VStack(spacing: 4) {
                Text(attachment.fileName)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                
                Text(attachment.formattedFileSize)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                if attachment.canPreview {
                    Text("Tap to preview")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
            }
        }
        .frame(width: 120)
        .padding(8)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}