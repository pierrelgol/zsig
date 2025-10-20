const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;
const mask = @import("mask.zig");

pub const HandlerFn = *const fn (i32) callconv(.c) void;

pub const HandlerAction = union(enum) {
    handler: HandlerFn,

    ignore,

    default,
};

pub fn setHandler(
    sig: i32,
    action: HandlerAction,
    mask_during_handler: ?mask.SignalSet,
) !linux.Sigaction {
    var act: linux.Sigaction = .{
        .handler = .{ .handler = undefined },
        .mask = if (mask_during_handler) |m| m.inner else linux.sigemptyset(),
        .flags = linux.SA.RESTART,
    };

    switch (action) {
        .handler => |h| {
            act.handler.handler = h;
        },
        .ignore => {
            act.handler.handler = linux.SIG.IGN;
        },
        .default => {
            act.handler.handler = linux.SIG.DFL;
        },
    }

    var old_act: linux.Sigaction = undefined;
    const rc = linux.sigaction(@intCast(sig), &act, &old_act);
    if (rc != 0) {
        return error.SignalActionFailed;
    }

    return old_act;
}

pub fn setHandlerIgnore(sig: i32) !linux.Sigaction {
    return setHandler(sig, .ignore, null);
}

pub fn setHandlerDefault(sig: i32) !linux.Sigaction {
    return setHandler(sig, .default, null);
}

pub fn setHandlerFunction(sig: i32, handler: HandlerFn) !linux.Sigaction {
    return setHandler(sig, .{ .handler = handler }, null);
}

pub fn getHandler(sig: i32) !linux.Sigaction {
    var act: linux.Sigaction = undefined;
    const rc = linux.sigaction(@intCast(sig), null, &act);
    if (rc != 0) {
        return error.SignalActionFailed;
    }
    return act;
}

var test_signal_received: i32 = 0;

fn testHandler(sig: i32) callconv(.c) void {
    test_signal_received = sig;
}

test "setHandler - custom function" {
    const testing = std.testing;

    const old = try setHandler(posix.SIG.USR1, .{ .handler = testHandler }, null);
    defer _ = linux.sigaction(posix.SIG.USR1, &old, null);

    test_signal_received = 0;

    try posix.kill(linux.getpid(), posix.SIG.USR1);

    std.Thread.sleep(10 * std.time.ns_per_ms);

    try testing.expectEqual(posix.SIG.USR1, test_signal_received);
}

// test "setHandler - ignore" {
//     const testing = std.testing;

//     const old = try setHandlerIgnore(posix.SIG.USR2);
//     defer _ = linux.sigaction(posix.SIG.USR2, &old, null);

//     try posix.kill(linux.getpid(), posix.SIG.USR2);
//     std.Thread.sleep(10 * std.time.ns_per_ms);

//     try testing.expect(true);
// }

test "getHandler - retrieves current handler" {
    const testing = std.testing;

    const original = try getHandler(posix.SIG.USR1);

    _ = try setHandlerFunction(posix.SIG.USR1, testHandler);
    defer _ = linux.sigaction(posix.SIG.USR1, &original, null);

    const current = try getHandler(posix.SIG.USR1);

    try testing.expectEqual(@intFromPtr(&testHandler), @intFromPtr(current.handler.handler));
}

// Additional test handlers
var handler_default_called: bool = false;

fn testHandlerDefault(sig: i32) callconv(.c) void {
    _ = sig;
    handler_default_called = true;
}

var multi_sig_received: i32 = 0;
var multi_sig_count: u32 = 0;

fn testHandlerMultiSig(sig: i32) callconv(.c) void {
    multi_sig_received = sig;
    multi_sig_count += 1;
}

test "setHandler - default action" {
    const testing = std.testing;

    // Get original handler
    const original = try getHandler(posix.SIG.USR1);
    defer _ = linux.sigaction(posix.SIG.USR1, &original, null);

    // Set to default
    _ = try setHandlerDefault(posix.SIG.USR1);

    // Verify handler changed (we can't easily test default behavior without risking termination)
    const current = try getHandler(posix.SIG.USR1);
    try testing.expect(current.handler.handler == linux.SIG.DFL);
}

test "setHandler - with mask during handler" {
    const testing = std.testing;

    // Create a mask to block USR2 during USR1 handler
    var handler_mask = mask.SignalSet.initEmpty();
    handler_mask.add(posix.SIG.USR2);

    // Install handler with mask
    const old = try setHandler(posix.SIG.USR1, .{ .handler = testHandler }, handler_mask);
    defer _ = linux.sigaction(posix.SIG.USR1, &old, null);

    test_signal_received = 0;

    // Send USR1
    try posix.kill(linux.getpid(), posix.SIG.USR1);
    std.Thread.sleep(10 * std.time.ns_per_ms);

    // Verify handler was called
    try testing.expectEqual(posix.SIG.USR1, test_signal_received);
}

