//
//  AddBathroomView.swift
//  GeoPoop
//
//  Full-screen form for adding a new bathroom OR editing an existing one.
//  Pass `editing: bathroom` to pre-fill all fields and update on save.
//
//  Form sections (in order):
//    1. Mini map + reverse-geocoded address
//    2. Name (required) · Date Visited
//    3. Overall Rating
//    4. Access & Availability
//    5. Layout
//    6. Toilet Paper
//    7. Amenities & Fixtures
//    8. Hygiene & Wait Time
//    9. Photos
//   10. Notes
//

import CoreLocation
import MapKit
import PhotosUI
import SwiftData
import SwiftUI

struct AddBathroomView: View {

    // MARK: - Environment

    @Environment(\.dismiss)            private var dismiss
    @Environment(\.modelContext)       private var modelContext
    @Environment(SupabaseService.self) private var supabaseService
    @Environment(SyncQueue.self)       private var syncQueue

    // MARK: - Input

    let userLocation: CLLocationCoordinate2D?
    let editing: Bathroom?

    // MARK: - Core Fields

    @State private var name        = ""
    @State private var rating      = 0
    @State private var notes       = ""
    @State private var dateVisited = Date()

    // MARK: - Access & Availability

    @State private var accessType           = BathroomAccess.free
    @State private var requiresReceiptCode  = false
    @State private var isOpen24Hours        = false

    // MARK: - Layout

    @State private var stallType             = StallType.single
    @State private var genderType            = GenderType.allGender
    @State private var isIndoor              = true
    @State private var isWheelchairAccessible = false

    // MARK: - Toilet Paper

    @State private var hasToiletPaper      = true
    @State private var hasExtraToiletPaper = false
    @State private var hasDispenser        = false   // form-only; maps to dispenserRating
    @State private var dispenserRating     = 0       // 1–5 when hasDispenser is true

    // MARK: - Amenities & Fixtures

    @State private var hasHeatedSeat    = false
    @State private var bidetType        = BidetType.none
    @State private var hasChangingTable = false

    // MARK: - Hygiene & Wait

    @State private var hasSoap        = true
    @State private var hasDryingOption = true
    @State private var waitTime        = WaitTime.unknown

    // MARK: - Location

    @State private var selectedCoordinate: CLLocationCoordinate2D
    @State private var geocodedAddress = ""
    @State private var isGeocoding     = false
    @State private var geocodeTask: Task<Void, Never>?

    // MARK: - Photos

    @State private var existingFileNames: [String]  = []
    @State private var selectedPhotos: [UIImage]    = []
    @State private var photoPickerItems: [PhotosPickerItem] = []

    // MARK: - Cloud / Privacy

    @State private var isPrivate = false

    // MARK: - UI State

    @State private var showDiscardAlert = false
    @State private var showCamera       = false
    @State private var isSaving         = false
    @FocusState private var nameFocused: Bool

    // MARK: - Computed

    private var isEditMode: Bool     { editing != nil }
    private var totalPhotoCount: Int { existingFileNames.count + selectedPhotos.count }
    private var canSave: Bool        { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving }

    private var isDirty: Bool {
        if let b = editing {
            return name                   != b.name
                || rating                 != b.rating
                || notes                  != b.notes
                || dateVisited            != b.dateVisited
                || accessType             != b.accessType
                || requiresReceiptCode    != b.requiresReceiptCode
                || isOpen24Hours          != b.isOpen24Hours
                || stallType              != b.stallType
                || genderType             != b.genderType
                || isIndoor               != b.isIndoor
                || isWheelchairAccessible != b.isWheelchairAccessible
                || hasToiletPaper         != b.hasToiletPaper
                || hasExtraToiletPaper    != b.hasExtraToiletPaper
                || dispenserRating        != b.dispenserRating
                || hasHeatedSeat          != b.hasHeatedSeat
                || bidetType              != b.bidetType
                || hasChangingTable       != b.hasChangingTable
                || hasSoap                != b.hasSoap
                || hasDryingOption        != b.hasDryingOption
                || waitTime               != b.waitTime
                || isPrivate              != b.isPrivate
                || existingFileNames      != b.imageFileNames
                || !selectedPhotos.isEmpty
        }
        return !name.isEmpty || rating > 0 || !notes.isEmpty || !selectedPhotos.isEmpty
            || accessType != .free || isOpen24Hours || !isIndoor || isWheelchairAccessible
            || !hasToiletPaper || hasDispenser || hasHeatedSeat || bidetType != .none
            || hasChangingTable || !hasSoap || !hasDryingOption
    }

