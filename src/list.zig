const std = @import("std");

pub const OutputMode = enum { pipe, terminal };
pub const Config = struct { all: bool, output_mode: OutputMode, width: usize };

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
    config: Config,

    pub fn init(self: *PrintDirectoryContents, io: std.Io, writer: *std.Io.Writer, allocator: std.mem.Allocator, config: Config) !void {
        self.io = io;
        self.writer = writer;
        self.allocator = allocator;
        self.entries = .empty;
        self.config = config;
    }

    pub fn deinit(self: *PrintDirectoryContents) void {
        for (self.entries.items) |entry| {
            self.allocator.free(entry.name);
        }
        self.entries.deinit(self.allocator);
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
                .name = try self.allocator.dupe(u8, entry.name),
                .kind = entry.kind,
                .inode = entry.inode,
            };

            try self.entries.append(self.allocator, owned_entry);
        }
        // std.debug.print("\n", .{});
        try self.printEntries();
    }

    fn isHidden(name: []const u8) bool {
        return std.mem.startsWith(u8, name, ".");
    }

    fn comparatorFn(_: @TypeOf(.{}), a: OwnedEntry, b: OwnedEntry) bool {
        return std.mem.order(u8, a.name, b.name) == .lt;
    }

    fn columnWidth(entries: []const OwnedEntry) usize {
        var max_word_length: usize = 0;
        for (entries) |entry| {
            if (max_word_length < entry.name.len)
                max_word_length = entry.name.len;
        }

        return max_word_length + 3;
    }

    fn printEntries(self: *PrintDirectoryContents) !void {
        std.mem.sort(
            OwnedEntry,
            self.entries.items,
            .{},
            comparatorFn,
        );

        const column_width: usize = columnWidth(self.entries.items);
        const words_in_a_row: usize = @max(1, self.config.width / column_width);

        var words: usize = 0;
        for (self.entries.items) |entry| {
            if (!self.config.all and isHidden(entry.name)) {
                continue;
            }
            if (words >= words_in_a_row) {
                try self.writer.print("\n", .{});
                words = 0;
            }

            try self.writer.print("{s}", .{entry.name});

            switch (self.config.output_mode) {
                .terminal => {
                    words += 1;
                    const padding: usize = column_width - entry.name.len;
                    for (0..padding) |_| try self.writer.writeByte(' ');
                },
                .pipe => {
                    try self.writer.print("\n", .{});
                },
            }
        }
    }
};