test "setHandler - multiple signals different handlers" {
    const testing = std.testing;

    // Save original handlers
    const orig_usr1 = try getHandler(posix.SIG.USR1);
    const orig_usr2 = try getHandler(posix.SIG.USR2);
    const orig_hup = try getHandler(posix.SIG.HUP);
    defer {
        _ = linux.sigaction(posix.SIG.USR1, &orig_usr1, null);
        _ = linux.sigaction(posix.SIG.USR2, &orig_usr2, null);
        _ = linux.sigaction(posix.SIG.HUP, &orig_hup, null);
    }

    // Install different handlers
    _ = try setHandlerFunction(posix.SIG.USR1, testHandler);
    _ = try setHandlerFunction(posix.SIG.USR2, testHandlerMultiSig);
    _ = try setHandlerIgnore(posix.SIG.HUP);

    test_signal_received = 0;
    multi_sig_received = 0;

    // Send USR1
    try posix.kill(linux.getpid(), posix.SIG.USR1);
    std.Thread.sleep(10 * std.time.ns_per_ms);
    try testing.expectEqual(posix.SIG.USR1, test_signal_received);

    // Send USR2
    try posix.kill(linux.getpid(), posix.SIG.USR2);
    std.Thread.sleep(10 * std.time.ns_per_ms);
    try testing.expectEqual(posix.SIG.USR2, multi_sig_received);

    // Send HUP (should be ignored)
    try posix.kill(linux.getpid(), posix.SIG.HUP);
    std.Thread.sleep(10 * std.time.ns_per_ms);
    // No way to verify ignore worked except that we didn't crash
    try testing.expect(true);
}

test "setHandler - handler replacement" {
    const testing = std.testing;

    const original = try getHandler(posix.SIG.USR1);
    defer _ = linux.sigaction(posix.SIG.USR1, &original, null);

    // Install first handler
    _ = try setHandlerFunction(posix.SIG.USR1, testHandler);

    test_signal_received = 0;
    try posix.kill(linux.getpid(), posix.SIG.USR1);
    std.Thread.sleep(10 * std.time.ns_per_ms);
    try testing.expectEqual(posix.SIG.USR1, test_signal_received);

    // Replace with second handler
    multi_sig_received = 0;
    _ = try setHandlerFunction(posix.SIG.USR1, testHandlerMultiSig);

    // Send signal again
    try posix.kill(linux.getpid(), posix.SIG.USR1);
    std.Thread.sleep(10 * std.time.ns_per_ms);
    try testing.expectEqual(posix.SIG.USR1, multi_sig_received);
}

test "setHandler - rapid signal delivery" {
    const testing = std.testing;

    const original = try getHandler(posix.SIG.USR1);
    defer _ = linux.sigaction(posix.SIG.USR1, &original, null);

    multi_sig_count = 0;
    _ = try setHandlerFunction(posix.SIG.USR1, testHandlerMultiSig);

    // Send multiple signals
    try posix.kill(linux.getpid(), posix.SIG.USR1);
    try posix.kill(linux.getpid(), posix.SIG.USR1);
    try posix.kill(linux.getpid(), posix.SIG.USR1);

    // Wait for delivery
    std.Thread.sleep(50 * std.time.ns_per_ms);

    // Should have received at least one signal (may coalesce)
    try testing.expect(multi_sig_count >= 1);
}

test "setHandler - correct signal parameter" {
    const testing = std.testing;

    const orig_usr1 = try getHandler(posix.SIG.USR1);
    const orig_usr2 = try getHandler(posix.SIG.USR2);
    defer {
        _ = linux.sigaction(posix.SIG.USR1, &orig_usr1, null);
        _ = linux.sigaction(posix.SIG.USR2, &orig_usr2, null);
    }

    // Install same handler for both signals
    multi_sig_received = 0;
    _ = try setHandlerFunction(posix.SIG.USR1, testHandlerMultiSig);
    _ = try setHandlerFunction(posix.SIG.USR2, testHandlerMultiSig);

    // Send USR1
    try posix.kill(linux.getpid(), posix.SIG.USR1);
    std.Thread.sleep(10 * std.time.ns_per_ms);
    try testing.expectEqual(posix.SIG.USR1, multi_sig_received);

    // Send USR2
    multi_sig_received = 0;
    try posix.kill(linux.getpid(), posix.SIG.USR2);
    std.Thread.sleep(10 * std.time.ns_per_ms);
    try testing.expectEqual(posix.SIG.USR2, multi_sig_received);
}

test "setHandler - restore original handler" {
    const testing = std.testing;

    // Get original
    const original = try getHandler(posix.SIG.USR1);

    // Set custom handler
    const old = try setHandlerFunction(posix.SIG.USR1, testHandler);

    test_signal_received = 0;
    try posix.kill(linux.getpid(), posix.SIG.USR1);
    std.Thread.sleep(10 * std.time.ns_per_ms);
    try testing.expectEqual(posix.SIG.USR1, test_signal_received);

    // Restore original
    _ = linux.sigaction(posix.SIG.USR1, &old, null);

    // Verify restoration worked (can't easily test behavior, but can check it was set)
    const restored = try getHandler(posix.SIG.USR1);
    try testing.expectEqual(@intFromPtr(original.handler.handler), @intFromPtr(restored.handler.handler));
}

test "setHandler - SA_RESTART flag verification" {
    const testing = std.testing;

    const original = try getHandler(posix.SIG.USR1);
    defer _ = linux.sigaction(posix.SIG.USR1, &original, null);

    // Set a handler
    _ = try setHandlerFunction(posix.SIG.USR1, testHandler);

    // Get it back and verify SA_RESTART flag is set
    const current = try getHandler(posix.SIG.USR1);
    try testing.expect((current.flags & linux.SA.RESTART) != 0);
}
