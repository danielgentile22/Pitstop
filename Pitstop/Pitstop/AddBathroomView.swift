import CoreLocation
import MapKit
import PhotosUI
import SwiftData
import SwiftUI

/// Full-screen form for adding a bathroom, or editing one when `editing` is non-nil.
/// Adding from a `candidate` prefills its name, location, address, and hours, and links the new Bathroom to it.
struct AddBathroomView: View {

    // MARK: - Environment

    @Environment(\.dismiss)            private var dismiss
    @Environment(\.modelContext)       private var modelContext

    // MARK: - Input

    /// Add mode only: the pin starts at, or follows the first fix from, this manager.
    let locationManager: LocationManager?
    let editing: Bathroom?
    let candidate: Candidate?

    // MARK: - Fields

    /// Every field, pin included. `initialForm` is the snapshot taken when the form opened.
    @State private var form: BathroomForm
    private let initialForm: BathroomForm

    // MARK: - Location

    @State private var geocodedAddress = ""
    @State private var addressQuery = ""
    @State private var mapJump: MiniMapPicker.JumpTarget?
    @State private var searchProblem: SearchProblem?
    @State private var isGeocoding     = false
    @State private var geocodeTask: Task<Void, Never>?
    @State private var searchTask: Task<Void, Never>?
    /// Where the pin was last placed for the user. While it has not been dragged away from here,
    /// a new bathroom's pin moves to the first location fix.
    @State private var placedCoordinate: CLLocationCoordinate2D
    @State private var pinFollowsLocation: Bool

    private enum SearchProblem { case noMatch, needsConnection }

    /// Washington DC, the center of the area the seed covers, for a new pin with no location yet.
    static let defaultCoordinate = CLLocationCoordinate2D(latitude: 38.8895, longitude: -77.0353)

    // MARK: - Photos

    @State private var existingFileNames: [String]  = []
    @State private var selectedPhotos: [UIImage]    = []
    @State private var photoPickerItems: [PhotosPickerItem] = []

    // MARK: - UI State

    @State private var showDiscardAlert = false
    @State private var saveError: BathroomSaver.SaveError?
    @State private var showCamera       = false
    @State private var showCameraBlockedAlert = false
    @State private var isSaving         = false
    @FocusState private var nameFocused: Bool

    // MARK: - Computed

    private var isEditMode: Bool     { editing != nil }
    private var totalPhotoCount: Int { existingFileNames.count + selectedPhotos.count }
    private var canSave: Bool        { !form.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving }

    private var isDirty: Bool {
        form.hasChanges(from: initialForm)
            || existingFileNames != (editing?.imageFileNames ?? [])
            || !selectedPhotos.isEmpty
    }

    // MARK: - Init