    // MARK: - Init

    init(userLocation: CLLocationCoordinate2D?, editing: Bathroom? = nil) {
        self.userLocation = userLocation
        self.editing      = editing

        if let b = editing {
            _name                   = State(initialValue: b.name)
            _rating                 = State(initialValue: b.rating)
            _notes                  = State(initialValue: b.notes)
            _dateVisited            = State(initialValue: b.dateVisited)
            _accessType             = State(initialValue: b.accessType)
            _requiresReceiptCode    = State(initialValue: b.requiresReceiptCode)
            _isOpen24Hours          = State(initialValue: b.isOpen24Hours)
            _stallType              = State(initialValue: b.stallType)
            _genderType             = State(initialValue: b.genderType)
            _isIndoor               = State(initialValue: b.isIndoor)
            _isWheelchairAccessible = State(initialValue: b.isWheelchairAccessible)
            _hasToiletPaper         = State(initialValue: b.hasToiletPaper)
            _hasExtraToiletPaper    = State(initialValue: b.hasExtraToiletPaper)
            _hasDispenser           = State(initialValue: b.dispenserRating > 0)
            _dispenserRating        = State(initialValue: b.dispenserRating)
            _hasHeatedSeat          = State(initialValue: b.hasHeatedSeat)
            _bidetType              = State(initialValue: b.bidetType)
            _hasChangingTable       = State(initialValue: b.hasChangingTable)
            _hasSoap                = State(initialValue: b.hasSoap)
            _hasDryingOption        = State(initialValue: b.hasDryingOption)
            _waitTime               = State(initialValue: b.waitTime)
            _selectedCoordinate     = State(initialValue: b.coordinate)
            _existingFileNames      = State(initialValue: b.imageFileNames)
            _geocodedAddress        = State(initialValue: b.address ?? "")
            _isPrivate              = State(initialValue: b.isPrivate)
        } else {
            let start = userLocation ?? CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855)
            _selectedCoordinate = State(initialValue: start)
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // ── Mini Map ──────────────────────────────────────────────
                    MiniMapPicker(selectedCoordinate: $selectedCoordinate)
                        .frame(height: 220)
                        .onChange(of: selectedCoordinate.latitude)  { scheduleGeocode(for: selectedCoordinate) }
                        .onChange(of: selectedCoordinate.longitude) { scheduleGeocode(for: selectedCoordinate) }

                    // ── Address ───────────────────────────────────────────────
                    addressRow
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground))

                    // ── Form ──────────────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 0) {

                        formSection("Essentials") {
                            nameField
                            dateField
                        }

                        formDivider

                        formSection("Overall Rating") {
                            StarRatingInput(rating: $rating)
                        }

                        formDivider

                        formSection("Access & Hours") {
                            accessField
                            if accessType == .purchaseRequired {
                                receiptCodeField
                            }
                            open24HoursField
                        }

                        formDivider

                        // ── Additional Details ─────────────────────────────────────────
                        // Progressive disclosure: collapsed by default to avoid overwhelming
                        // new users. Power users can expand to fill in the full detail set.
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 0) {
                                formSection("Layout") {
                                    stallTypeField
                                    genderTypeField
                                    indoorField
                                    wheelchairField
                                }

                                formDivider

                                formSection("Toilet Paper") {
                                    toiletPaperField
                                    if hasToiletPaper {
                                        extraTpField
                                    }
                                    dispenserToggleField
                                    if hasDispenser {
                                        dispenserRatingField
                                    }
                                }

                                formDivider

                                formSection("Amenities & Fixtures") {
                                    heatedSeatField
                                    bidetField
                                    changingTableField
                                }

                                formDivider

                                formSection("Hygiene & Wait Time") {
                                    soapField
                                    dryingField
                                    waitTimeField
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "slider.horizontal.3")
                                    .foregroundStyle(.blue)
                                Text("Additional Details")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.blue)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                        }

                        formDivider

                        formSection("Photos") {
                            photosField
                        }

                        formDivider

                        formSection("Notes") {
                            notesField
                        }

                        formDivider

                        formSection("Privacy") {
                            privacyField
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isEditMode ? "Edit Bathroom" : "Add Bathroom")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { handleCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { nameFocused = false }
                }
            }
            .alert("Discard Changes?", isPresented: $showDiscardAlert) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("Your changes will be lost.")
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPickerView { image in
                    showCamera = false
                    if let image, totalPhotoCount < 10 { selectedPhotos.append(image) }
                }
                .ignoresSafeArea()
            }
        }
        .onAppear {
            if !isEditMode { scheduleGeocode(for: selectedCoordinate) }
        }
        .onChange(of: photoPickerItems) { _, newItems in
            loadPickerItems(newItems)
        }
    }

    // MARK: - Section Container

    private func formSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .tracking(0.6)
            content()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
    }

    private var formDivider: some View {
        Divider().padding(.horizontal, 20)
    }

    // MARK: - Address Row

    private var addressRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "location.fill").font(.caption).foregroundStyle(.blue)
            if isGeocoding {
                Text("Locating…").font(.caption).foregroundStyle(.secondary)
            } else if geocodedAddress.isEmpty {
                Text("Address unavailable").font(.caption).foregroundStyle(.secondary)
            } else {
                Text(geocodedAddress).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Essentials

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Name", required: true)
            TextField("e.g. Starbucks on Main", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .submitLabel(.done)
                .onSubmit { nameFocused = false }
        }
    }

    private var dateField: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Date Visited")
            DatePicker("", selection: $dateVisited, in: ...Date(), displayedComponents: .date)
                .labelsHidden()
        }
    }

    // MARK: - Access & Hours

    private var accessField: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("How do you get in?")
            Picker("Access", selection: $accessType) {
                ForEach(BathroomAccess.allCases) { access in
                    Label(access.displayName, systemImage: access.icon).tag(access)
                }
            }
            .pickerStyle(.menu)
            .tint(accessType.color)
        }
    }

    private var receiptCodeField: some View {
        Toggle(isOn: $requiresReceiptCode) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Code on Receipt").font(.subheadline)
                    Text("Restroom code is printed on purchase receipt")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "doc.text").foregroundStyle(.blue)
            }
        }
        .tint(.blue)
    }

    private var open24HoursField: some View {
        Toggle(isOn: $isOpen24Hours) {
            Label {
                Text("Open 24 Hours").font(.subheadline)
            } icon: {
                Image(systemName: "clock").foregroundStyle(isOpen24Hours ? .blue : .secondary)
            }
        }
        .tint(.blue)
    }

    // MARK: - Layout

    private var stallTypeField: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Stall Type")
            Picker("Stall type", selection: $stallType) {
                ForEach(StallType.allCases, id: \.rawValue) { s in
                    Label(s.displayName, systemImage: s.icon).tag(s)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var genderTypeField: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Gender")
            Picker("Gender", selection: $genderType) {
                ForEach(GenderType.allCases, id: \.rawValue) { g in
                    Label(g.displayName, systemImage: g.icon).tag(g)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var indoorField: some View {
        Toggle(isOn: $isIndoor) {
            Label {
                Text(isIndoor ? "Indoor" : "Outdoor").font(.subheadline)
            } icon: {
                Image(systemName: isIndoor ? "building.2" : "tree")
                    .foregroundStyle(isIndoor ? .blue : .green)
            }
        }
        .tint(.blue)
    }

    private var wheelchairField: some View {
        Toggle(isOn: $isWheelchairAccessible) {
            Label {
                Text("Wheelchair Accessible").font(.subheadline)
            } icon: {
                Image(systemName: "figure.roll")
                    .foregroundStyle(isWheelchairAccessible ? .blue : .secondary)
            }
        }
        .tint(.blue)
    }

    // MARK: - Toilet Paper

    private var toiletPaperField: some View {
        Toggle(isOn: $hasToiletPaper.animation(.easeInOut(duration: 0.2))) {
            Label {
                Text("Toilet Paper Available").font(.subheadline)
            } icon: {
                Image(systemName: "roll").foregroundStyle(hasToiletPaper ? .brown : .secondary)
            }
        }
        .tint(.brown)
    }

    private var extraTpField: some View {
        Toggle(isOn: $hasExtraToiletPaper) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Extra Rolls Available").font(.subheadline)
                    Text("Backup rolls are stocked, not just one roll")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "plus.circle").foregroundStyle(hasExtraToiletPaper ? .brown : .secondary)
            }
        }
        .tint(.brown)
    }

    private var dispenserToggleField: some View {
        Toggle(isOn: $hasDispenser.animation(.easeInOut(duration: 0.2))) {
            Label {
                Text("Has Dedicated Dispenser").font(.subheadline)
            } icon: {
                Image(systemName: "cylinder").foregroundStyle(hasDispenser ? .brown : .secondary)
            }
        }
        .tint(.brown)
    }

    private var dispenserRatingField: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Dispenser Quality")
            HStack(spacing: 4) {
                StarRatingInput(rating: $dispenserRating)
                Spacer()
                Text(dispenserRating == 0 ? "Unrated" : "\(dispenserRating)/5")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Amenities & Fixtures

    private var heatedSeatField: some View {
        Toggle(isOn: $hasHeatedSeat) {
            Label {
                Text("Heated Seat").font(.subheadline)
            } icon: {
                Image(systemName: "thermometer.medium")
                    .foregroundStyle(hasHeatedSeat ? .orange : .secondary)
            }
        }
        .tint(.orange)
    }

    private var bidetField: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Bidet")
            Picker("Bidet", selection: $bidetType) {
                ForEach(BidetType.allCases, id: \.rawValue) { b in
                    Label(b.displayName, systemImage: b.icon).tag(b)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var changingTableField: some View {
        Toggle(isOn: $hasChangingTable) {
            Label {
                Text("Changing Table Available").font(.subheadline)
            } icon: {
                Image(systemName: "figure.and.child.holdinghands")
                    .foregroundStyle(hasChangingTable ? .green : .secondary)
            }
        }
        .tint(.green)
    }

    // MARK: - Hygiene & Wait Time

    private var soapField: some View {
        Toggle(isOn: $hasSoap) {
            Label {
                Text("Soap Available").font(.subheadline)
            } icon: {
                Image(systemName: "hands.sparkles")
                    .foregroundStyle(hasSoap ? .teal : .secondary)
            }
        }
        .tint(.teal)
    }

    private var dryingField: some View {
        Toggle(isOn: $hasDryingOption) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hand Drying Available").font(.subheadline)
                    Text("Paper towels or hand dryer")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "wind")
                    .foregroundStyle(hasDryingOption ? .teal : .secondary)
            }
        }
        .tint(.teal)
    }

    private var waitTimeField: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Typical Wait Time")
            Picker("Wait time", selection: $waitTime) {
                ForEach(WaitTime.allCases, id: \.rawValue) { w in
                    Label(w.displayName, systemImage: w.icon).tag(w)
                }
            }
            .pickerStyle(.menu)
        }
    }

    // MARK: - Photos

    private var photosField: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                fieldLabel("Photos")
                Spacer()
                Text("\(totalPhotoCount)/10").font(.caption).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    PhotosPicker(
                        selection: $photoPickerItems,
                        maxSelectionCount: max(0, 10 - totalPhotoCount),
                        matching: .images
                    ) {
                        photoActionButton(icon: "photo.on.rectangle.angled", label: "Library")
                    }
                    .disabled(totalPhotoCount >= 10)

                    Button { showCamera = true } label: {
                        photoActionButton(icon: "camera.fill", label: "Camera")
                    }
                    .disabled(totalPhotoCount >= 10)

                    ForEach(Array(existingFileNames.enumerated()), id: \.offset) { index, fileName in
                        existingPhotoThumbnail(fileName: fileName, index: index)
                    }
                    ForEach(Array(selectedPhotos.enumerated()), id: \.offset) { index, photo in
                        newPhotoThumbnail(image: photo, index: index)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Privacy

    private var privacyField: some View {
        Toggle(isOn: $isPrivate) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Private Entry").font(.subheadline)
                    Text(isPrivate
                         ? "Only you can see this bathroom"
                         : "Visible to everyone in the app")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: isPrivate ? "lock.fill" : "globe")
                    .foregroundStyle(isPrivate ? .red : .green)
            }
        }
        .tint(.red)
    }

    // MARK: - Notes

    private var notesField: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Notes")
            TextEditor(text: $notes)
                .frame(minHeight: 90, maxHeight: 160)
                .padding(8)
                .background(Color(.secondarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .font(.body)
        }
    }

    // MARK: - Photo Subviews

    private func photoActionButton(icon: String, label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 22)).foregroundStyle(.blue)
            Text(label).font(.caption2.weight(.medium)).foregroundStyle(.blue)
        }
        .frame(width: 72, height: 72)
        .background(Color(.secondarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func existingPhotoThumbnail(fileName: String, index: Int) -> some View {
        let image = editing.flatMap { ImageStorage.loadThumbnail(bathroomID: $0.id, fileName: fileName) }
        return Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Rectangle().fill(Color(.systemGray5))
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .topTrailing) {
            removeButton {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    existingFileNames = existingFileNames.enumerated()
                        .filter { $0.offset != index }.map { $0.element }
                }
            }
            .accessibilityLabel("Remove photo \(index + 1)")
        }
    }

    private func newPhotoThumbnail(image: UIImage, index: Int) -> some View {
        Image(uiImage: image).resizable().scaledToFill()
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .topTrailing) {
                removeButton {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedPhotos = selectedPhotos.enumerated()
                            .filter { $0.offset != index }.map { $0.element }
                    }
                }
                .accessibilityLabel("Remove new photo \(index + 1)")
            }
    }

    private func removeButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(.white)
                .background(Circle().fill(.black.opacity(0.5)).padding(3))
        }
        .offset(x: 6, y: -6)
    }

    // MARK: - Field Label Helper

    private func fieldLabel(_ title: String, required: Bool = false) -> some View {
        HStack(spacing: 2) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            if required { Text("*").font(.subheadline.weight(.semibold)).foregroundStyle(.red) }
        }
    }

    // MARK: - Photo Loading

    private func loadPickerItems(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            for item in items {
                guard totalPhotoCount < 10 else { break }
                if let data  = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    selectedPhotos.append(image)
                }
            }
            photoPickerItems = []
        }
    }

    // MARK: - Geocoding

    private func scheduleGeocode(for coordinate: CLLocationCoordinate2D) {
        geocodeTask?.cancel()
        geocodeTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            isGeocoding = true
            geocodedAddress = await reverseGeocode(coordinate) ?? geocodedAddress
            isGeocoding = false
        }
    }

    private func reverseGeocode(_ coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let request = MKReverseGeocodingRequest(location: location),
              let mapItem = try? await request.mapItems.first else { return nil }
        let p = mapItem.placemark
        return [p.subThoroughfare, p.thoroughfare, p.locality].compactMap { $0 }.joined(separator: " ")
    }

    // MARK: - Actions

    private func handleCancel() {
        if isDirty { showDiscardAlert = true } else { dismiss() }
    }

    private func save() async {
        isSaving = true
        geocodeTask?.cancel()

        let finalAddress         = await reverseGeocode(selectedCoordinate)
            ?? (isEditMode ? editing?.address : nil)
        let savedDispenserRating = hasDispenser ? max(1, dispenserRating) : 0

        if let bathroom = editing {
            // Edit mode — apply photo changes, then mutate all fields in place
            let removed = Set(bathroom.imageFileNames).subtracting(existingFileNames)
            removed.forEach { ImageStorage.deleteImage(bathroomID: bathroom.id, fileName: $0) }
            var newFiles: [String] = []
            for photo in selectedPhotos {
                if let f = ImageStorage.saveImage(photo, bathroomID: bathroom.id) { newFiles.append(f) }
            }
            applyFormState(to: bathroom,
                           address: finalAddress ?? bathroom.address,
                           savedDispenserRating: savedDispenserRating)
            bathroom.imageFileNames = existingFileNames + newFiles

            let removedArr  = Array(removed)
            let uploadPairs = zip(selectedPhotos, newFiles).map { ($0, $1) }
            let bid         = bathroom.id
            // Enqueue all cloud ops — retried automatically if offline
            if !removedArr.isEmpty {
                syncQueue.enqueue(.deletePhotos(bathroomID: bid, fileNames: removedArr))
            }
            for (_, fileName) in uploadPairs {
                syncQueue.enqueue(.uploadPhoto(bathroomID: bid, fileName: fileName))
            }
            syncQueue.enqueue(.upsertBathroom(bathroomID: bid))
            Task { await syncQueue.drain(supabase: supabaseService, context: modelContext) }

        } else {
            // Add mode — create, populate, then insert
            let bathroom = Bathroom(
                name:      name.trimmingCharacters(in: .whitespacesAndNewlines),
                latitude:  selectedCoordinate.latitude,
                longitude: selectedCoordinate.longitude
            )
            applyFormState(to: bathroom,
                           address: finalAddress,
                           savedDispenserRating: savedDispenserRating)
            var files: [String] = []
            for photo in selectedPhotos {
                if let f = ImageStorage.saveImage(photo, bathroomID: bathroom.id) { files.append(f) }
            }
            bathroom.imageFileNames = files
            modelContext.insert(bathroom)

            let bid = bathroom.id
            for fileName in files {
                syncQueue.enqueue(.uploadPhoto(bathroomID: bid, fileName: fileName))
            }
            syncQueue.enqueue(.upsertBathroom(bathroomID: bid))
            Task { await syncQueue.drain(supabase: supabaseService, context: modelContext) }
        }

        dismiss()
    }

    /// Writes all form-state values onto a Bathroom instance.
    /// Called by both add mode (after creating a new record) and edit mode
    /// (mutating an existing record) to eliminate the duplicate assignment block.
    private func applyFormState(to bathroom: Bathroom, address: String?, savedDispenserRating: Int) {
        bathroom.name                   = name.trimmingCharacters(in: .whitespacesAndNewlines)
        bathroom.latitude               = selectedCoordinate.latitude
        bathroom.longitude              = selectedCoordinate.longitude
        bathroom.address                = address
        bathroom.rating                 = rating
        bathroom.accessType             = accessType
        bathroom.requiresReceiptCode    = requiresReceiptCode
        bathroom.isOpen24Hours          = isOpen24Hours
        bathroom.stallType              = stallType
        bathroom.genderType             = genderType
        bathroom.isIndoor               = isIndoor
        bathroom.isWheelchairAccessible = isWheelchairAccessible
        bathroom.hasToiletPaper         = hasToiletPaper
        bathroom.hasExtraToiletPaper    = hasExtraToiletPaper
        bathroom.dispenserRating        = savedDispenserRating
        bathroom.hasHeatedSeat          = hasHeatedSeat
        bathroom.bidetType              = bidetType
        bathroom.hasChangingTable       = hasChangingTable
        bathroom.hasSoap                = hasSoap
        bathroom.hasDryingOption        = hasDryingOption
        bathroom.waitTime               = waitTime
        bathroom.notes                  = notes
        bathroom.dateVisited            = dateVisited
        bathroom.isPrivate              = isPrivate
        bathroom.dateModified           = Date()
    }
}

// MARK: - Previews

#Preview("Add mode") {
    AddBathroomView(userLocation: CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855))
        .modelContainer(for: Bathroom.self, inMemory: true)
        .environment(SupabaseService())
        .environment(SyncQueue())
}

#Preview("Edit mode") {
    let b = Bathroom(
        name: "Starbucks on Main", latitude: 40.7580, longitude: -73.9855,
        address: "123 Main St", rating: 4, accessType: .purchaseRequired,
        requiresReceiptCode: true, bidetType: .electronic, hasChangingTable: true
    )
    return AddBathroomView(userLocation: nil, editing: b)
        .modelContainer(for: Bathroom.self, inMemory: true)
        .environment(SupabaseService())
        .environment(SyncQueue())
}
