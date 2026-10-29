import CountdownManagerUI
import Foundation

@MainActor
func testWhatsNewHistory() {
    let firstSuite = "CountdownWhatsNew.First.\(UUID().uuidString)"
    let secondSuite = "CountdownWhatsNew.Second.\(UUID().uuidString)"
    let firstDefaults = UserDefaults(suiteName: firstSuite)!
    let secondDefaults = UserDefaults(suiteName: secondSuite)!
    defer {
        firstDefaults.removePersistentDomain(forName: firstSuite)
        secondDefaults.removePersistentDomain(forName: secondSuite)
    }

    firstDefaults.set("preserve unrelated preference", forKey: "fixture.unrelated")
    let beforePresentation = firstDefaults.persistentDomain(forName: firstSuite) ?? [:]
    let currentRelease = "fixture-release-1"
    let nextRelease = "fixture-release-2"

    // Creating/reading an owner does not consume the unseen release. Discarding an owner
    // without presenting a window also leaves it unseen; UI admission itself is not tested here.
    do {
        let unpresented = WhatsNewHistory(defaults: firstDefaults, releaseID: currentRelease)
        for _ in 0..<3 { precondition(unpresented.hasUnseenRelease) }
        precondition(NSDictionary(dictionary: beforePresentation).isEqual(
            to: firstDefaults.persistentDomain(forName: firstSuite) ?? [:]))
    }
    let first = WhatsNewHistory(defaults: firstDefaults, releaseID: currentRelease)
    precondition(first.hasUnseenRelease)
    first.markPresented()
    precondition(!first.hasUnseenRelease)
    precondition(firstDefaults.string(forKey: "fixture.unrelated") == "preserve unrelated preference")

    let afterPresentation = firstDefaults.persistentDomain(forName: firstSuite) ?? [:]
    first.markPresented()
    precondition(NSDictionary(dictionary: afterPresentation).isEqual(
        to: firstDefaults.persistentDomain(forName: firstSuite) ?? [:]))
    let reopenedDefaults = UserDefaults(suiteName: firstSuite)!
    let reopened = WhatsNewHistory(defaults: reopenedDefaults, releaseID: currentRelease)
    precondition(!reopened.hasUnseenRelease)

    // Reading a different release does not mark it or erase the current release's last-seen state.
    let next = WhatsNewHistory(defaults: firstDefaults, releaseID: nextRelease)
    precondition(next.hasUnseenRelease && !reopened.hasUnseenRelease)
    precondition(NSDictionary(dictionary: afterPresentation).isEqual(
        to: firstDefaults.persistentDomain(forName: firstSuite) ?? [:]))
    next.markPresented()
    precondition(!next.hasUnseenRelease)
    precondition(!WhatsNewHistory(defaults: reopenedDefaults, releaseID: nextRelease).hasUnseenRelease)

    // A separate preview/test profile has its own history; neither suite changes the other.
    let isolatedBefore = secondDefaults.persistentDomain(forName: secondSuite) ?? [:]
    let isolated = WhatsNewHistory(defaults: secondDefaults, releaseID: nextRelease)
    precondition(isolated.hasUnseenRelease)
    precondition(NSDictionary(dictionary: isolatedBefore).isEqual(
        to: secondDefaults.persistentDomain(forName: secondSuite) ?? [:]))
    isolated.markPresented()
    precondition(!isolated.hasUnseenRelease && !next.hasUnseenRelease)
    precondition(WhatsNewHistory(defaults: secondDefaults, releaseID: currentRelease).hasUnseenRelease)
    precondition(firstDefaults.string(forKey: "fixture.unrelated") == "preserve unrelated preference")

    print("PASS WhatsNewHistory: unseen reads/unpresented owner, explicit/idempotent mark, reopened owner, new release and isolated defaults; UI admission is separate evidence")
}
