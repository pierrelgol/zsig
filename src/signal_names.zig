const std = @import("std");
const posix = std.posix;

pub fn signalFromName(name: []const u8) ?i32 {
    var buf: [32]u8 = undefined;
    if (name.len > buf.len) return null;

    const upper = blk: {
        for (name, 0..) |c, i| {
            buf[i] = std.ascii.toUpper(c);
        }
        break :blk buf[0..name.len];
    };

    const signal_name = if (std.mem.startsWith(u8, upper, "SIG") and upper.len > 3)
        upper[3..]
    else
        upper;

    if (std.mem.eql(u8, signal_name, "HUP")) return posix.SIG.HUP;
    if (std.mem.eql(u8, signal_name, "INT")) return posix.SIG.INT;
    if (std.mem.eql(u8, signal_name, "QUIT")) return posix.SIG.QUIT;
    if (std.mem.eql(u8, signal_name, "ILL")) return posix.SIG.ILL;
    if (std.mem.eql(u8, signal_name, "TRAP")) return posix.SIG.TRAP;
    if (std.mem.eql(u8, signal_name, "ABRT")) return posix.SIG.ABRT;
    if (std.mem.eql(u8, signal_name, "BUS")) return posix.SIG.BUS;
    if (std.mem.eql(u8, signal_name, "FPE")) return posix.SIG.FPE;
    if (std.mem.eql(u8, signal_name, "KILL")) return posix.SIG.KILL;
    if (std.mem.eql(u8, signal_name, "USR1")) return posix.SIG.USR1;
    if (std.mem.eql(u8, signal_name, "SEGV")) return posix.SIG.SEGV;
    if (std.mem.eql(u8, signal_name, "USR2")) return posix.SIG.USR2;
    if (std.mem.eql(u8, signal_name, "PIPE")) return posix.SIG.PIPE;
    if (std.mem.eql(u8, signal_name, "ALRM")) return posix.SIG.ALRM;
    if (std.mem.eql(u8, signal_name, "TERM")) return posix.SIG.TERM;
    if (std.mem.eql(u8, signal_name, "CHLD")) return posix.SIG.CHLD;
    if (std.mem.eql(u8, signal_name, "CONT")) return posix.SIG.CONT;
    if (std.mem.eql(u8, signal_name, "STOP")) return posix.SIG.STOP;
    if (std.mem.eql(u8, signal_name, "TSTP")) return posix.SIG.TSTP;
    if (std.mem.eql(u8, signal_name, "TTIN")) return posix.SIG.TTIN;
    if (std.mem.eql(u8, signal_name, "TTOU")) return posix.SIG.TTOU;
    if (std.mem.eql(u8, signal_name, "URG")) return posix.SIG.URG;
    if (std.mem.eql(u8, signal_name, "XCPU")) return posix.SIG.XCPU;
    if (std.mem.eql(u8, signal_name, "XFSZ")) return posix.SIG.XFSZ;
    if (std.mem.eql(u8, signal_name, "VTALRM")) return posix.SIG.VTALRM;
    if (std.mem.eql(u8, signal_name, "PROF")) return posix.SIG.PROF;
    if (std.mem.eql(u8, signal_name, "WINCH")) return posix.SIG.WINCH;
    if (std.mem.eql(u8, signal_name, "IO")) return posix.SIG.IO;
    if (std.mem.eql(u8, signal_name, "PWR")) return posix.SIG.PWR;
    if (std.mem.eql(u8, signal_name, "SYS")) return posix.SIG.SYS;

    return null;
}

pub fn nameFromSignal(sig: i32) ?[]const u8 {
    return switch (sig) {
        posix.SIG.HUP => "HUP",
        posix.SIG.INT => "INT",
        posix.SIG.QUIT => "QUIT",
        posix.SIG.ILL => "ILL",
        posix.SIG.TRAP => "TRAP",
        posix.SIG.ABRT => "ABRT",
        posix.SIG.BUS => "BUS",
        posix.SIG.FPE => "FPE",
        posix.SIG.KILL => "KILL",
        posix.SIG.USR1 => "USR1",
        posix.SIG.SEGV => "SEGV",
        posix.SIG.USR2 => "USR2",
        posix.SIG.PIPE => "PIPE",
        posix.SIG.ALRM => "ALRM",
        posix.SIG.TERM => "TERM",
        posix.SIG.CHLD => "CHLD",
        posix.SIG.CONT => "CONT",
        posix.SIG.STOP => "STOP",
        posix.SIG.TSTP => "TSTP",
        posix.SIG.TTIN => "TTIN",
        posix.SIG.TTOU => "TTOU",
        posix.SIG.URG => "URG",
        posix.SIG.XCPU => "XCPU",
        posix.SIG.XFSZ => "XFSZ",
        posix.SIG.VTALRM => "VTALRM",
        posix.SIG.PROF => "PROF",
        posix.SIG.WINCH => "WINCH",
        posix.SIG.IO => "IO",
        posix.SIG.PWR => "PWR",
        posix.SIG.SYS => "SYS",
        else => null,
    };
}

test "signalFromName - basic signals" {
    const testing = std.testing;

    try testing.expectEqual(posix.SIG.TERM, signalFromName("TERM"));
    try testing.expectEqual(posix.SIG.TERM, signalFromName("SIGTERM"));
    try testing.expectEqual(posix.SIG.TERM, signalFromName("term"));
    try testing.expectEqual(posix.SIG.TERM, signalFromName("sigterm"));

    try testing.expectEqual(posix.SIG.HUP, signalFromName("HUP"));
    try testing.expectEqual(posix.SIG.USR1, signalFromName("USR1"));
    try testing.expectEqual(posix.SIG.KILL, signalFromName("KILL"));
    try testing.expectEqual(posix.SIG.CHLD, signalFromName("CHLD"));
}

