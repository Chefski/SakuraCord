import Observation
import SwiftUI

/// The Settings page owns the native file sheet; popovers only request a file.
@Observable
@MainActor
final class ProfileImageImportRequest {
    var isPresented = false
    @ObservationIgnored private var completion: ((Result<URL, any Error>) -> Void)?

    func present(completion: @escaping (Result<URL, any Error>) -> Void) {
        guard !isPresented else { return }
        self.completion = completion
        isPresented = true
    }

    func complete(_ result: Result<[URL], any Error>) {
        let callback = completion
        completion = nil
        isPresented = false
        callback?(result.flatMap { urls in
            guard let url = urls.first else { return .failure(CancellationError()) }
            return .success(url)
        })
    }

    func cancel() {
        complete(.failure(CancellationError()))
    }
}

extension EnvironmentValues {
    @Entry var profileImageImportRequest: ProfileImageImportRequest?
}
