import Foundation
import Testing
@testable import Wely

private final class FakeCheck: OwnerCheck {
    var answer = true
    var isAvailable = true
    private(set) var asked = 0
    var biometryName: String? { "Face ID" }

    func verify(reason: String) async -> Bool {
        asked += 1
        return answer
    }
}

struct AppLockTests {
    private let defaults = UserDefaults(suiteName: "AppLockTests-\(UUID().uuidString)")!

    private func lock(_ check: FakeCheck, at time: @escaping () -> Date = { Date(timeIntervalSince1970: 0) }) -> AppLock {
        AppLock(check: check, defaults: defaults, now: time)
    }

    @Test func startsUnlockedWhileOff() {
        let lock = lock(FakeCheck())
        #expect(!lock.isEnabled)
        #expect(!lock.isLocked)
    }

    @Test func enablingNeedsTheOwnerAndIsRemembered() async {
        let check = FakeCheck()
        check.answer = false
        let refused = lock(check)
        #expect(await refused.enable() == false)
        #expect(!refused.isEnabled)

        check.answer = true
        let accepted = lock(check)
        #expect(await accepted.enable())
        #expect(accepted.isEnabled)
        // A cold start with the lock on starts locked.
        #expect(lock(check).isLocked)
    }

    @Test func locksOnlyAfterAMinuteInTheBackground() async {
        let check = FakeCheck()
        var now = Date(timeIntervalSince1970: 0)
        let lock = lock(check, at: { now })
        await lock.enable()

        lock.didEnterBackground()
        #expect(lock.isHidden)
        #expect(lock.isCovering)
        now += 59
        lock.didBecomeActive()
        #expect(!lock.isLocked)
        #expect(!lock.isHidden)
        #expect(!lock.isCovering)

        lock.didEnterBackground()
        now += 60
        lock.didBecomeActive()
        #expect(lock.isLocked)
    }

    @Test func aSystemPromptDoesNotStartTheTimer() async {
        var now = Date(timeIntervalSince1970: 0)
        let lock = lock(FakeCheck(), at: { now })
        await lock.enable()
        lock.didResignActive()
        now += 600
        lock.didBecomeActive()
        #expect(!lock.isLocked)
    }

    @Test func unlockingNeedsTheOwner() async {
        let check = FakeCheck()
        await lock(check).enable()
        let locked = lock(check)
        check.answer = false
        await locked.unlock()
        #expect(locked.isLocked)
        check.answer = true
        await locked.unlock()
        #expect(!locked.isLocked)
    }

    @Test func disablingAndSigningOutUnlock() async {
        let check = FakeCheck()
        await lock(check).enable()
        let signedOut = lock(check)
        signedOut.reset()
        #expect(!signedOut.isLocked)
        #expect(signedOut.isEnabled)

        let disabled = lock(check)
        disabled.disable()
        #expect(!disabled.isLocked)
        #expect(!lock(check).isEnabled)
    }

    @Test func isOfferedOnceWhenThePhoneCanCheck() async {
        let check = FakeCheck()
        let lock = lock(check)
        #expect(lock.shouldOffer)
        lock.markOffered()
        #expect(!lock.shouldOffer)
    }

    @Test func isNotOfferedWhenOnOrUnavailable() async {
        let check = FakeCheck()
        check.isAvailable = false
        #expect(!lock(check).shouldOffer)
        check.isAvailable = true
        let enabled = lock(check)
        await enabled.enable()
        #expect(!enabled.shouldOffer)
    }
}
