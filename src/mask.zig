const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;

pub const SignalSet = struct {
    inner: posix.sigset_t,

    pub fn initEmpty() SignalSet {
        return .{ .inner = linux.sigemptyset() };
    }

    pub fn initFull() SignalSet {
        return .{ .inner = linux.sigfillset() };
    }

    pub fn add(self: *SignalSet, sig: i32) void {
        linux.sigaddset(&self.inner, @intCast(sig));
    }

    pub fn remove(self: *SignalSet, sig: i32) void {
        linux.sigdelset(&self.inner, @intCast(sig));
    }

    pub fn contains(self: *const SignalSet, sig: i32) bool {
        return linux.sigismember(&self.inner, @intCast(sig));
    }
};

pub fn blockSignals(set: SignalSet) !SignalSet {
    var old_set: posix.sigset_t = undefined;
    const rc = linux.sigprocmask(linux.SIG.BLOCK, &set.inner, &old_set);
    if (rc != 0) {
        return error.SignalMaskFailed;
    }
    return .{ .inner = old_set };
}

pub fn unblockSignals(set: SignalSet) !SignalSet {
    var old_set: posix.sigset_t = undefined;
    const rc = linux.sigprocmask(linux.SIG.UNBLOCK, &set.inner, &old_set);
    if (rc != 0) {
        return error.SignalMaskFailed;
    }
    return .{ .inner = old_set };
}

pub fn setSignalMask(set: SignalSet) !SignalSet {
    var old_set: posix.sigset_t = undefined;
    const rc = linux.sigprocmask(linux.SIG.SETMASK, &set.inner, &old_set);
    if (rc != 0) {
        return error.SignalMaskFailed;
    }
    return .{ .inner = old_set };
}

pub fn getSignalMask() !SignalSet {
    var set: posix.sigset_t = undefined;
    const rc = linux.sigprocmask(linux.SIG.SETMASK, null, &set);
    if (rc != 0) {
        return error.SignalMaskFailed;
    }
    return .{ .inner = set };
}

test "SignalSet - empty and full" {
    const testing = std.testing;

    var empty = SignalSet.initEmpty();
    try testing.expect(!empty.contains(posix.SIG.TERM));
    try testing.expect(!empty.contains(posix.SIG.HUP));

    var full = SignalSet.initFull();
    try testing.expect(full.contains(posix.SIG.TERM));
    try testing.expect(full.contains(posix.SIG.HUP));
}

test "SignalSet - add and remove" {
    const testing = std.testing;

    var set = SignalSet.initEmpty();
    try testing.expect(!set.contains(posix.SIG.TERM));

    set.add(posix.SIG.TERM);
    try testing.expect(set.contains(posix.SIG.TERM));
    try testing.expect(!set.contains(posix.SIG.HUP));

    set.add(posix.SIG.HUP);
    try testing.expect(set.contains(posix.SIG.TERM));
    try testing.expect(set.contains(posix.SIG.HUP));

    set.remove(posix.SIG.TERM);
    try testing.expect(!set.contains(posix.SIG.TERM));
    try testing.expect(set.contains(posix.SIG.HUP));
}

test "signal masking - block and unblock" {
    const testing = std.testing;

    // Save the current mask at start
    const initial_mask = try getSignalMask();

    var set = SignalSet.initEmpty();
    set.add(posix.SIG.USR1);

    const old_mask = try blockSignals(set);

    const current = try getSignalMask();
    try testing.expect(current.contains(posix.SIG.USR1));

    _ = try unblockSignals(set);

    const restored = try getSignalMask();
    try testing.expect(restored.contains(posix.SIG.USR1) == old_mask.contains(posix.SIG.USR1));

    // Restore initial mask
    _ = try setSignalMask(initial_mask);
}

test "SignalSet - multiple signals" {
    const testing = std.testing;

    var set = SignalSet.initEmpty();

    // Add 5 different signals
    set.add(posix.SIG.HUP);
    set.add(posix.SIG.INT);
    set.add(posix.SIG.USR1);
    set.add(posix.SIG.USR2);
    set.add(posix.SIG.TERM);

    // Verify all are contained
    try testing.expect(set.contains(posix.SIG.HUP));
    try testing.expect(set.contains(posix.SIG.INT));
    try testing.expect(set.contains(posix.SIG.USR1));
    try testing.expect(set.contains(posix.SIG.USR2));
    try testing.expect(set.contains(posix.SIG.TERM));

    // Verify others are not
    try testing.expect(!set.contains(posix.SIG.QUIT));
    try testing.expect(!set.contains(posix.SIG.CHLD));

    // Remove one and verify
    set.remove(posix.SIG.INT);
    try testing.expect(!set.contains(posix.SIG.INT));
    try testing.expect(set.contains(posix.SIG.HUP)); // Others still there
}

