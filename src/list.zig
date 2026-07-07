const std = @import("std");

pub fn printDirectories(root: []const u8, io: std.Io) !void {
    var dir: std.Io.Dir = try std.Io.Dir.cwd().openDir(io, root, .{ .iterate = true });
    defer dir.close(io);

    // const stats = try dir.stat(io);

    // std.debug.print("{}", .{stats});

    var dirIterator = dir.iterate();

    while (try dirIterator.next(io)) |dirContent| {
        std.debug.print("{s}\n", .{dirContent.name});
    }
}
