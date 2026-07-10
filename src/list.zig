const std = @import("std");
const builtin = @import("builtin");

pub const OutputMode = enum { pipe, terminal };
pub const Config = struct { all: bool, long: bool, output_mode: OutputMode, width: usize };

const OwnedEntry = struct {
    name: []u8,
    kind: std.Io.File.Kind,
    inode: std.Io.File.INode,
};

pub const PrintDirectoryContents = struct {
    writer: *std.Io.Writer,
    io: std.Io,
    allocator: std.mem.Allocator,
    entries: std.ArrayList(OwnedEntry),
    visible: std.ArrayList(*const OwnedEntry),
    config: Config,
    root: []u8,

    pub fn init(self: *PrintDirectoryContents, io: std.Io, writer: *std.Io.Writer, allocator: std.mem.Allocator, config: Config) !void {
        self.io = io;
        self.writer = writer;
        self.allocator = allocator;
        self.entries = .empty;
        self.visible = .empty;
        self.config = config;
        self.root = try self.allocator.dupe(u8, "");
    }

    pub fn deinit(self: *PrintDirectoryContents) void {
        for (self.entries.items) |entry| {
            self.allocator.free(entry.name);
        }
        self.entries.deinit(self.allocator);
        self.visible.deinit(self.allocator);
    }

    pub fn clear(self: *PrintDirectoryContents) void {
        for (self.entries.items) |entry| {
            self.allocator.free(entry.name);
        }
        self.entries.clearRetainingCapacity();
        self.visible.clearRetainingCapacity();
        self.allocator.free(self.root);
    }

    pub fn printDirectories(self: *PrintDirectoryContents, root: []const u8) !void {
        self.root = try self.allocator.dupe(u8, root);
        var dir: std.Io.Dir = try std.Io.Dir.cwd().openDir(self.io, root, .{ .iterate = true });
        defer dir.close(self.io);

        var dirIterator = dir.iterate();

        while (try dirIterator.next(self.io)) |entry| {
            const owned_entry: OwnedEntry = .{
                .name = try self.allocator.dupe(u8, entry.name),
                .kind = entry.kind,
                .inode = entry.inode,
            };

            try self.entries.append(self.allocator, owned_entry);
        }

        self.sortEntries();
        try self.extractVisible();
        if (self.config.long) {
            try self.printEntriesLong();
        } else {
            try self.printEntries();
        }
    }

    fn sortEntries(self: *PrintDirectoryContents) void {
        std.mem.sort(
            OwnedEntry,
            self.entries.items,
            .{},
            comparatorFn,
        );
    }
    fn extractVisible(self: *PrintDirectoryContents) !void {
        for (self.entries.items) |*entry| {
            if (!self.config.all and isHidden(entry.name))
                continue;
            try self.visible.append(self.allocator, entry);
        }
    }

    fn formatPermissions(self: *PrintDirectoryContents, entry: *const OwnedEntry, stat: std.Io.File.Stat) !void {
        try self.writer.writeByte(switch (entry.kind) {
            .directory => 'd',
            .sym_link => 'l',
            else => '-',
        });

        if (builtin.os.tag == .windows) {
            try self.writer.writeAll("---------");
            return;
        }
        if (std.posix.mode_t == u0) {
            try self.writer.writeAll("---------");
            return;
        }

        const mode = stat.permissions.toMode();

        const perms = [_]struct { bit: u32, ch: u8 }{
            .{ .bit = 0o400, .ch = 'r' }, .{ .bit = 0o200, .ch = 'w' }, .{ .bit = 0o100, .ch = 'x' },
            .{ .bit = 0o040, .ch = 'r' }, .{ .bit = 0o020, .ch = 'w' }, .{ .bit = 0o010, .ch = 'x' },
            .{ .bit = 0o004, .ch = 'r' }, .{ .bit = 0o002, .ch = 'w' }, .{ .bit = 0o001, .ch = 'x' },
        };

        for (perms) |p| {
            try self.writer.print("{c}", .{if (mode & p.bit != 0) p.ch else '-'});
        }
    }

    fn numDigits(n: usize) usize {
        var v: usize = n;
        var count: usize = 0;
        while (v >= 10) : (v /= 10) {
            count += 1;
        }
        return count;
    }

    fn printEntriesLong(self: *PrintDirectoryContents) !void {
        var dir = try std.Io.Dir.cwd().openDir(self.io, self.root, .{ .iterate = true });
        defer dir.close(self.io);

        // Pass 1: stat everything once, cache results, compute column widths
        var stats = try self.allocator.alloc(std.Io.File.Stat, self.visible.items.len);
        defer self.allocator.free(stats);

        var max_nlink_width: usize = 1;
        var max_size_width: usize = 1;

        for (self.visible.items, 0..) |entry, i| {
            stats[i] = try std.Io.Dir.statFile(dir, self.io, entry.name, .{});
            max_nlink_width = @max(max_nlink_width, numDigits(stats[i].nlink));
            max_size_width = @max(max_size_width, numDigits(stats[i].size));
        }

        for (self.visible.items, 0..) |entry, i| {
            try self.formatPermissions(entry, stats[i]);
            try self.writer.writeByte(' ');

            const nlink_digits = numDigits(stats[i].nlink);
            for (0..max_nlink_width - nlink_digits) |_| try self.writer.writeByte(' ');
            try self.writer.print("{d}", .{stats[i].nlink});
            try self.writer.writeByte(' ');

            const size_digits = numDigits(stats[i].size);
            for (0..max_size_width - size_digits) |_| try self.writer.writeByte(' ');
            try self.writer.print("{d}", .{stats[i].size});
            try self.writer.writeByte(' ');

            try self.writer.writeAll(entry.name);
            try self.writer.writeByte('\n');
        }
    }

    fn isHidden(name: []const u8) bool {
        return std.mem.startsWith(u8, name, ".");
    }

    fn comparatorFn(_: @TypeOf(.{}), a: OwnedEntry, b: OwnedEntry) bool {
        return std.mem.order(u8, a.name, b.name) == .lt;
    }

    fn columnWidth(entries: []const *const OwnedEntry) usize {
        var max_word_length: usize = 0;
        for (entries) |entry| {
            if (max_word_length < entry.name.len)
                max_word_length = entry.name.len;
        }

        return max_word_length + 3;
    }

    fn printEntries(self: *PrintDirectoryContents) !void {
        if (self.config.output_mode == .pipe) {
            for (self.visible.items) |entry| {
                try self.writer.print("{s}\n", .{entry.name});
            }
            return;
        }

        const column_width: usize = columnWidth(self.visible.items);
        const num_columns: usize = @max(1, self.config.width / column_width);
        const num_rows: usize = (self.visible.items.len + num_columns - 1) / num_columns;

        for (0..num_rows) |row| {
            for (0..num_columns) |col| {
                const i = col * num_rows + row;
                if (i >= self.visible.items.len)
                    continue;

                const entry = self.visible.items[i];
                try self.writer.print("{s}", .{entry.name});

                const padding = column_width - entry.name.len;
                for (0..padding) |_| try self.writer.writeByte(' ');
            }

            try self.writer.print("\n", .{});
        }
    }
};
