//
//  UnfinishedMoveBatchGateTests.swift
//  Project: Thaw
//
//  Copyright (Ice) © 2023–2025 Jordan Baird
//  Copyright (Thaw) © 2026 Toni Förster
//  Licensed under the GNU GPLv3

import Testing
@testable import Thaw

/// Characterizes the arm that withholds the live arrangement from the saved
/// order after a bulk apply gave up partway.
///
/// A batch that fails leaves the bar wherever it stopped. Recording that as
/// the user's layout replaces the order the batch was restoring, so the next
/// pass plans against the partial result and shifts things a little further
/// again (#900). The arm is cleared only by a clean apply or an explicit user
/// move; elapsed time cannot make a partial result authoritative.
@Suite("Unfinished move batch gate")
struct UnfinishedMoveBatchGateTests {
    private let clock = ContinuousClock()

    /// The ordinary case: every apply so far enacted what it planned, so
    /// nothing is withheld.
    @Test("No arm does not block the save")
    func noArmDoesNotBlock() {
        #expect(
            !MenuBarItemManager.unfinishedMoveBatchBlocksSave(
                observedAt: nil
            )
        )
    }

    /// The cache cycle immediately after a failed batch is the one that
    /// would persist the wreckage, so it has to be covered.
    @Test("A batch that just failed blocks the save")
    func freshArmBlocks() {
        let now = clock.now
        #expect(
            MenuBarItemManager.unfinishedMoveBatchBlocksSave(
                observedAt: now
            )
        )
    }

    /// A recent failure remains non-authoritative while its retry is pending.
    @Test("A recent unfinished batch blocks the save")
    func recentUnfinishedBatchBlocks() {
        let armedAt = clock.now
        #expect(
            MenuBarItemManager.unfinishedMoveBatchBlocksSave(
                observedAt: armedAt
            )
        )
    }

    /// A failed batch is not an order of record merely because time passed.
    /// The latch is cleared only by a clean apply or an explicit user move.
    @Test("An old unfinished batch still blocks the save")
    func oldUnfinishedBatchStillBlocks() {
        let armedAt = clock.now
        #expect(
            MenuBarItemManager.unfinishedMoveBatchBlocksSave(
                observedAt: armedAt
            )
        )
    }

    /// A direct Cmd-drag or a successful Layout editor drag is an explicit
    /// choice to make the current arrangement authoritative.
    @Test("An explicit user move clears the unfinished-batch latch")
    @MainActor
    func explicitUserMoveClearsLatch() {
        let manager = MenuBarItemManager()
        manager.recordBulkApplyOutcome(unenactedMoveCount: 1)
        #expect(manager.hasUnfinishedMoveBatch)

        manager.recordExternalMoveOperation()

        #expect(!manager.hasUnfinishedMoveBatch)
    }

    /// A preflight guard that returns before posting an event has burned no
    /// drag budget and hidden no cursor, so it is no evidence about whether
    /// this bar accepts synthetic drags — which is the only thing the circuit
    /// breaker measures. Counting guard refusals let a standing refusal
    /// escalate itself all the way to the hard cap, at which point applies
    /// with nothing to do with the guard were refused too.
    @Test("Deferred-only applies withhold the save without arming the breaker")
    @MainActor
    func deferredOnlyAppliesDoNotArmTheBreaker() {
        let manager = MenuBarItemManager()
        for _ in 0 ..< 10 {
            manager.recordBulkApplyOutcome(unenactedMoveCount: 2, deferredMoveCount: 2)
        }

        #expect(manager.hasUnfinishedMoveBatch)
        #expect(manager.isAutomaticBulkApplyPermitted(caller: #function, quietly: true))
    }

    /// The counterpart: moves that were actually attempted and failed are
    /// exactly what the breaker exists for, and still ration dispatch.
    @Test("Attempted failures still arm the breaker")
    @MainActor
    func attemptedFailuresArmTheBreaker() {
        let manager = MenuBarItemManager()
        manager.recordBulkApplyOutcome(unenactedMoveCount: 1)
        manager.recordBulkApplyOutcome(unenactedMoveCount: 1)

        #expect(!manager.isAutomaticBulkApplyPermitted(caller: #function, quietly: true))
    }

    /// A batch may both defer and fail. Only the failures count.
    @Test("A mixed apply arms the breaker once for its attempted failures")
    @MainActor
    func mixedApplyCountsOnlyAttemptedFailures() {
        let manager = MenuBarItemManager()
        manager.recordBulkApplyOutcome(unenactedMoveCount: 5, deferredMoveCount: 4)
        manager.recordBulkApplyOutcome(unenactedMoveCount: 5, deferredMoveCount: 4)

        #expect(!manager.isAutomaticBulkApplyPermitted(caller: #function, quietly: true))
    }

    /// Every reading the streak was built from describes a geometry that a
    /// display arriving or leaving has since replaced. A flapping external
    /// display would otherwise ratchet the breaker to its cap without any one
    /// arrangement having been given a fair attempt.
    @Test("A display change clears the breaker but not the save withhold")
    @MainActor
    func displayChangeClearsTheBreaker() {
        let manager = MenuBarItemManager()
        manager.recordBulkApplyOutcome(unenactedMoveCount: 1)
        manager.recordBulkApplyOutcome(unenactedMoveCount: 1)
        #expect(!manager.isAutomaticBulkApplyPermitted(caller: #function, quietly: true))

        manager.resetBulkApplyCircuitBreakerForDisplayChange()

        #expect(manager.isAutomaticBulkApplyPermitted(caller: #function, quietly: true))
    }
}