test "signalFromName - invalid" {
    const testing = std.testing;

    try testing.expectEqual(null, signalFromName("INVALID"));
    try testing.expectEqual(null, signalFromName(""));
    try testing.expectEqual(null, signalFromName("SIG"));
}

test "nameFromSignal - basic signals" {
    const testing = std.testing;

    try testing.expectEqualStrings("TERM", nameFromSignal(posix.SIG.TERM).?);
    try testing.expectEqualStrings("HUP", nameFromSignal(posix.SIG.HUP).?);
    try testing.expectEqualStrings("USR1", nameFromSignal(posix.SIG.USR1).?);
    try testing.expectEqualStrings("CHLD", nameFromSignal(posix.SIG.CHLD).?);
}

test "nameFromSignal - invalid" {
    const testing = std.testing;

    try testing.expectEqual(null, nameFromSignal(9999));
    try testing.expectEqual(null, nameFromSignal(-1));
}

test "signal round-trip - all supported signals" {
    const testing = std.testing;

    // Test all supported signals can be converted name->number->name
    const signals = [_][]const u8{
        "HUP",    "INT",  "QUIT",  "ILL",  "TRAP", "ABRT", "BUS",  "FPE",
        "KILL",   "USR1", "SEGV",  "USR2", "PIPE", "ALRM", "TERM", "CHLD",
        "CONT",   "STOP", "TSTP",  "TTIN", "TTOU", "URG",  "XCPU", "XFSZ",
        "VTALRM", "PROF", "WINCH", "IO",   "PWR",  "SYS",
    };

    for (signals) |name| {
        const sig_num = signalFromName(name);
        try testing.expect(sig_num != null);

        const sig_name = nameFromSignal(sig_num.?);
        try testing.expect(sig_name != null);
        try testing.expectEqualStrings(name, sig_name.?);
    }
}

test "signalFromName - case insensitivity" {
    const testing = std.testing;

    // Mixed case variants
    try testing.expectEqual(posix.SIG.TERM, signalFromName("TeRm"));
    try testing.expectEqual(posix.SIG.HUP, signalFromName("hUp"));
    try testing.expectEqual(posix.SIG.USR1, signalFromName("UsR1"));
    try testing.expectEqual(posix.SIG.CHLD, signalFromName("cHlD"));

    // With SIG prefix in various cases
    try testing.expectEqual(posix.SIG.TERM, signalFromName("SiGtErM"));
    try testing.expectEqual(posix.SIG.HUP, signalFromName("sIgHuP"));
}

test "signalFromName - all variants with SIG prefix" {
    const testing = std.testing;

    // Every signal should work with and without SIG prefix
    try testing.expectEqual(signalFromName("HUP"), signalFromName("SIGHUP"));
    try testing.expectEqual(signalFromName("INT"), signalFromName("SIGINT"));
    try testing.expectEqual(signalFromName("TERM"), signalFromName("SIGTERM"));
    try testing.expectEqual(signalFromName("KILL"), signalFromName("SIGKILL"));
    try testing.expectEqual(signalFromName("USR1"), signalFromName("SIGUSR1"));
    try testing.expectEqual(signalFromName("USR2"), signalFromName("SIGUSR2"));
    try testing.expectEqual(signalFromName("CHLD"), signalFromName("SIGCHLD"));
    try testing.expectEqual(signalFromName("CONT"), signalFromName("SIGCONT"));
    try testing.expectEqual(signalFromName("STOP"), signalFromName("SIGSTOP"));
}

test "signalFromName - buffer boundary" {
    const testing = std.testing;

    // Names longer than buffer should return null
    const too_long = "SIGVERYLONGSIGNALNAMETHATEXCEEDSBUFFER";
    try testing.expectEqual(null, signalFromName(too_long));

    // Edge case: exactly at buffer boundary (32 chars)
    const at_boundary = "SIGTERMXXXXXXXXXXXXXXXXXX"; // 26 chars (under 32)
    try testing.expectEqual(null, signalFromName(at_boundary)); // Should be invalid, not TERM
}

test "signalFromName - edge cases" {
    const testing = std.testing;

    // Just "SIG" prefix without signal name
    try testing.expectEqual(null, signalFromName("SIG"));

    // Numbers
    try testing.expectEqual(null, signalFromName("123"));
    try testing.expectEqual(null, signalFromName("SIG123"));

    // Special characters
    try testing.expectEqual(null, signalFromName("SIG-TERM"));
    try testing.expectEqual(null, signalFromName("TERM!"));
}

test "nameFromSignal - all common signals" {
    const testing = std.testing;

    // Test a comprehensive set of signals
    try testing.expectEqualStrings("HUP", nameFromSignal(posix.SIG.HUP).?);
    try testing.expectEqualStrings("INT", nameFromSignal(posix.SIG.INT).?);
    try testing.expectEqualStrings("QUIT", nameFromSignal(posix.SIG.QUIT).?);
    try testing.expectEqualStrings("KILL", nameFromSignal(posix.SIG.KILL).?);
    try testing.expectEqualStrings("USR1", nameFromSignal(posix.SIG.USR1).?);
    try testing.expectEqualStrings("USR2", nameFromSignal(posix.SIG.USR2).?);
    try testing.expectEqualStrings("PIPE", nameFromSignal(posix.SIG.PIPE).?);
    try testing.expectEqualStrings("ALRM", nameFromSignal(posix.SIG.ALRM).?);
    try testing.expectEqualStrings("CONT", nameFromSignal(posix.SIG.CONT).?);
    try testing.expectEqualStrings("STOP", nameFromSignal(posix.SIG.STOP).?);
}
