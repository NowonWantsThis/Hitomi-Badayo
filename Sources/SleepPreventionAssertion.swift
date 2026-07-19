import Foundation
import IOKit.pwr_mgt

final class SleepPreventionAssertion {
    private var assertionID = IOPMAssertionID(0)
    private(set) var isActive = false

    @discardableResult
    func acquire(reason: String = "Hitomi Native downloads in progress") -> Bool {
        guard !isActive else { return true }

        var newAssertionID = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoIdleSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &newAssertionID
        )
        guard result == kIOReturnSuccess else {
            return false
        }

        assertionID = newAssertionID
        isActive = true
        return true
    }

    func release() {
        guard isActive else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = IOPMAssertionID(0)
        isActive = false
    }

    deinit {
        release()
    }
}
