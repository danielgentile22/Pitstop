//
//  CameraPickerView.swift
//  Pitstop
//
//  UIImagePickerController wrapped as a SwiftUI view for camera capture.
//  As of iOS 18, there is no pure SwiftUI camera API — UIKit bridging is required.
//
//  Usage:
//    .sheet(isPresented: $showCamera) {
//        CameraPickerView(onCapture: { image in
//            selectedPhotos.append(image)
//        })
//        .ignoresSafeArea()
//    }
//

import SwiftUI
import UIKit

/// A SwiftUI wrapper around `UIImagePickerController` for camera capture.
///
/// - Calls `onCapture` with the taken photo if the user confirms.
/// - Calls `onCapture` with `nil` if the user cancels (so callers can dismiss).
/// - The parent is responsible for dismissing the sheet.
struct CameraPickerView: UIViewControllerRepresentable {

    // MARK: - Input

    /// Called when the user finishes (photo taken) or cancels (nil).
    var onCapture: (UIImage?) -> Void

    // MARK: - UIViewControllerRepresentable

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        // No updates needed — the picker is fully managed by the coordinator.
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {

        private let onCapture: (UIImage?) -> Void

        init(onCapture: @escaping (UIImage?) -> Void) {
            self.onCapture = onCapture
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = info[.originalImage] as? UIImage
            onCapture(image)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCapture(nil)
        }
    }
}
