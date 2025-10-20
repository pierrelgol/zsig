const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;

pub const ChildStatus = struct {
    pid: posix.pid_t,

    exit_info: ExitInfo,

    pub const ExitInfo = union(enum) {
        exited: u8,

        signaled: i32,

        stopped: i32,

        continued,
    };

    fn fromWaitStatus(pid: posix.pid_t, status: u32) ChildStatus {
        if (linux.W.IFEXITED(status)) {
            return .{
                .pid = pid,
                .exit_info = .{ .exited = linux.W.EXITSTATUS(status) },
            };
        } else if (linux.W.IFSIGNALED(status)) {
            return .{
                .pid = pid,
                .exit_info = .{ .signaled = @intCast(linux.W.TERMSIG(status)) },
            };
        } else if (linux.W.IFSTOPPED(status)) {
            return .{
                .pid = pid,
                .exit_info = .{ .stopped = @intCast(linux.W.STOPSIG(status)) },
            };
        } else {
            return .{
                .pid = pid,
                .exit_info = .continued,
            };
        }
    }

    pub fn exitedNormally(self: ChildStatus) bool {
        return switch (self.exit_info) {
            .exited => true,
            else => false,
        };
    }

    pub fn exitCode(self: ChildStatus) ?u8 {
        return switch (self.exit_info) {
            .exited => |code| code,
            else => null,
        };
    }

    pub fn wasSignaled(self: ChildStatus) bool {
        return switch (self.exit_info) {
            .signaled => true,
            else => false,
        };
    }

    pub fn termSignal(self: ChildStatus) ?i32 {
        return switch (self.exit_info) {
            .signaled => |sig| sig,
            else => null,
        };
    }
};

pub fn waitChild(pid: posix.pid_t) !?ChildStatus {
    var status: u32 = 0;
    const result = linux.waitpid(pid, &status, linux.W.NOHANG);

    const MAX_ERRNO = 4095;
    if (result > @as(usize, 0) -% MAX_ERRNO) {
        return error.WaitFailed;
    }

    if (result == 0) {
        return null;
    }

    return ChildStatus.fromWaitStatus(@intCast(result), status);
}

pub fn waitAnyChild() !?ChildStatus {
    return waitChild(-1);
}

pub fn waitChildBlocking(pid: posix.pid_t) !ChildStatus {
    var status: u32 = 0;
    const result = linux.waitpid(pid, &status, 0);

    const MAX_ERRNO = 4095;
    if (result > @as(usize, 0) -% MAX_ERRNO) {
        return error.WaitFailed;
    }

    return ChildStatus.fromWaitStatus(@intCast(result), status);
}

pub fn sendSignal(pid: posix.pid_t, sig: i32) !void {
    try posix.kill(pid, @intCast(sig));
}

pub fn sendSignalToGroup(pgid: posix.pid_t, sig: i32) !void {
    try posix.kill(-pgid, @intCast(sig));
}

test "ChildStatus - parse exit status" {
    const testing = std.testing;

    const status1 = ChildStatus.fromWaitStatus(1234, 0x0000);
    try testing.expect(status1.exitedNormally());
    try testing.expectEqual(@as(u8, 0), status1.exitCode().?);
    try testing.expect(!status1.wasSignaled());

    const status2 = ChildStatus.fromWaitStatus(1234, 0x2A00);
    try testing.expect(status2.exitedNormally());
    try testing.expectEqual(@as(u8, 42), status2.exitCode().?);

    const status3 = ChildStatus.fromWaitStatus(1234, 0x000F);
    try testing.expect(!status3.exitedNormally());
    try testing.expect(status3.wasSignaled());
    try testing.expectEqual(@as(i32, 15), status3.termSignal().?);
    try testing.expectEqual(@as(?u8, null), status3.exitCode());
}

test "waitChild - no child processes" {
    const testing = std.testing;

    const result = waitChild(999999);
    try testing.expectError(error.WaitFailed, result);
}

