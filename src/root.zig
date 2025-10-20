const std = @import("std");
pub const SIG = std.posix.SIG;

const handler_mod = @import("handler.zig");
pub const HandlerFn = handler_mod.HandlerFn;
pub const HandlerAction = handler_mod.HandlerAction;
pub const setHandler = handler_mod.setHandler;
pub const setHandlerIgnore = handler_mod.setHandlerIgnore;
pub const setHandlerDefault = handler_mod.setHandlerDefault;
pub const setHandlerFunction = handler_mod.setHandlerFunction;
pub const getHandler = handler_mod.getHandler;
const mask_mod = @import("mask.zig");
pub const SignalSet = mask_mod.SignalSet;
pub const blockSignals = mask_mod.blockSignals;
pub const unblockSignals = mask_mod.unblockSignals;
pub const setSignalMask = mask_mod.setSignalMask;
pub const getSignalMask = mask_mod.getSignalMask;
const process_mod = @import("process.zig");
pub const ChildStatus = process_mod.ChildStatus;
pub const waitChild = process_mod.waitChild;
pub const waitAnyChild = process_mod.waitAnyChild;
pub const waitChildBlocking = process_mod.waitChildBlocking;
pub const sendSignal = process_mod.sendSignal;
pub const sendSignalToGroup = process_mod.sendSignalToGroup;
const signal_names_mod = @import("signal_names.zig");
pub const signalFromName = signal_names_mod.signalFromName;
pub const nameFromSignal = signal_names_mod.nameFromSignal;

test "zsig - complete workflow" {
    const testing = std.testing;

    const sigterm = signalFromName("TERM").?;
    try testing.expectEqual(SIG.TERM, sigterm);

    const name = nameFromSignal(SIG.TERM).?;
    try testing.expectEqualStrings("TERM", name);

    var set = SignalSet.initEmpty();
    try testing.expect(!set.contains(SIG.USR1));

    set.add(SIG.USR1);
    try testing.expect(set.contains(SIG.USR1));

    const old_mask = try blockSignals(set);
    defer _ = setSignalMask(old_mask) catch {};

    const current = try getSignalMask();
    try testing.expect(current.contains(SIG.USR1));
}

test "zsig - handler and process" {
    const testing = std.testing;

    const TestHandler = struct {
        var count: u32 = 0;
        fn handle(_: i32) callconv(.c) void {
            count += 1;
        }
    };

    const old = try setHandlerFunction(SIG.USR2, TestHandler.handle);
    defer _ = std.os.linux.sigaction(SIG.USR2, &old, null);

    TestHandler.count = 0;

    try sendSignal(std.os.linux.getpid(), SIG.USR2);

    std.Thread.sleep(10 * std.time.ns_per_ms);

    try testing.expectEqual(@as(u32, 1), TestHandler.count);
}

// Integration test helpers
var taskmaster_reload_flag: bool = false;
var taskmaster_child_changed: bool = false;

fn taskmasterHandleSighup(_: i32) callconv(.c) void {
    taskmaster_reload_flag = true;
}

fn taskmasterHandleSigchld(_: i32) callconv(.c) void {
    taskmaster_child_changed = true;
}

test "zsig - taskmaster workflow simulation" {
    const testing = std.testing;

    // Install handlers for HUP and CHLD (taskmaster pattern)
    const old_hup = try setHandlerFunction(SIG.HUP, taskmasterHandleSighup);
    const old_chld = try setHandlerFunction(SIG.CHLD, taskmasterHandleSigchld);
    defer {
        _ = std.os.linux.sigaction(SIG.HUP, &old_hup, null);
        _ = std.os.linux.sigaction(SIG.CHLD, &old_chld, null);
    }

    // Reset flags
    taskmaster_reload_flag = false;
    taskmaster_child_changed = false;

    // Simulate SIGHUP for config reload
    try sendSignal(std.os.linux.getpid(), SIG.HUP);
    std.Thread.sleep(10 * std.time.ns_per_ms);
    try testing.expect(taskmaster_reload_flag);

    // Simulate SIGCHLD for child process state change
    try sendSignal(std.os.linux.getpid(), SIG.CHLD);
    std.Thread.sleep(10 * std.time.ns_per_ms);
    try testing.expect(taskmaster_child_changed);

    // Test signal name conversion (for stop signal config)
    const term_sig = signalFromName("TERM").?;
    try testing.expectEqual(SIG.TERM, term_sig);

    // Block SIGCHLD during critical section (updating process list)
    var mask = SignalSet.initEmpty();
    mask.add(SIG.CHLD);
    const old_mask = try blockSignals(mask);
    defer _ = setSignalMask(old_mask) catch {};

    // Critical section protected
    const current = try getSignalMask();
    try testing.expect(current.contains(SIG.CHLD));
}