test "SignalSet - remove operations" {
    const testing = std.testing;

    var set = SignalSet.initEmpty();

    // Add some signals
    set.add(posix.SIG.INT);
    set.add(posix.SIG.QUIT);
    set.add(posix.SIG.PIPE);

    try testing.expect(set.contains(posix.SIG.INT));
    try testing.expect(set.contains(posix.SIG.QUIT));
    try testing.expect(set.contains(posix.SIG.PIPE));

    // Remove one signal
    set.remove(posix.SIG.INT);
    try testing.expect(!set.contains(posix.SIG.INT));

    // Others should still be there
    try testing.expect(set.contains(posix.SIG.QUIT));
    try testing.expect(set.contains(posix.SIG.PIPE));

    // Remove all signals
    set.remove(posix.SIG.QUIT);
    set.remove(posix.SIG.PIPE);

    try testing.expect(!set.contains(posix.SIG.INT));
    try testing.expect(!set.contains(posix.SIG.QUIT));
    try testing.expect(!set.contains(posix.SIG.PIPE));
}

test "SignalSet - full set contains common signals" {
    const testing = std.testing;

    const set = SignalSet.initFull();

    // Full set should contain all common signals
    try testing.expect(set.contains(posix.SIG.HUP));
    try testing.expect(set.contains(posix.SIG.INT));
    try testing.expect(set.contains(posix.SIG.QUIT));
    try testing.expect(set.contains(posix.SIG.KILL));
    try testing.expect(set.contains(posix.SIG.USR1));
    try testing.expect(set.contains(posix.SIG.USR2));
    try testing.expect(set.contains(posix.SIG.TERM));
    try testing.expect(set.contains(posix.SIG.CHLD));
    try testing.expect(set.contains(posix.SIG.CONT));
}

test "signal masking - nested blocking" {
    const testing = std.testing;

    // First, block USR1
    var set1 = SignalSet.initEmpty();
    set1.add(posix.SIG.USR1);
    const mask1 = try blockSignals(set1);
    defer _ = setSignalMask(mask1) catch {};

    // Verify USR1 is blocked
    var current = try getSignalMask();
    try testing.expect(current.contains(posix.SIG.USR1));

    // Now block USR2 as well
    var set2 = SignalSet.initEmpty();
    set2.add(posix.SIG.USR2);
    const mask2 = try blockSignals(set2);

    // Verify both are blocked
    current = try getSignalMask();
    try testing.expect(current.contains(posix.SIG.USR1));
    try testing.expect(current.contains(posix.SIG.USR2));

    // Restore second mask
    _ = try setSignalMask(mask2);

    // USR1 should still be blocked, USR2 should not
    current = try getSignalMask();
    try testing.expect(current.contains(posix.SIG.USR1));
}

test "signal masking - setSignalMask direct" {
    const testing = std.testing;

    // Get current mask
    const original = try getSignalMask();
    defer _ = setSignalMask(original) catch {};

    // Create a new mask with specific signals
    var new_mask = SignalSet.initEmpty();
    new_mask.add(posix.SIG.USR1);
    new_mask.add(posix.SIG.USR2);

    // Set it directly
    _ = try setSignalMask(new_mask);

    // Verify it was set
    const current = try getSignalMask();
    try testing.expect(current.contains(posix.SIG.USR1));
    try testing.expect(current.contains(posix.SIG.USR2));
}

test "signal masking - empty set" {
    const testing = std.testing;

    const empty = SignalSet.initEmpty();

    // Get current mask
    const original = try getSignalMask();
    defer _ = setSignalMask(original) catch {};

    // Blocking empty set should not change anything
    const old = try blockSignals(empty);

    // Mask should be the same
    const current = try getSignalMask();
    try testing.expect(current.contains(posix.SIG.USR1) == old.contains(posix.SIG.USR1));
}

test "signal masking - full set isolation" {
    const testing = std.testing;

    // Get current mask to restore later
    const original = try getSignalMask();
    defer _ = setSignalMask(original) catch {};

    // Block all signals
    const full = SignalSet.initFull();
    _ = try setSignalMask(full);

    // Verify many signals are blocked
    const current = try getSignalMask();
    try testing.expect(current.contains(posix.SIG.USR1));
    try testing.expect(current.contains(posix.SIG.USR2));
    try testing.expect(current.contains(posix.SIG.HUP));
    try testing.expect(current.contains(posix.SIG.INT));
    try testing.expect(current.contains(posix.SIG.TERM));
}

test "signal masking - mask persistence" {
    const testing = std.testing;

    // Get original mask
    const original = try getSignalMask();
    defer _ = setSignalMask(original) catch {};

    // Create and set a specific mask
    var set = SignalSet.initEmpty();
    set.add(posix.SIG.USR1);
    set.add(posix.SIG.HUP);
    _ = try setSignalMask(set);

    // Get it back
    const retrieved = try getSignalMask();

    // Should match what we set
    try testing.expect(retrieved.contains(posix.SIG.USR1));
    try testing.expect(retrieved.contains(posix.SIG.HUP));
    try testing.expect(!retrieved.contains(posix.SIG.USR2));
}
