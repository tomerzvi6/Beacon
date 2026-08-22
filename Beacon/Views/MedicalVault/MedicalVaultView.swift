import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

struct MedicalVaultView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppEnvironment.self) private var environment
    @State private var viewModel: MedicalVaultViewModel?
    @State private var openedDocument: BackendDocument?
    @State private var openedSummary: AISummary?
    @State private var searchDebounceTask: Task<Void, Never>? = nil

    // Upload-flow state
    private enum NextPicker { case camera, photos, files }
    @State private var showingActionSheet = false
    @State private var pendingNextPicker: NextPicker? = nil
    @State private var showingCameraPicker = false
    @State private var photosPickerVisible = false
    @State private var showingFileImporter = false
    @State private var photosSelection: PhotosPickerItem? = nil
    @State private var pendingFile: PendingUploadFile? = nil
    @State private var showingBackendAuthAlert = false

    // Independent-mode intake state
    private enum IndependentAction { case batchScan, medicationLabel, appointment, files }
    @State private var showingIndependentIntake = false
    @State private var pendingIndependentAction: IndependentAction? = nil
    @State private var showingBatchScan = false
    @State private var showingMedicationIntake = false
    @State private var showingAppointmentIntake = false
    @State private var intakeToast: String? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .trailing, spacing: Theme.Spacing.m) {
                        if let vm = viewModel {
                            // Hospital-sync alerts belong to the integrated build only —
                            // in independent mode nothing arrives "from the hospital".
                            if environment.dataSourceMode == .hospitalIntegrated, let alert = vm.alert {
                                HospitalSyncAlertCard(alert: alert, onDismiss: { vm.dismissAlert() })
                            }

                            BeaconScreenHeader(
                                title: "תיק רפואי",
                                subtitle: environment.isIndependentMode
                                    ? "מצלמים — וביקון מזהה, מתייק ומסכם לבד."
                                    : "כל המסמכים והסיכומים של \(environment.patient.displayName), מסודרים וברורים."
                            )

                            if environment.isIndependentMode {
                                quickIntakeStrip
                            }

                            // In independent mode, only a summary of a document the
                            // family actually uploaded may appear — showing the static
                            // demo summary to a fresh user reads as someone else's data.
                            // The integrated build keeps the demo card as a showcase.
                            if let activeSummary = vm.featuredAISummary
                                ?? (environment.isIndependentMode ? nil : vm.featuredSummary) {
                                AISmartSummaryFeatureCard(
                                    summary: activeSummary,
                                    onReadFullSummary: {
                                        // Navigate to the full document detail when a real
                                        // parsed document is available; otherwise show the
                                        // static demo in AISummaryDetailView.
                                        if let doc = vm.featuredDocument {
                                            openedDocument = doc
                                        } else {
                                            openedSummary = activeSummary
                                        }
                                    },
                                    onAddSuggestedTasks: {
                                        Task { _ = await vm.addSuggestedTasksToCalendar(from: activeSummary) }
                                    },
                                    importedTaskCount: vm.lastImportedTaskTitles.isEmpty
                                        ? nil
                                        : vm.lastImportedTaskTitles.count,
                                    isExample: vm.featuredAISummary == nil
                                )
                            }

                            if shouldShowDocumentControls(vm) {
                                searchField(vm: vm)
                                DocumentFilterChips(
                                    selection: Binding(
                                        get: { vm.selectedCategory },
                                        set: { newValue in
                                            vm.selectedCategory = newValue
                                            Task { await vm.refresh() }
                                        }
                                    )
                                )
                            }

                            documentList(vm: vm)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.m)
                    .padding(.top, Theme.Layout.scrollContentTopClearance)
                    .padding(.bottom, Theme.Layout.scrollContentBottomClearance)
                }
                .refreshable {
                    await viewModel?.refresh()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar(.hidden, for: .navigationBar)
            .beaconScreenBackground()
            .overlay(alignment: .bottomTrailing) {
                uploadFAB
                    .padding(.horizontal, Theme.Spacing.l)
                    .padding(.bottom, Theme.Layout.scrollContentBottomClearance)
            }
            .overlay(alignment: .center) {
                uploadProgressOverlay
            }
            .overlay(alignment: .bottom) {
                if let intakeToast {
                    Text(intakeToast)
                        .font(Theme.Typography.bodyEmphasis)
                        .foregroundStyle(Theme.Palette.textPrimary)
                        .padding(.vertical, Theme.Layout.controlVerticalPadding)
                        .padding(.horizontal, Theme.Spacing.l)
                        .background(.regularMaterial, in: Capsule())
                        .beaconCardShadow()
                        .padding(.bottom, Theme.Spacing.l)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: intakeToast)
            .sensoryFeedback(.success, trigger: intakeToast)
            .task(id: intakeToast) {
                guard intakeToast != nil else { return }
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                intakeToast = nil
            }
            .navigationDestination(item: $openedDocument) { doc in
                DocumentDetailView(document: doc)
            }
            .navigationDestination(item: $openedSummary) { summary in
                AISummaryDetailView(
                    summary: summary,
                    onAddSuggestedTasks: { _ in
                        Task { _ = await viewModel?.addSuggestedTasksToCalendar(from: summary) }
                    },
                    // Reached only via the fallback path in the closure
                    // above (no real parsed document) — always the demo.
                    isExample: true
                )
            }
        }
        .task {
            // First-time setup — instantiate the view model and load
            // the first page from the backend.
            if viewModel == nil {
                viewModel = MedicalVaultViewModel(context: context)
                await viewModel?.refresh()
            }
        }
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
        .sheet(isPresented: $showingIndependentIntake, onDismiss: {
            guard let action = pendingIndependentAction else { return }
            pendingIndependentAction = nil
            switch action {
            case .batchScan, .files:
                startDocumentPath(action)
            case .medicationLabel:
                showingMedicationIntake = true
            case .appointment:
                showingAppointmentIntake = true
            }
        }) {
            IndependentIntakeSheet(
                onBatchScan: { pendingIndependentAction = .batchScan },
                onMedicationLabel: { pendingIndependentAction = .medicationLabel },
                onAppointment: { pendingIndependentAction = .appointment },
                onFiles: { pendingIndependentAction = .files }
            )
        }
        .sheet(isPresented: $showingBatchScan) {
            if let vm = viewModel {
                BatchScanSheet(viewModel: vm) { succeeded, failed in
                    // Only celebrate a clean run — showing a green "success"
                    // toast at the same moment a failure alert pops up
                    // (MedicalVaultViewModel.uploadBatch sets one whenever
                    // failed > 0) reads as the app contradicting itself.
                    if succeeded > 0 && failed == 0 {
                        intakeToast = "\(succeeded) דפים נכנסו לתיק ומעובדים ברקע ✓"
                    }
                }
            }
        }
        .sheet(isPresented: $showingMedicationIntake) {
            MedicationLabelIntakeSheet { medicationName in
                intakeToast = "\(medicationName) נוספה ללוח התרופות ✓"
            }
        }
        .sheet(isPresented: $showingAppointmentIntake) {
            AppointmentIntakeSheet { _ in
                intakeToast = "התור נוסף ליומן המשפחתי ✓"
            }
        }
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
        .photosPicker(
            isPresented: photosPickerBinding,
            selection: $photosSelection,
            matching: .images
        )
        .onChange(of: photosSelection) { _, newItem in
            guard let newItem else { return }
            Task { await loadPhotosItem(newItem) }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.pdf, .image],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
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
        .alert("נדרשת התחברות מלאה", isPresented: $showingBackendAuthAlert) {
            Button("סגור", role: .cancel) {}
        } message: {
            Text("כדי להעלות PDF או תמונה, צריך להתחבר עם Apple או Google. ההתחברות המלאה מאפשרת ל-Beacon לשמור ולעבד את המסמך בבטחה.")
        }
    }

    // MARK: - Document list (paginated)

    private func shouldShowDocumentControls(_ vm: MedicalVaultViewModel) -> Bool {
        !vm.documents.isEmpty || !vm.searchText.isEmpty || vm.selectedCategory != nil
    }

    @ViewBuilder
    private func documentList(vm: MedicalVaultViewModel) -> some View {
        if vm.documents.isEmpty && !vm.isLoading {
            BeaconCard {
                BeaconEmptyState(
                    systemImage: "doc.badge.plus",
                    title: vm.searchText.isEmpty
                        ? (vm.selectedCategory != nil ? "אין מסמכים בקטגוריה זו" : "אין מסמכים עדיין")
                        : "לא נמצאו תוצאות",
                    message: vm.searchText.isEmpty
                        ? (environment.isIndependentMode
                            ? "אל תסדרו כלום — רק תצלמו. כל דף שתצלמו יזוהה, יתויק ויסוכם בעברית פשוטה."
                            : "העלה מסמך ראשון כדי ש-Beacon יוכל לסכם אותו, לזהות משימות ולהציע תרופות לבדיקה.")
                        : "נסו לחפש מילת מפתח אחרת או לבחור קטגוריה אחרת.",
                    actionTitle: vm.searchText.isEmpty
                        ? (environment.isIndependentMode ? "התחלת צילום" : "העלה מסמך ראשון")
                        : nil,
                    action: vm.searchText.isEmpty ? beginUploadFlow : nil
                )
            }
        } else {
            VStack(spacing: Theme.Spacing.m) {
                ForEach(vm.documents) { doc in
                    DocumentCard(
                        document: doc,
                        isPolling: vm.pollingDocumentIds.contains(doc.id),
                        onOpen: { openedDocument = doc },
                        onRetryParse: {
                            Task { await vm.startParseAndPoll(documentId: doc.id) }
                        }
                    )
                    .onAppear {
                        if doc.id == vm.documents.last?.id, vm.hasMore {
                            Task { await vm.loadMore() }
                        }
                    }
                }
                if vm.isLoading && !vm.documents.isEmpty {
                    ProgressView().controlSize(.regular).padding(.vertical, Theme.Spacing.m)
                }
                if let msg = vm.loadErrorMessage {
                    Text(msg)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.coralAccent)
                        .padding(Theme.Spacing.m)
                }
            }
        }
    }

    // MARK: - FAB + progress overlay

    private func beginUploadFlow() {
        if environment.isIndependentMode {
            // Medication + appointment intake are fully local — the auth
            // gate applies only when a document upload path is chosen.
            showingIndependentIntake = true
            return
        }
        if TokenStore.read() == nil {
            showingBackendAuthAlert = true
        } else {
            showingActionSheet = true
        }
    }

    /// Requires backend auth (document uploads go through the parser API).
    private func startDocumentPath(_ action: IndependentAction) {
        if TokenStore.read() == nil {
            showingBackendAuthAlert = true
            return
        }
        switch action {
        case .batchScan: showingBatchScan = true
        case .files: showingFileImporter = true
        default: break
        }
    }

    // MARK: - Independent-mode quick intake

    /// One-tap capture strip — the three most-used intake paths, always
    /// visible so families never hunt for the FAB.
    private var quickIntakeStrip: some View {
        HStack(spacing: Theme.Spacing.s) {
            quickIntakeButton(
                icon: "square.stack.3d.up.fill",
                label: "ערימת\nמסמכים",
                tint: Theme.Palette.deepTeal
            ) {
                startDocumentPath(.batchScan)
            }
            quickIntakeButton(
                icon: "pills.fill",
                label: "קופסת\nתרופה",
                tint: Theme.Palette.sageDark
            ) {
                showingMedicationIntake = true
            }
            quickIntakeButton(
                icon: "calendar.badge.plus",
                label: "זימון\nתור",
                tint: Theme.Palette.softBlue
            ) {
                showingAppointmentIntake = true
            }
        }
    }

    private func quickIntakeButton(
        icon: String,
        label: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: Theme.Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
                Text(label)
                    .font(Theme.Typography.captionEmphasis)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.s + Theme.Spacing.xs)
            .background(Theme.Palette.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.card, style: .continuous))
            .beaconCardShadow()
        }
        .buttonStyle(.plain)
    }

    private var uploadFAB: some View {
        Button {
            beginUploadFlow()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: Theme.Layout.floatingActionButtonSize, height: Theme.Layout.floatingActionButtonSize)
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
            return "\"\(filename)\" עלה בהצלחה לתיק הרפואי. מעבדים אותו ברקע."
        case .duplicate(let filename, let uploadedAt):
            let when = uploadedAt.map(formatDate) ?? "תאריך לא ידוע"
            return "\"\(filename)\" הועלה לתיק ב-\(when). לא נוצרה גרסה כפולה."
        case .failure(let message):
            return message
        }
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
            TextField(
                "חיפוש מסמך, תאריך או מילת מפתח...",
                text: Binding(
                    get: { vm.searchText },
                    set: { newValue in
                        vm.searchText = newValue
                        // 400ms debounce so we don't fire a request per keystroke.
                        searchDebounceTask?.cancel()
                        searchDebounceTask = Task {
                            try? await Task.sleep(nanoseconds: 400_000_000)
                            if !Task.isCancelled {
                                await vm.refresh()
                            }
                        }
                    }
                )
            )
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.Palette.textPrimary)
        }
        .padding(.vertical, Theme.Layout.controlVerticalPadding)
        .padding(.horizontal, Theme.Spacing.m)
        .background(Theme.Palette.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.chip, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.chip, style: .continuous)
                .strokeBorder(Theme.Palette.textSecondary.opacity(0.15), lineWidth: 1)
        )
    }
}
