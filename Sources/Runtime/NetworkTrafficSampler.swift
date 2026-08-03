import Darwin
import Foundation

final class NetworkTrafficSampler {
    typealias SampleProvider = (Date) -> NetworkTrafficSample?

    private let appStartedAt: Date
    private let downloadSampleProvider: SampleProvider
    private let uploadSampleProvider: SampleProvider
    private var initialDownloadSample: NetworkTrafficSample?
    private var previousDownloadSample: NetworkTrafficSample?
    private var previousUploadSample: NetworkTrafficSample?

    init(
        appStartedAt: Date,
        downloadSampleProvider: @escaping SampleProvider = systemDownloadSample,
        uploadSampleProvider: @escaping SampleProvider = systemUploadSample
    ) {
        self.appStartedAt = appStartedAt
        self.downloadSampleProvider = downloadSampleProvider
        self.uploadSampleProvider = uploadSampleProvider
        initialDownloadSample = downloadSampleProvider(appStartedAt)
    }

    func currentDownloadSpeedBytesPerSecond(
        at timestamp: Date = Date()
    ) -> Int64? {
        guard let sample = downloadSampleProvider(timestamp) else {
            return nil
        }
        defer {
            previousDownloadSample = sample
        }
        return Self.speedBytesPerSecond(
            previous: previousDownloadSample,
            current: sample
        )
    }

    func downloadedSinceAppStartByteCount(
        at timestamp: Date = Date()
    ) -> Int64? {
        if initialDownloadSample == nil {
            initialDownloadSample = downloadSampleProvider(appStartedAt)
        }
        guard let initialDownloadSample,
              let current = downloadSampleProvider(timestamp),
              current.byteCount >= initialDownloadSample.byteCount else {
            return nil
        }
        return Int64(current.byteCount - initialDownloadSample.byteCount)
    }

    func currentUploadSpeedBytesPerSecond(
        at timestamp: Date = Date()
    ) -> Int64? {
        guard let sample = uploadSampleProvider(timestamp) else {
            return nil
        }
        defer {
            previousUploadSample = sample
        }
        return Self.speedBytesPerSecond(
            previous: previousUploadSample,
            current: sample
        )
    }

    static func speedBytesPerSecond(
        previous: NetworkTrafficSample?,
        current: NetworkTrafficSample
    ) -> Int64? {
        guard let previous else { return nil }
        let interval = current.timestamp.timeIntervalSince(previous.timestamp)
        guard interval > 0, current.byteCount >= previous.byteCount else {
            return nil
        }
        let delta = current.byteCount - previous.byteCount
        return Int64((Double(delta) / interval).rounded())
    }

    private static func systemDownloadSample(
        at timestamp: Date
    ) -> NetworkTrafficSample? {
        systemSample(at: timestamp, byteCount: { $0.ifi_ibytes })
    }

    private static func systemUploadSample(
        at timestamp: Date
    ) -> NetworkTrafficSample? {
        systemSample(at: timestamp, byteCount: { $0.ifi_obytes })
    }

    private static func systemSample(
        at timestamp: Date,
        byteCount: (if_data) -> UInt32
    ) -> NetworkTrafficSample? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0,
              let firstInterface = interfaces else {
            return nil
        }
        defer {
            freeifaddrs(interfaces)
        }

        var totalByteCount: UInt64 = 0
        var current: UnsafeMutablePointer<ifaddrs>? = firstInterface
        while let interface = current {
            defer {
                current = interface.pointee.ifa_next
            }

            let flags = Int32(interface.pointee.ifa_flags)
            guard (flags & IFF_UP) != 0,
                  (flags & IFF_LOOPBACK) == 0,
                  let address = interface.pointee.ifa_addr,
                  Int32(address.pointee.sa_family) == AF_LINK,
                  let data = interface.pointee.ifa_data else {
                continue
            }

            let interfaceData = data.assumingMemoryBound(to: if_data.self).pointee
            totalByteCount += UInt64(byteCount(interfaceData))
        }

        return NetworkTrafficSample(
            timestamp: timestamp,
            byteCount: totalByteCount
        )
    }
}