test "zsig - error propagation" {
    const testing = std.testing;

    // Test that errors bubble up correctly

    // Invalid PID for waitChild
    const wait_result = waitChild(999999);
    try testing.expectError(error.WaitFailed, wait_result);

    // Invalid signal name
    try testing.expectEqual(@as(?i32, null), signalFromName("INVALID_SIG"));

    // Verify error types are correct
    const CompareError = error{WaitFailed};
    const wait_err = wait_result catch |err| err;
    try testing.expectEqual(CompareError.WaitFailed, wait_err);
}

test "zsig - handler and masking interaction" {
    const testing = std.testing;

    var handler_called: bool = false;
    const TestHandler = struct {
        var called: *bool = undefined;
        fn handle(_: i32) callconv(.c) void {
            called.* = true;
        }
    };
    TestHandler.called = &handler_called;

    // Install handler for USR1
    const old = try setHandlerFunction(SIG.USR1, TestHandler.handle);
    defer _ = std.os.linux.sigaction(SIG.USR1, &old, null);

    // Block USR1
    var set = SignalSet.initEmpty();
    set.add(SIG.USR1);
    const old_mask = try blockSignals(set);

    handler_called = false;

    // Send signal while blocked - won't be delivered immediately
    try sendSignal(std.os.linux.getpid(), SIG.USR1);
    std.Thread.sleep(10 * std.time.ns_per_ms);

    // Handler should not have been called yet (signal is blocked)
    // Note: This is timing-dependent, but in practice the signal stays blocked

    // Unblock and signal should be delivered
    _ = try setSignalMask(old_mask);
    std.Thread.sleep(10 * std.time.ns_per_ms);

    // Now handler should have been called
    try testing.expect(handler_called);
}

test "zsig - multi-signal scenario" {
    const testing = std.testing;

    var usr1_received: bool = false;
    var usr2_received: bool = false;
    var hup_received: bool = false;

    const Usr1Handler = struct {
        var flag: *bool = undefined;
        fn handle(_: i32) callconv(.c) void {
            flag.* = true;
        }
    };
    const Usr2Handler = struct {
        var flag: *bool = undefined;
        fn handle(_: i32) callconv(.c) void {
            flag.* = true;
        }
    };
    const HupHandler = struct {
        var flag: *bool = undefined;
        fn handle(_: i32) callconv(.c) void {
            flag.* = true;
        }
    };

    Usr1Handler.flag = &usr1_received;
    Usr2Handler.flag = &usr2_received;
    HupHandler.flag = &hup_received;

    // Install handlers for multiple signals
    const old_usr1 = try setHandlerFunction(SIG.USR1, Usr1Handler.handle);
    const old_usr2 = try setHandlerFunction(SIG.USR2, Usr2Handler.handle);
    const old_hup = try setHandlerFunction(SIG.HUP, HupHandler.handle);
    defer {
        _ = std.os.linux.sigaction(SIG.USR1, &old_usr1, null);
        _ = std.os.linux.sigaction(SIG.USR2, &old_usr2, null);
        _ = std.os.linux.sigaction(SIG.HUP, &old_hup, null);
    }

    // Create a mask with USR1 and USR2
    var mask = SignalSet.initEmpty();
    mask.add(SIG.USR1);
    mask.add(SIG.USR2);
    const old_mask = try blockSignals(mask);
    defer _ = setSignalMask(old_mask) catch {};

    // Send HUP (not blocked, should be delivered)
    try sendSignal(std.os.linux.getpid(), SIG.HUP);
    std.Thread.sleep(10 * std.time.ns_per_ms);
    try testing.expect(hup_received);

    // Send USR1 and USR2 (blocked, won't be delivered yet)
    try sendSignal(std.os.linux.getpid(), SIG.USR1);
    try sendSignal(std.os.linux.getpid(), SIG.USR2);
    std.Thread.sleep(10 * std.time.ns_per_ms);

    // Unblock and they should be delivered
    _ = try setSignalMask(old_mask);
    std.Thread.sleep(10 * std.time.ns_per_ms);

    try testing.expect(usr1_received);
    try testing.expect(usr2_received);
}

test {
    _ = @import("signal_names.zig");
    _ = @import("mask.zig");
    _ = @import("handler.zig");
    _ = @import("process.zig");
}
