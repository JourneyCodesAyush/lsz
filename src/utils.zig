const std = @import("std");
const builtin = @import("builtin");

pub fn getTerminalSize(handle: std.Io.File.Handle) !usize {
    // TODO: implement OS based terminal width
    switch (builtin.os.tag) {
        .linux => return getTerminalWidthLinux(handle),
        else => return 80,
    }
}

fn getTerminalWidthLinux(handle: std.Io.File.Handle) usize {
    var winsize = std.mem.zeroes(std.posix.winsize);
    if (std.c.ioctl(handle, std.c.T.IOCGWINSZ, @intFromPtr(&winsize)) == 0) {
        return winsize.col;
    }
    // Fallback value
    return 80;
}

pub const month_names = [_][]const u8{ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };

pub const Date = struct {
    year: i32 = 0,
    month: u32 = 0,
    day: u32 = 0,
};

// Neri/Schneider (2021): https://arxiv.org/abs/2102.06959v1
// Ported via the C++ reference impl (https://github.com/cassioneri/calendar).
const S: u32 = 82;
const K: u32 = 719468 + 146097 * S;
const L: u32 = 400 * S;

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