    init(locationManager: LocationManager? = nil, editing: Bathroom? = nil, candidate: Candidate? = nil) {
        self.locationManager = editing == nil && candidate == nil ? locationManager : nil
        self.editing      = editing
        self.candidate    = editing == nil ? candidate : nil

        let form: BathroomForm
        if let b = editing {
            form                = BathroomForm(bathroom: b)
            _existingFileNames  = State(initialValue: b.imageFileNames)
            _geocodedAddress    = State(initialValue: b.address ?? "")
        } else if let c = self.candidate {
            form                = BathroomForm(candidate: c)
            _geocodedAddress    = State(initialValue: c.address ?? "")
        } else {
            form = BathroomForm(coordinate: locationManager?.userLocation ?? Self.defaultCoordinate)
        }
        _form       = State(initialValue: form)
        initialForm = form
        _placedCoordinate   = State(initialValue: form.coordinate)
        _pinFollowsLocation = State(initialValue: self.locationManager != nil && self.locationManager?.userLocation == nil)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    MiniMapPicker(selectedCoordinate: $form.coordinate, jumpTo: $mapJump)
                        .frame(height: 220)
                        .onChange(of: form.coordinate.latitude)  { pinChanged() }
                        .onChange(of: form.coordinate.longitude) { pinChanged() }
                        .onChange(of: locationManager?.userLocation?.latitude)  { followFirstFix() }
                        .onChange(of: locationManager?.userLocation?.longitude) { followFirstFix() }

                    addressRow
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground))

                    VStack(alignment: .leading, spacing: 0) {

                        formSection("Essentials") {
                            nameField
                            dateField
                        }

                        formDivider

                        formSection("Overall Rating") {
                            StarRatingInput(rating: $form.rating)
                        }

                        formDivider

                        formSection("Access & Hours") {
                            accessField
                            if form.accessType == .purchaseRequired {
                                receiptCodeField
                            }
                            open24HoursField
                        }

                        formDivider

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
                                    if form.hasToiletPaper {
                                        extraTpField
                                    }
                                    dispenserToggleField
                                    if form.hasDispenser {
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
                        .disabled(isSaving)
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
            .alert("Camera Access Is Off", isPresented: $showCameraBlockedAlert) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("To take photos, allow camera access for Pitstop in Settings.")
            }
            .alert("Couldn't Save", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError?.errorDescription ?? "")
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
            if !isEditMode { scheduleGeocode(for: form.coordinate) }
        }
        .onDisappear {
            geocodeTask?.cancel()
            searchTask?.cancel()
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.caption).foregroundStyle(.blue)
                TextField("Type an address to move the pin", text: $addressQuery)
                    .font(.subheadline)
                    .textContentType(.fullStreetAddress)
                    .submitLabel(.search)
                    .onSubmit { searchAddress() }
                    .onChange(of: addressQuery) { searchProblem = nil }
            }
            HStack(spacing: 8) {
                Image(systemName: "location.fill").font(.caption).foregroundStyle(.blue)
                if searchProblem == .noMatch {
                    Text("No match for that address").font(.caption).foregroundStyle(.red)
                } else if searchProblem == .needsConnection {
                    Text("Address search needs a connection").font(.caption).foregroundStyle(.red)
                } else if isGeocoding {
                    Text("Locating…").font(.caption).foregroundStyle(.secondary)
                } else if geocodedAddress.isEmpty {
                    Text("Address unavailable").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(geocodedAddress).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Essentials

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Name", required: true)
            TextField("e.g. Starbucks on Main", text: $form.name)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .submitLabel(.done)
                .onSubmit { nameFocused = false }
        }
    }

    private var dateField: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Date Visited")
            DatePicker("", selection: $form.dateVisited, in: ...Date(), displayedComponents: .date)
                .labelsHidden()
        }
    }

    // MARK: - Access & Hours

    private var accessField: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("How do you get in?")
            Picker("Access", selection: $form.accessType) {
                ForEach(BathroomAccess.allCases) { access in
                    Label(access.displayName, systemImage: access.icon).tag(access)
                }
            }
            .pickerStyle(.menu)
            .tint(form.accessType.color)
        }
    }

    private var receiptCodeField: some View {
        Toggle(isOn: $form.requiresReceiptCode) {
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
        Toggle(isOn: $form.isOpen24Hours) {
            Label {
                Text("Open 24 Hours").font(.subheadline)
            } icon: {
                Image(systemName: "clock").foregroundStyle(form.isOpen24Hours ? .blue : .secondary)
            }
        }
        .tint(.blue)
    }

    // MARK: - Layout

    private var stallTypeField: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Stall Type")
            Picker("Stall type", selection: $form.stallType) {
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
            Picker("Gender", selection: $form.genderType) {
                ForEach(GenderType.allCases, id: \.rawValue) { g in
                    Label(g.displayName, systemImage: g.icon).tag(g)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var indoorField: some View {
        Toggle(isOn: $form.isIndoor) {
            Label {
                Text(form.isIndoor ? "Indoor" : "Outdoor").font(.subheadline)
            } icon: {
                Image(systemName: form.isIndoor ? "building.2" : "tree")
                    .foregroundStyle(form.isIndoor ? .blue : .green)
            }
        }
        .tint(.blue)
    }

    private var wheelchairField: some View {
        Toggle(isOn: $form.isWheelchairAccessible) {
            Label {
                Text("Wheelchair Accessible").font(.subheadline)
            } icon: {
                Image(systemName: "figure.roll")
                    .foregroundStyle(form.isWheelchairAccessible ? .blue : .secondary)
            }
        }
        .tint(.blue)
    }

    // MARK: - Toilet Paper

    private var toiletPaperField: some View {
        Toggle(isOn: $form.hasToiletPaper.animation(.easeInOut(duration: 0.2))) {
            Label {
                Text("Toilet Paper Available").font(.subheadline)
            } icon: {
                Image(systemName: "roll").foregroundStyle(form.hasToiletPaper ? .brown : .secondary)
            }
        }
        .tint(.brown)
    }

    private var extraTpField: some View {
        Toggle(isOn: $form.hasExtraToiletPaper) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Extra Rolls Available").font(.subheadline)
                    Text("Backup rolls are stocked, not just one roll")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "plus.circle").foregroundStyle(form.hasExtraToiletPaper ? .brown : .secondary)
            }
        }
        .tint(.brown)
    }

    private var dispenserToggleField: some View {
        Toggle(isOn: $form.hasDispenser.animation(.easeInOut(duration: 0.2))) {
            Label {
                Text("Has Dedicated Dispenser").font(.subheadline)
            } icon: {
                Image(systemName: "cylinder").foregroundStyle(form.hasDispenser ? .brown : .secondary)
            }
        }
        .tint(.brown)
    }

    private var dispenserRatingField: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Dispenser Quality")
            HStack(spacing: 4) {
                StarRatingInput(rating: $form.dispenserRating)
                Spacer()
                Text(form.dispenserRating == 0 ? "Unrated" : "\(form.dispenserRating)/5")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Amenities & Fixtures

    private var heatedSeatField: some View {
        Toggle(isOn: $form.hasHeatedSeat) {
            Label {
                Text("Heated Seat").font(.subheadline)
            } icon: {
                Image(systemName: "thermometer.medium")
                    .foregroundStyle(form.hasHeatedSeat ? .orange : .secondary)
            }
        }
        .tint(.orange)
    }

    private var bidetField: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Bidet")
            Picker("Bidet", selection: $form.bidetType) {
                ForEach(BidetType.allCases, id: \.rawValue) { b in
                    Label(b.displayName, systemImage: b.icon).tag(b)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var changingTableField: some View {
        Toggle(isOn: $form.hasChangingTable) {
            Label {
                Text("Changing Table Available").font(.subheadline)
            } icon: {
                Image(systemName: "figure.and.child.holdinghands")
                    .foregroundStyle(form.hasChangingTable ? .green : .secondary)
            }
        }
        .tint(.green)
    }

    // MARK: - Hygiene & Wait Time

    private var soapField: some View {
        Toggle(isOn: $form.hasSoap) {
            Label {
                Text("Soap Available").font(.subheadline)
            } icon: {
                Image(systemName: "hands.sparkles")
                    .foregroundStyle(form.hasSoap ? .teal : .secondary)
            }
        }
        .tint(.teal)
    }

    private var dryingField: some View {
        Toggle(isOn: $form.hasDryingOption) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hand Drying Available").font(.subheadline)
                    Text("Paper towels or hand dryer")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "wind")
                    .foregroundStyle(form.hasDryingOption ? .teal : .secondary)
            }
        }
        .tint(.teal)
    }

    private var waitTimeField: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Typical Wait Time")
            Picker("Wait time", selection: $form.waitTime) {
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

                    if CameraAccess.isAvailable {
                        Button { Task { await openCamera() } } label: {
                            photoActionButton(icon: "camera.fill", label: "Camera")
                        }
                        .disabled(totalPhotoCount >= 10)
                    }

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

    private func openCamera() async {
        switch await CameraAccess.request() {
        case .granted: showCamera = true
        case .blocked: showCameraBlockedAlert = true
        }
    }

    // MARK: - Notes

    private var notesField: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel("Notes")
            TextEditor(text: $form.notes)
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

    private func pinChanged() {
        if form.pinMoved(from: placedCoordinate) { pinFollowsLocation = false }
        scheduleGeocode(for: form.coordinate)
    }

    /// Moves a new bathroom's untouched pin to the first fix that arrives after the form opened.
    private func followFirstFix() {
        guard pinFollowsLocation, let location = locationManager?.userLocation else { return }
        pinFollowsLocation = false
        placePin(at: location)
    }

    private func placePin(at coordinate: CLLocationCoordinate2D) {
        placedCoordinate = coordinate
        form.coordinate  = coordinate
        mapJump = .init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    private func scheduleGeocode(for coordinate: CLLocationCoordinate2D) {
        geocodeTask?.cancel()
        if let kept = keptAddress(at: coordinate) {
            geocodedAddress = kept
            isGeocoding = false
            return
        }
        geocodeTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            isGeocoding = true
            let address = await reverseGeocode(coordinate)
            // A newer pin position owns the address row now.
            guard !Task.isCancelled else { return }
            geocodedAddress = address ?? geocodedAddress
            isGeocoding = false
        }
    }

    /// Only the latest search may move the pin: starting one cancels the one before it.
    private func searchAddress() {
        searchTask?.cancel()
        searchProblem = nil
        let query = addressQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(center: form.coordinate, latitudinalMeters: 50_000, longitudinalMeters: 50_000)
        searchTask = Task {
            let item: MKMapItem?
            do {
                item = try await MKLocalSearch(request: request).start().mapItems.first
            } catch let error as MKError where error.code == .placemarkNotFound {
                item = nil
            } catch {
                guard !Task.isCancelled else { return }
                searchProblem = .needsConnection
                return
            }
            guard !Task.isCancelled else { return }
            guard let item else {
                searchProblem = .noMatch
                return
            }
            pinFollowsLocation = false
            placePin(at: item.location.coordinate)
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }

    private func reverseGeocode(_ coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let request = MKReverseGeocodingRequest(location: location),
              let mapItem = try? await request.mapItems.first else { return nil }
        guard let short = mapItem.address?.shortAddress else { return nil }
        let line = short.split(whereSeparator: \.isNewline).joined(separator: ", ")
        return line.isEmpty ? nil : line
    }

    /// The stored address of the Bathroom or Candidate while the pin still sits on it, which beats a reverse geocode.
    private func keptAddress(at coordinate: CLLocationCoordinate2D) -> String? {
        let address = editing?.address ?? candidate?.address
        guard let address, !address.isEmpty else { return nil }
        var pin = initialForm
        pin.coordinate = coordinate
        return pin.pinMoved(from: initialForm.coordinate) ? nil : address
    }

    // MARK: - Actions

    private func handleCancel() {
        if isDirty { showDiscardAlert = true } else { dismiss() }
    }

    private func save() async {
        isSaving = true
        geocodeTask?.cancel()
        searchTask?.cancel()

        let target: BathroomSaver.Target = editing.map { .edit($0) } ?? .new(from: candidate)
        let saver = BathroomSaver(context: modelContext, geocode: reverseGeocode)
        do {
            try await saver.save(
                form,
                to: target,
                photos: .init(kept: existingFileNames, added: selectedPhotos),
                fallbackAddress: geocodedAddress.isEmpty ? nil : geocodedAddress
            )
            dismiss()
        } catch {
            saveError = error as? BathroomSaver.SaveError ?? .commitFailed
            isSaving = false
        }
    }
}

// MARK: - Previews

#Preview("Add mode") {
    AddBathroomView(locationManager: LocationManager())
        .modelContainer(for: Bathroom.self, inMemory: true)
}

#Preview("Edit mode") {
    let b = Bathroom(
        name: "Starbucks on Main", latitude: 40.7580, longitude: -73.9855,
        address: "123 Main St", rating: 4, accessType: .purchaseRequired,
        requiresReceiptCode: true, bidetType: .electronic, hasChangingTable: true
    )
    return AddBathroomView(editing: b)
        .modelContainer(for: Bathroom.self, inMemory: true)
}
