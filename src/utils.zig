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