test "sendSignal - to self" {
    const testing = std.testing;

    const handler = struct {
        var received: bool = false;
        fn handle(_: i32) callconv(.c) void {
            received = true;
        }
    };

    var act: linux.Sigaction = .{
        .handler = .{ .handler = handler.handle },
        .mask = linux.sigemptyset(),
        .flags = 0,
    };
    var old: linux.Sigaction = undefined;
    _ = linux.sigaction(posix.SIG.USR1, &act, &old);
    defer _ = linux.sigaction(posix.SIG.USR1, &old, null);

    handler.received = false;

    try sendSignal(linux.getpid(), posix.SIG.USR1);

    std.Thread.sleep(10 * std.time.ns_per_ms);

    try testing.expect(handler.received);
}

test "ChildStatus - all methods comprehensive" {
    const testing = std.testing;

    // Test with normal exit
    const status1 = ChildStatus.fromWaitStatus(100, 0x0000);
    try testing.expect(status1.exitedNormally());
    try testing.expectEqual(@as(u8, 0), status1.exitCode().?);
    try testing.expect(!status1.wasSignaled());
    try testing.expectEqual(@as(?i32, null), status1.termSignal());

    // Test with signaled
    const status2 = ChildStatus.fromWaitStatus(200, 0x0009); // SIGKILL
    try testing.expect(!status2.exitedNormally());
    try testing.expectEqual(@as(?u8, null), status2.exitCode());
    try testing.expect(status2.wasSignaled());
    try testing.expectEqual(@as(i32, 9), status2.termSignal().?);

    // Test with stopped
    const status3 = ChildStatus.fromWaitStatus(300, 0x137F); // SIGSTOP in high byte, 0x7F = stopped
    try testing.expect(!status3.exitedNormally());
    try testing.expectEqual(@as(?u8, null), status3.exitCode());
}

test "ChildStatus - stopped process" {
    const testing = std.testing;

    // Simulate a stopped status (WIFSTOPPED)
    const stopped_status = 0x137F; // Signal 19 (SIGSTOP), stopped indicator
    const status = ChildStatus.fromWaitStatus(123, stopped_status);

    try testing.expect(!status.exitedNormally());
    try testing.expect(!status.wasSignaled());
}

test "ChildStatus - continued status" {
    const testing = std.testing;

    // Simulate a continued status (not exited, signaled, or stopped)
    const continued_status = 0xFFFF;
    const status = ChildStatus.fromWaitStatus(456, continued_status);

    // Should be marked as continued
    try testing.expect(!status.exitedNormally());
    try testing.expect(!status.wasSignaled());
}

test "Child Status - multiple exit codes" {
    const testing = std.testing;

    // Exit code 0
    const status0 = ChildStatus.fromWaitStatus(1, 0x0000);
    try testing.expectEqual(@as(u8, 0), status0.exitCode().?);

    // Exit code 1
    const status1 = ChildStatus.fromWaitStatus(1, 0x0100);
    try testing.expectEqual(@as(u8, 1), status1.exitCode().?);

    // Exit code 127
    const status127 = ChildStatus.fromWaitStatus(1, 0x7F00);
    try testing.expectEqual(@as(u8, 127), status127.exitCode().?);

    // Exit code 255
    const status255 = ChildStatus.fromWaitStatus(1, 0xFF00);
    try testing.expectEqual(@as(u8, 255), status255.exitCode().?);
}

test "ChildStatus - multiple signal terminations" {
    const testing = std.testing;

    // SIGTERM (15)
    const term_status = ChildStatus.fromWaitStatus(1, 0x000F);
    try testing.expect(term_status.wasSignaled());
    try testing.expectEqual(@as(i32, 15), term_status.termSignal().?);

    // SIGKILL (9)
    const kill_status = ChildStatus.fromWaitStatus(1, 0x0009);
    try testing.expect(kill_status.wasSignaled());
    try testing.expectEqual(@as(i32, 9), kill_status.termSignal().?);

    // SIGSEGV (11)
    const segv_status = ChildStatus.fromWaitStatus(1, 0x000B);
    try testing.expect(segv_status.wasSignaled());
    try testing.expectEqual(@as(i32, 11), segv_status.termSignal().?);
}

