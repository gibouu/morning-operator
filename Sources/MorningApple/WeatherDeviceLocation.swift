import MorningCore
import Foundation
import CoreLocation

public enum WeatherLocationAuthorization: Sendable, Equatable {
    case notDetermined, authorized, denied, unavailable
}

public enum WeatherDeviceLocationError: Error, LocalizedError, Sendable, Equatable {
    case denied, unavailable, timedOut, invalidReading
    public var errorDescription: String? {
        switch self {
        case .denied: AppLanguage.localized("Location is off. Allow it in iPhone Settings or choose a city for the weather.", bundle: .module)
        case .unavailable, .invalidReading: AppLanguage.localized("Your location isn't available yet. Try again or choose a city.", bundle: .module)
        case .timedOut: AppLanguage.localized("Finding your location took too long. Try again or choose a city.", bundle: .module)
        }
    }
}

@MainActor
public protocol WeatherDeviceLocationProviding: AnyObject {
    var authorization: WeatherLocationAuthorization { get }
    /// Explicit action only, after the app has explained the use of location.
    func requestAuthorization() async throws -> Bool
    /// A single foreground fix. Never asks for permission or starts continuous tracking.
    func currentLocation() async throws -> WeatherLocation
    func cancel()
}

/// Owns every delegate continuation and timeout. Coordinates stay in memory; a
/// cancelled, denied or late callback can never complete a subsequent request.
@MainActor
public final class WeatherDeviceLocation: NSObject, WeatherDeviceLocationProviding, @preconcurrency CLLocationManagerDelegate {
    private lazy var manager: CLLocationManager = {
        let manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        return manager
    }()
    private let clock: any Clock<Duration>
    private let timeout: Duration
    private var authorizationContinuation: CheckedContinuation<Bool, any Error>?
    private var locationContinuation: CheckedContinuation<WeatherLocation, any Error>?
    private var timer: Task<Void, Never>?
    private var attempt: UUID?

    public init(timeout: Duration = .seconds(8), clock: any Clock<Duration> = ContinuousClock()) {
        self.timeout = min(max(timeout, .milliseconds(1)), .seconds(10))
        self.clock = clock
        super.init()
    }

    public var authorization: WeatherLocationAuthorization {
        guard Bundle.main.object(forInfoDictionaryKey: "NSLocationWhenInUseUsageDescription") is String else { return .unavailable }
        return switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: .authorized
        case .denied, .restricted: .denied
        case .notDetermined: .notDetermined
        @unknown default: .unavailable
        }
    }

    public func requestAuthorization() async throws -> Bool {
        try Task.checkCancellation()
        if authorization != .notDetermined { return authorization == .authorized }
        guard Bundle.main.object(forInfoDictionaryKey: "NSLocationWhenInUseUsageDescription") is String,
              attempt == nil else { throw WeatherDeviceLocationError.unavailable }
        let id = UUID(); attempt = id
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                authorizationContinuation = continuation
                startTimer(id: id, duration: .seconds(45))
                manager.requestWhenInUseAuthorization()
            }
        } onCancel: { Task { @MainActor [weak self] in self?.fail(CancellationError(), id: id) } }
    }

    public func currentLocation() async throws -> WeatherLocation {
        try Task.checkCancellation()
        guard authorization == .authorized else {
            throw authorization == .denied ? WeatherDeviceLocationError.denied : .unavailable
        }
        guard attempt == nil else { throw WeatherDeviceLocationError.unavailable }
        // Each fix has a fresh delegate source. An already queued callback from a
        // cancelled manager cannot be mistaken for a newer request's result.
        manager.delegate = nil; manager.stopUpdatingLocation()
        manager = CLLocationManager(); manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        let id = UUID(); attempt = id
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                locationContinuation = continuation
                startTimer(id: id, duration: timeout)
                manager.requestLocation()
            }
        } onCancel: { Task { @MainActor [weak self] in self?.fail(CancellationError(), id: id) } }
    }

    public func cancel() {
        guard let attempt else { return }
        fail(CancellationError(), id: attempt)
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager === self.manager, let id = attempt else { return }
        if let continuation = authorizationContinuation, authorization != .notDetermined {
            authorizationContinuation = nil; finish(id: id)
            continuation.resume(returning: authorization == .authorized)
        } else if locationContinuation != nil, authorization != .authorized {
            fail(WeatherDeviceLocationError.denied, id: id)
        }
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard manager === self.manager, let id = attempt, let continuation = locationContinuation, authorization == .authorized else { return }
        guard let reading = locations.last,
              let location = try? Self.validated(reading, at: Date(),
                  reducedAccuracy: manager.accuracyAuthorization == .reducedAccuracy) else { return }
        locationContinuation = nil; finish(id: id)
        continuation.resume(returning: location)
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        guard manager === self.manager, let id = attempt, locationContinuation != nil else { return }
        // A temporary unknown fix can recover before the bounded deadline.
        if (error as? CLError)?.code == .locationUnknown { return }
        fail((error as? CLError)?.code == .denied ? WeatherDeviceLocationError.denied : .unavailable, id: id)
    }

    static func validated(_ reading: CLLocation, at now: Date, reducedAccuracy: Bool = false) throws -> WeatherLocation {
        let age = now.timeIntervalSince(reading.timestamp)
        // The Core Location SDK permits reduced-accuracy fixes up to 20 minutes old.
        let maximumAge = reducedAccuracy ? 1_200.0 : 300.0
        let maximumUncertainty = reducedAccuracy ? 20_000.0 : 5_000.0
        guard reading.horizontalAccuracy.isFinite, (0...maximumUncertainty).contains(reading.horizontalAccuracy),
              age.isFinite, (-60...maximumAge).contains(age) else { throw WeatherDeviceLocationError.invalidReading }
        return try WeatherLocation(latitude: reading.coordinate.latitude, longitude: reading.coordinate.longitude,
            displayName: AppLanguage.localized("Current location", bundle: .module))
    }

    private func startTimer(id: UUID, duration: Duration) {
        timer = Task { @MainActor [weak self, clock] in
            do { try await clock.sleep(for: duration) } catch { return }
            self?.fail(WeatherDeviceLocationError.timedOut, id: id)
        }
    }
    private func finish(id: UUID) {
        guard attempt == id else { return }
        attempt = nil; timer?.cancel(); timer = nil
        manager.stopUpdatingLocation()
    }
    private func fail(_ error: any Error, id: UUID) {
        guard attempt == id else { return }
        let authorization = authorizationContinuation, location = locationContinuation
        authorizationContinuation = nil; locationContinuation = nil; finish(id: id)
        authorization?.resume(throwing: error); location?.resume(throwing: error)
    }
}
