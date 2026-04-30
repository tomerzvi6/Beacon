import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

struct MedicalVaultView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppEnvironment.self) private var environment
    @State private var viewModel: MedicalVaultViewModel?
    @State private var openedDocument: MedicalDocument?

    // Upload-flow state
    private enum NextPicker { case camera, photos, files }
    @State private var showingActionSheet = false
    @State private var pendingNextPicker: NextPicker? = nil
    @State private var showingCameraPicker = false
    @State private var photosPickerVisible = false
    @State private var showingFileImporter = false
    @State private var photosSelection: PhotosPickerItem? = nil
    @State private var pendingFile: PendingUploadFile? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .trailing, spacing: Theme.Spacing.l) {
                    PatientStatusStrip()

                    if let vm = viewModel {
                        if let alert = vm.alert {
                            HospitalSyncAlertCard(alert: alert, onDismiss: { vm.dismissAlert() })
                        }

                        BeaconScreenHeader(
                            title: "תיק רפואי",
                            subtitle: "כל המסמכים והסיכומים של \(environment.patient.displayName), מסודרים וברורים."
                        )

                        AISmartSummaryFeatureCard(
                            summary: vm.featuredSummary,
                            onReadFullSummary: {
                                openedDocument = vm.documents.first {
                                    $0.aiSummaryKey == vm.featuredSummary.id
                                }
                            },
                            onAddSuggestedTasks: {
                                let added = vm.addSuggestedTasksToCalendar(from: vm.featuredSummary)
                                _ = added
                            },
                            importedTaskCount: vm.lastImportedTaskTitles.isEmpty ? nil : vm.lastImportedTaskTitles.count
                        )

                        searchField(vm: vm)
                        DocumentFilterChips(selection: Binding(
                            get: { vm.selectedFilter },
                            set: { vm.selectedFilter = $0 }
                        ))

                        if vm.filteredDocuments.isEmpty {
                            BeaconCard {
                                BeaconEmptyState(
                                    systemImage: "doc.text.magnifyingglass",
                                    title: vm.searchText.isEmpty ? "אין מסמכים בקטגוריה" : "לא נמצאו תוצאות",
                                    message: vm.searchText.isEmpty
                                        ? "מסמכים שיתקבלו מבית החולים יופיעו כאן אוטומטית."
                                        : "נסו לחפש מילת מפתח אחרת או לבחור קטגוריה אחרת."
                                )
                            }
                        } else {
                            VStack(spacing: Theme.Spacing.m) {
                                ForEach(vm.filteredDocuments) { doc in
                                    DocumentCard(
                                        document: doc,
                                        summary: vm.summary(for: doc),
                                        onOpen: { openedDocument = doc }
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(Theme.Spacing.m)
                .padding(.bottom, 96)  // leave room for the FAB
            }
            .beaconScreenBackground()
            .overlay(alignment: .bottomTrailing) {
                uploadFAB
                    .padding(Theme.Spacing.l)
            }
            .overlay(alignment: .center) {
                uploadProgressOverlay
            }
            .navigationDestination(item: $openedDocument) { doc in
                if let vm = viewModel {
                    DocumentDetailView(
                        document: doc,
                        summary: vm.summary(for: doc),
                        onAddSuggestedTasks: { _ in
                            if let summary = vm.summary(for: doc) {
                                _ = vm.addSuggestedTasksToCalendar(from: summary)
                            }
                        }
                    )
                }
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = MedicalVaultViewModel(context: context)
            } else {
                viewModel?.refresh()
            }
        }
        // 1. Action sheet (Camera / Photos / Files)
        // Defer presenting the next picker until the action sheet has
        // fully dismissed — SwiftUI ignores a second presentation while
        // the first is still animating out.
        .sheet(isPresented: $showingActionSheet, onDismiss: {
            guard let next = pendingNextPicker else { return }
            pendingNextPicker = nil
            switch next {
            case .camera: showingCameraPicker = true
            case .photos: photosPickerVisible = true
            case .files:  showingFileImporter = true
            }
        }) {
            UploadActionSheet(
                onCamera: { pendingNextPicker = .camera; showingActionSheet = false },
                onPhotos: { pendingNextPicker = .photos; showingActionSheet = false },
                onFiles:  { pendingNextPicker = .files;  showingActionSheet = false }
            )
        }
        // 2a. Camera picker
        .fullScreenCover(isPresented: $showingCameraPicker) {
            CameraPicker(
                onImage: { image in
                    showingCameraPicker = false
                    if let data = image.jpegBytes() {
                        pendingFile = PendingUploadFile(
                            data: data,
                            filename: "Beacon-\(timestamp()).jpg",
                            mimeType: "image/jpeg",
                            sourceLabel: "צילום"
                        )
                    }
                },
                onCancel: { showingCameraPicker = false }
            )
            .ignoresSafeArea()
        }
        // 2b. Photos picker (modifier-based, presents the system sheet)
        .photosPicker(
            isPresented: photosPickerBinding,
            selection: $photosSelection,
            matching: .images
        )
        .onChange(of: photosSelection) { _, newItem in
            guard let newItem else { return }
            Task { await loadPhotosItem(newItem) }
        }
        // 2c. File importer
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.pdf, .image],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        // 3. Metadata sheet
        .sheet(item: $pendingFile) { file in
            UploadMetadataSheet(
                filename: file.filename,
                sourceLabel: file.sourceLabel,
                mimeType: file.mimeType,
                byteCount: file.data.count,
                userRole: environment.backendUser?.role,
                onUpload: { category, isPrivate in
                    pendingFile = nil
                    Task { await viewModel?.upload(file, category: category, isPrivate: isPrivate) }
                },
                onCancel: { pendingFile = nil }
            )
        }
        // 4. Result alert
        .alert(
            uploadAlertTitle,
            isPresented: uploadAlertIsPresented,
            presenting: viewModel?.uploadAlert
        ) { _ in
            Button("סגור", role: .cancel) {
                viewModel?.uploadAlert = nil
            }
        } message: { alert in
            Text(Self.uploadAlertMessage(alert))
        }
    }

    // MARK: - Alert plumbing

    private var uploadAlertTitle: String {
        switch viewModel?.uploadAlert {
        case .success:   return "הקובץ הועלה"
        case .duplicate: return "המסמך כבר קיים בתיק"
        case .failure:   return "ההעלאה נכשלה"
        case .none:      return ""
        }
    }

    private var uploadAlertIsPresented: Binding<Bool> {
        Binding(
            get: { viewModel?.uploadAlert != nil },
            set: { newValue in
                if !newValue { viewModel?.uploadAlert = nil }
            }
        )
    }

    private static func uploadAlertMessage(_ alert: MedicalVaultViewModel.UploadAlert) -> String {
        switch alert {
        case .success(let filename, _):
            return "\"\(filename)\" עלה בהצלחה לתיק הרפואי."
        case .duplicate(let filename, let uploadedAt):
            let when = uploadedAt.map(formatDate) ?? "תאריך לא ידוע"
            return "\"\(filename)\" הועלה לתיק ב-\(when). לא נוצרה גרסה כפולה."
        case .failure(let message):
            return message
        }
    }

    // MARK: - FAB + progress overlay

    private var uploadFAB: some View {
        Button {
            showingActionSheet = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Theme.Palette.deepTeal, in: Circle())
                .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
        }
        .accessibilityLabel("הוספת מסמך לתיק")
        .disabled(uploadingProgress != nil)
    }

    @ViewBuilder
    private var uploadProgressOverlay: some View {
        if let progress = uploadingProgress {
            VStack(spacing: Theme.Spacing.m) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(Theme.Palette.deepTeal)
                Text("מעלה את הקובץ… \(Int(progress * 100))%")
                    .font(Theme.Typography.captionEmphasis)
                    .foregroundStyle(Theme.Palette.textPrimary)
            }
            .padding(Theme.Spacing.l)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.card, style: .continuous))
            .shadow(radius: 10)
            .padding(.horizontal, Theme.Spacing.xl)
        }
    }

    private var uploadingProgress: Double? {
        guard let vm = viewModel else { return nil }
        if case .uploading(let p) = vm.uploadPhase { return p }
        return nil
    }

    // MARK: - Photos picker plumbing

    private var photosPickerBinding: Binding<Bool> {
        Binding(
            get: { photosPickerVisible },
            set: { photosPickerVisible = $0 }
        )
    }

    @MainActor
    private func loadPhotosItem(_ item: PhotosPickerItem) async {
        defer { photosSelection = nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        // Re-encode as JPEG so the backend ALLOWED_MIME_TYPES list accepts it
        // even when the source was HEIC.
        let bytes: Data
        let mime: String
        if let image = UIImage(data: data), let jpeg = image.jpegBytes() {
            bytes = jpeg
            mime = "image/jpeg"
        } else {
            bytes = data
            mime = "image/jpeg"
        }
        pendingFile = PendingUploadFile(
            data: bytes,
            filename: "Beacon-\(timestamp()).jpg",
            mimeType: mime,
            sourceLabel: "אלבום"
        )
    }

    // MARK: - File importer

    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let needsScopedAccess = url.startAccessingSecurityScopedResource()
        defer { if needsScopedAccess { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        let mime = mimeType(for: url)
        pendingFile = PendingUploadFile(
            data: data,
            filename: url.lastPathComponent,
            mimeType: mime,
            sourceLabel: "קובץ"
        )
    }

    private func mimeType(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf":          return "application/pdf"
        case "png":          return "image/png"
        case "heic", "heif": return "image/heic"
        case "jpg", "jpeg":  return "image/jpeg"
        default:
            if let type = UTType(filenameExtension: ext)?.preferredMIMEType { return type }
            return "application/octet-stream"
        }
    }

    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "he_IL")
        return formatter.string(from: date)
    }

    // MARK: - Search field

    private func searchField(vm: MedicalVaultViewModel) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.Palette.textSecondary)
            TextField("חיפוש מסמך, תאריך או מילת מפתח...", text: Binding(
                get: { vm.searchText },
                set: { vm.searchText = $0 }
            ))
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.Palette.textPrimary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, Theme.Spacing.m)
        .background(Theme.Palette.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.chip, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.chip, style: .continuous)
                .strokeBorder(Theme.Palette.textSecondary.opacity(0.15), lineWidth: 1)
        )
    }
}

#Preview("MedicalVaultView") {
    let container = MockDataSeeder.makeInMemoryPreviewContainer()
    return MedicalVaultView()
        .modelContainer(container)
        .environment(AppEnvironment())
        .environment(\.locale, Locale(identifier: "he_IL"))
        .environment(\.layoutDirection, .rightToLeft)
}
