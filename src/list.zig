const std = @import("std");

const OwnedEntry = struct {
    name: []u8,
    kind: std.Io.File.Kind,
    inode: std.Io.File.INode,
};

pub const PrintDirectoryContents = struct {
    io: std.Io,
    allocator: *std.mem.Allocator,
    entries: std.ArrayList(OwnedEntry),

    pub fn init(self: *PrintDirectoryContents, io: std.Io, allocator: *std.mem.Allocator) !void {
        self.io = io;
        self.allocator = allocator;
        self.entries = .empty;
    }

    pub fn deinit(self: *PrintDirectoryContents) void {
        for (self.entries.items) |entry| {
            self.allocator.free(entry.name);
        }
        self.entries.deinit(self.allocator.*);
    }

    pub fn printDirectories(self: *PrintDirectoryContents, root: []const u8) !void {
        var dir: std.Io.Dir = try std.Io.Dir.cwd().openDir(self.io, root, .{ .iterate = true });
        defer dir.close(self.io);

        // const stats = try dir.stat(self.io);

        // std.debug.print("{}", .{stats});

        var dirIterator = dir.iterate();

        while (try dirIterator.next(self.io)) |entry| {
            // std.debug.print("{s}\n", .{entry.name});

            const owned_entry: OwnedEntry = .{
                .name = try self.allocator.*.dupe(u8, entry.name),
                .kind = entry.kind,
                .inode = entry.inode,
            };

            try self.entries.append(self.allocator.*, owned_entry);
        }
        // std.debug.print("\n", .{});
        self.printEntries();
    }

    fn comparatorFn(_: @TypeOf(.{}), a: OwnedEntry, b: OwnedEntry) bool {
        return std.mem.order(u8, a.name, b.name) == .lt;
    }

    fn printEntries(self: *PrintDirectoryContents) void {
        std.mem.sort(
            OwnedEntry,
            self.entries.items,
            .{},
            comparatorFn,
        );

        for (self.entries.items) |entry| {
            std.debug.print("{s}\n", .{entry.name});
        }
    }
};
