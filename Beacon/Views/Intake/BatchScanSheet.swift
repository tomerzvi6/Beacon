import SwiftUI
import PhotosUI

/// "קופסת הנעליים" — shoot page after page (or multi-select from the
/// album), then upload the whole pile to the vault in one go. Each page
/// goes through the regular backend parse pipeline.
struct BatchScanSheet: View {
    let viewModel: MedicalVaultViewModel
    var onFinished: (Int, Int) -> Void = { _, _ in }

    @Environment(\.dismiss) private var dismiss

    private struct CapturedPage: Identifiable {
        let id = UUID()
        let image: UIImage
    }

    @State private var pages: [CapturedPage] = []
    @State private var showingCamera = false
    @State private var photosPickerVisible = false
    @State private var photosSelection: [PhotosPickerItem] = []
    @State private var isUploading = false
    @State private var uploadedCount = 0

    private let thumbnailColumns = [GridItem(.adaptive(minimum: 84), spacing: Theme.Spacing.s)]

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.m) {
                if pages.isEmpty {
                    emptyPitch
                } else {
                    capturedGrid
                }
                Spacer(minLength: Theme.Spacing.s)
                controls
            }
            .padding(Theme.Spacing.m)
            .beaconScreenBackground()
            .navigationTitle("ערימת מסמכים")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("ביטול") { dismiss() }
                        .disabled(isUploading)
                }
            }
            .interactiveDismissDisabled(isUploading)
        }
        .environment(\.layoutDirection, .rightToLeft)
        .fullScreenCover(isPresented: $showingCamera) {
            if DocumentScannerView.isSupported {
                // Apple's scanner stays open page after page and
                // auto-crops — the right tool for a document pile.
                DocumentScannerView(
                    onScan: { images in
                        pages.append(contentsOf: images.map { CapturedPage(image: $0) })
                        showingCamera = false
                    },
                    onCancel: { showingCamera = false }
                )
                .ignoresSafeArea()
            } else {
                // Simulator fallback — one page per shot.
                CameraPicker(
                    onImage: { image in
                        pages.append(CapturedPage(image: image))
                        showingCamera = false
                    },
                    onCancel: { showingCamera = false }
                )
                .ignoresSafeArea()
            }
        }
        .photosPicker(
            isPresented: $photosPickerVisible,
            selection: $photosSelection,
            maxSelectionCount: 20,
            matching: .images
        )
        .onChange(of: photosSelection) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task {
                for item in newItems {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        pages.append(CapturedPage(image: image))
                    }
                }
                photosSelection = []
            }
        }
    }

    // MARK: - Content states

    private var emptyPitch: some View {
        BeaconCard {
            VStack(spacing: Theme.Spacing.s) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.Palette.deepTeal)
                Text("אל תסדרו כלום — רק תצלמו")
                    .font(Theme.Typography.cardTitle)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text("מכתבי שחרור, בדיקות, סיכומים — צלמו דף אחרי דף בלי למיין. ביקון יזהה, יתייק ויסכם כל אחד מהם.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var capturedGrid: some View {
        ScrollView {
            VStack(alignment: .trailing, spacing: Theme.Spacing.s) {
                Text("\(pages.count) דפים בערימה")
                    .font(Theme.Typography.bodyEmphasis)
                    .foregroundStyle(Theme.Palette.textPrimary)
                LazyVGrid(columns: thumbnailColumns, spacing: Theme.Spacing.s) {
                    ForEach(pages) { page in
                        Image(uiImage: page.image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 84, height: 110)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.chip, style: .continuous))
                            .overlay(alignment: .topTrailing) {
                                if !isUploading {
                                    Button {
                                        pages.removeAll { $0.id == page.id }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 18))
                                            .foregroundStyle(.white, Theme.Palette.coralAccent)
                                    }
                                    .padding(Theme.Spacing.xxs)
                                }
                            }
                    }
                }
            }
        }
    }

    private var controls: some View {
        VStack(spacing: Theme.Spacing.s) {
            if isUploading {
                BeaconCard {
                    VStack(spacing: Theme.Spacing.s) {
                        ProgressView(value: Double(uploadedCount), total: Double(max(pages.count, 1)))
                            .tint(Theme.Palette.deepTeal)
                        Text("מעלים דף \(min(uploadedCount + 1, pages.count)) מתוך \(pages.count)…")
                            .font(Theme.Typography.captionEmphasis)
                            .foregroundStyle(Theme.Palette.textPrimary)
                    }
                }
            } else {
                BeaconPrimaryButton(
                    title: pages.isEmpty ? "התחלת סריקה" : "סריקת דפים נוספים",
                    systemImage: "doc.viewfinder.fill"
                ) {
                    // Simulator has neither the document scanner nor a camera —
                    // route to the album instead of crashing.
                    if DocumentScannerView.isSupported
                        || UIImagePickerController.isSourceTypeAvailable(.camera) {
                        showingCamera = true
                    } else {
                        photosPickerVisible = true
                    }
                }
                BeaconSecondaryButton(title: "בחירה מהאלבום", systemImage: "photo.on.rectangle.angled") {
                    photosPickerVisible = true
                }
                if !pages.isEmpty {
                    BeaconPrimaryButton(
                        title: "סיום והעלאת \(pages.count) דפים",
                        systemImage: "arrow.up.doc.fill"
                    ) {
                        Task { await uploadAll() }
                    }
                }
            }
        }
    }

    // MARK: - Upload

    @MainActor
    private func uploadAll() async {
        isUploading = true
        uploadedCount = 0
        let stamp = timestamp()
        let files: [PendingUploadFile] = pages.enumerated().compactMap { index, page in
            guard let data = page.image.jpegBytes() else { return nil }
            return PendingUploadFile(
                data: data,
                filename: "Beacon-batch-\(stamp)-\(index + 1).jpg",
                mimeType: "image/jpeg",
                sourceLabel: "ערימת מסמכים"
            )
        }
        let result = await viewModel.uploadBatch(files) { finished in
            uploadedCount = finished
        }
        isUploading = false
        onFinished(result.succeeded, result.failed)
        dismiss()
    }

    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter.string(from: Date())
    }
}

#if DEBUG
#Preview("BatchScanSheet") {
    Color.gray
        .sheet(isPresented: .constant(true)) {
            BatchScanSheet(
                viewModel: MedicalVaultViewModel(
                    context: MockDataSeeder.makeInMemoryPreviewContainer().mainContext
                )
            )
        }
}
#endif