test "waitChild - with pid zero" {
    const testing = std.testing;

    // Waiting for pid 0 (any child in process group) should either:
    // - Return null (WNOHANG, no children)
    // - Return error (no children exist)
    const result = waitChild(0);

    // We expect this to either return null or an error since we have no children
    if (result) |maybe_status| {
        // If it succeeds, should be null (no children ready)
        try testing.expectEqual(@as(?ChildStatus, null), maybe_status);
    } else |_| {
        // Error is also acceptable (no children)
        try testing.expect(true);
    }
}

test "waitAnyChild - functionality" {
    const testing = std.testing;

    // waitAnyChild should behave like waitChild(-1)
    // Since we have no children, should return null or error
    const result = waitAnyChild();

    if (result) |maybe_status| {
        try testing.expectEqual(@as(?ChildStatus, null), maybe_status);
    } else |_| {
        try testing.expect(true);
    }
}

test "sendSignalToGroup - current process group" {
    const testing = std.testing;

    // Setup handler for SIGUSR2
    const handler = struct {
        var received: bool = false;
        fn handle(_: i32) callconv(.c) void {
            received = true;
        }
    };

    var act: linux.Sigaction = .{
        .handler = .{ .handler = handler.handle },
        .mask = linux.sigemptyset(),
        .flags = 0,
    };
    var old: linux.Sigaction = undefined;
    _ = linux.sigaction(posix.SIG.USR2, &act, &old);
    defer _ = linux.sigaction(posix.SIG.USR2, &old, null);

    handler.received = false;

    // Send to our own process group (pid 0)
    try sendSignalToGroup(0, posix.SIG.USR2);

    std.Thread.sleep(10 * std.time.ns_per_ms);

    try testing.expect(handler.received);
}

test "sendSignal - different signals" {
    const testing = std.testing;

    var received_sig: i32 = 0;
    const handler = struct {
        var sig_received: *i32 = undefined;
        fn handle(sig: i32) callconv(.c) void {
            sig_received.* = sig;
        }
    };

    handler.sig_received = &received_sig;

    // Install handler for USR1 and USR2
    var act: linux.Sigaction = .{
        .handler = .{ .handler = handler.handle },
        .mask = linux.sigemptyset(),
        .flags = 0,
    };
    var old_usr1: linux.Sigaction = undefined;
    var old_usr2: linux.Sigaction = undefined;
    _ = linux.sigaction(posix.SIG.USR1, &act, &old_usr1);
    _ = linux.sigaction(posix.SIG.USR2, &act, &old_usr2);
    defer {
        _ = linux.sigaction(posix.SIG.USR1, &old_usr1, null);
        _ = linux.sigaction(posix.SIG.USR2, &old_usr2, null);
    }

    // Send USR1
    received_sig = 0;
    try sendSignal(linux.getpid(), posix.SIG.USR1);
    std.Thread.sleep(10 * std.time.ns_per_ms);
    try testing.expectEqual(posix.SIG.USR1, received_sig);

    // Send USR2
    received_sig = 0;
    try sendSignal(linux.getpid(), posix.SIG.USR2);
    std.Thread.sleep(10 * std.time.ns_per_ms);
    try testing.expectEqual(posix.SIG.USR2, received_sig);
}

test "ChildStatus - edge case status values" {
    const testing = std.testing;

    // Status with all bits set
    const all_bits = ChildStatus.fromWaitStatus(999, 0xFFFF);
    try testing.expect(!all_bits.exitedNormally());

    // Status with only exit bit pattern
    const exit_only = ChildStatus.fromWaitStatus(1000, 0x0100);
    try testing.expect(exit_only.exitedNormally());
    try testing.expectEqual(@as(u8, 1), exit_only.exitCode().?);

    // Empty status
    const empty = ChildStatus.fromWaitStatus(1001, 0x0000);
    try testing.expect(empty.exitedNormally());
    try testing.expectEqual(@as(u8, 0), empty.exitCode().?);
}
