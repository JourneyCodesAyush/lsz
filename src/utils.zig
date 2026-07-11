//! Platform-specific utilities for `lsz`: terminal width detection and
//! rata-die date conversion (used by `-l`'s mtime column).

const std = @import("std");
const builtin = @import("builtin");

/// Returns the current terminal width in columns, for grid-layout sizing.
/// Falls back to 80 on platforms without a native width query implemented
/// (currently everything except Linux — macOS is deliberately deferred
/// until ioctl behavior can be verified there, and native Windows console
/// APIs aren't attempted since Zig 0.16 stripped the kernel32 wrappers
/// this would have relied on).
pub fn getTerminalSize(handle: std.Io.File.Handle) !usize {
    // TODO: implement OS based terminal width
    switch (builtin.os.tag) {
        .linux => return getTerminalWidthLinux(handle),
        else => return 80,
    }
}

/// Queries terminal column width on Linux via `ioctl(TIOCGWINSZ)`.
/// Returns 80 if the ioctl call fails (e.g. `handle` isn't a real tty).
fn getTerminalWidthLinux(handle: std.Io.File.Handle) usize {
    var winsize = std.mem.zeroes(std.posix.winsize);
    if (std.c.ioctl(handle, std.c.T.IOCGWINSZ, @intFromPtr(&winsize)) == 0) {
        return winsize.col;
    }
    // Fallback value
    return 80;
}

/// Three-letter month abbreviations, indexed 0 (Jan) through 11 (Dec) —
/// i.e. `month_names[date.month - 1]` for a 1-indexed `Date.month`.
pub const month_names = [_][]const u8{ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };

/// A calendar date, as produced by `rdToDate`.
pub const Date = struct {
    year: i32 = 0,
    /// 1-indexed: 1 = January, 12 = December.
    month: u32 = 0,
    /// 1-indexed day of month.
    day: u32 = 0,
};

// Neri/Schneider (2021): https://arxiv.org/abs/2102.06959v1
// Ported via the C++ reference impl (https://github.com/cassioneri/calendar).
const S: u32 = 82;
const K: u32 = 719468 + 146097 * S;
const L: u32 = 400 * S;

/// Converts a day count relative to the Unix epoch (1970-01-01 = day 0)
/// into a proleptic Gregorian calendar date. Handles negative day counts
/// (pre-1970 dates) correctly via the wrapping arithmetic in the
/// Neri/Schneider algorithm.
///
/// Used by `list.zig`'s `formatMTime` to render `Stat.mtime` as a
/// human-readable date for `-l` output.
pub fn rdToDate(N_U: i32) Date {
    const N: u32 = @as(u32, @bitCast(N_U)) +% K;

    const N_1: u32 = 4 * N + 3;
    const C: u32 = N_1 / 146097;
    const N_C: u32 = (N_1 % 146097) / 4;

    const N_2: u32 = 4 * N_C + 3;
    const P_2: u64 = @as(u64, 2939745) * N_2;
    const Z: u32 = @intCast(P_2 / 4294967296);
    const N_Y: u32 = @intCast((P_2 % 4294967296) / 2939745 / 4);
    const Y: u32 = 100 * C + Z;

    const N_3: u32 = 2141 * N_Y + 197913;
    const M: u32 = N_3 / 65536;
    const D: u32 = (N_3 % 65536) / 2141;

    const J: u32 = @intFromBool(N_Y >= 306);
    const Y_G: i32 = @intCast(@as(i32, @bitCast(Y -% L)) + @as(i32, @intCast(J)));
    const M_G: u32 = if (J != 0) M - 12 else M;
    const D_G: u32 = D + 1;

    return .{ .year = Y_G, .month = M_G, .day = D_G };
}
