//! Directory-listing logic for `lsz`.
//!
//! `PrintDirectoryContents` owns the lifecycle of a single directory
//! listing: reading entries, filtering hidden files, sorting, and printing
//! either a multi-column grid (default) or long format (`-l`). Instances
//! are reused across multiple positional directory arguments via `clear()`
//! rather than re-initialized, to avoid repeated allocator churn.

const std = @import("std");
const builtin = @import("builtin");

const dateutil = @import("utils.zig");
const month_names = @import("utils.zig").month_names;
const Date = @import("utils.zig").Date;

/// Whether stdout is an interactive terminal (`.terminal`, grid layout) or
/// piped/redirected (`.pipe`, one name per line).
pub const OutputMode = enum { pipe, terminal };

/// Listing options derived from parsed CLI flags.
pub const Config = struct {
    /// `-a` / `--all` — include entries starting with `.`.
    all: bool,
    /// `-l` / `--long` — use long listing format.
    long: bool,
    output_mode: OutputMode,
    /// Terminal column width, used to compute grid layout in short format.
    width: usize,
};

/// A directory entry with an owned copy of its name, decoupled from the
/// lifetime of the OS-level directory iterator that produced it.
const OwnedEntry = struct {
    name: []u8,
    kind: std.Io.File.Kind,
    inode: std.Io.File.INode,
};

/// Reads, filters, sorts, and prints the contents of one directory at a
/// time. Call `printDirectories` once per directory argument; call
/// `clear()` between calls when listing multiple directories in one run.
pub const PrintDirectoryContents = struct {
    writer: *std.Io.Writer,
    io: std.Io,
    allocator: std.mem.Allocator,
    /// All entries read from the directory, before hidden-file filtering.
    entries: std.ArrayList(OwnedEntry),
    /// Pointers into `entries` for entries that survive hidden-file
    /// filtering; this is what actually gets printed.
    visible: std.ArrayList(*const OwnedEntry),
    config: Config,
    /// Path of the directory currently loaded, used to reopen it (e.g. in
    /// `printEntriesLong`) since it isn't always the process cwd.
    root: []u8,

    /// Initializes an empty listing state. Must be called before any other
    /// method. `self.root` is seeded with an owned empty string so that the
    /// first `clear()` call (which frees `self.root`) has valid memory to
    /// free, even if `printDirectories` hasn't run yet.
    pub fn init(self: *PrintDirectoryContents, io: std.Io, writer: *std.Io.Writer, allocator: std.mem.Allocator, config: Config) !void {
        self.io = io;
        self.writer = writer;
        self.allocator = allocator;
        self.entries = .empty;
        self.visible = .empty;
        self.config = config;
        self.root = try self.allocator.dupe(u8, "");
    }

    /// Frees all owned entry names and backing arrays. Does not free
    /// `self.root` — harmless, since process exit reclaims it, but a known
    /// gap if this type is ever used in a longer-lived context.
    pub fn deinit(self: *PrintDirectoryContents) void {
        for (self.entries.items) |entry| {
            self.allocator.free(entry.name);
        }
        self.entries.deinit(self.allocator);
        self.visible.deinit(self.allocator);
    }

    /// Resets state between directory listings: frees entry names, clears
    /// (but retains capacity of) `entries`/`visible`, and frees `self.root`.
    /// Only call this when a previous `printDirectories` call has actually
    /// populated `self.root` — calling it before any listing has run would
    /// free uninitialized memory (see `init`'s empty-string seeding, which
    /// guards against this on the very first call).
    pub fn clear(self: *PrintDirectoryContents) void {
        for (self.entries.items) |entry| {
            self.allocator.free(entry.name);
        }
        self.entries.clearRetainingCapacity();
        self.visible.clearRetainingCapacity();
        self.allocator.free(self.root);
    }

    /// Reads all entries in `root`, sorts them, filters hidden entries, and
    /// prints them in either long or short format depending on `config`.
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

        // Sort must run before extractVisible: visible holds pointers into
        // entries, so sorting after extraction would leave those pointers
        // misaligned with the now-reordered backing array.
        self.sortEntries();
        try self.extractVisible();
        if (self.config.long) {
            try self.printEntriesLong();
        } else {
            try self.printEntries();
        }
    }

    /// Sorts `entries` alphabetically by name (case-sensitive, byte order).
    /// Note: directory names already carry their trailing `/` suffix at
    /// this point, so sort order can diverge from real `ls`, which sorts on
    /// the bare name and appends `/` only at print time. Known open issue.
    fn sortEntries(self: *PrintDirectoryContents) void {
        std.mem.sort(
            OwnedEntry,
            self.entries.items,
            .{},
            comparatorFn,
        );
    }

    /// Populates `visible` with pointers to entries that pass the
    /// hidden-file filter (i.e. all entries if `-a` was given, otherwise
    /// entries not starting with `.`).
    fn extractVisible(self: *PrintDirectoryContents) !void {
        for (self.entries.items) |*entry| {
            if (!self.config.all and isHidden(entry.name))
                continue;
            try self.visible.append(self.allocator, entry);
        }
    }

    /// Writes the 10-character permission string (e.g. `drwxr-xr-x`) for
    /// one entry. Falls back to a 9-dash placeholder on Windows and on
    /// platforms where `std.posix.mode_t` is the zero-bit-width fallback
    /// type (e.g. WASI), since POSIX mode bits aren't meaningful there.
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

    /// Writes a modification-time string for one entry, GNU `ls -l` style:
    /// `Mon DD HH:MM` if within the last ~6 months, otherwise `Mon DD  YYYY`.
    /// `now_secs` is Unix seconds, snapshotted once per listing (not
    /// per-entry) so that a long-running listing can't have entries
    /// straddling the recent/old boundary inconsistently.
    fn formatMTime(self: *PrintDirectoryContents, mtime: std.Io.Timestamp, now_secs: i64) !void {
        const secs: i64 = @intCast(@divFloor(mtime.nanoseconds, std.time.ns_per_s));
        const epoch_day: i32 = @intCast(@divFloor(secs, 86_400));
        const day_secs: u64 = @intCast(@mod(secs, 86_400));

        const date = dateutil.rdToDate(epoch_day);
        const hour = day_secs / 3600;
        const minute = (day_secs % 3600) / 60;

        const six_months_sec: i64 = 15_778_476;
        const age = now_secs - secs;
        const recent = age < six_months_sec and age > -six_months_sec;

        if (recent) {
            try self.writer.print("{s} {d:>2} {d:0>2}:{d:0>2}", .{ month_names[date.month - 1], date.day, hour, minute });
        } else {
            try self.writer.print("{s} {d:>2}  {d}", .{ month_names[date.month - 1], date.day, date.year });
        }
    }

    /// Returns the number of base-10 digits in `n` (minimum 1), used to
    /// right-align the nlink and size columns to a common width.
    fn numDigits(n: usize) usize {
        var v: usize = n;
        var count: usize = 0;
        while (v >= 10) : (v /= 10) {
            count += 1;
        }
        return count;
    }

    /// Prints `visible` in long format (`-l`): permissions, nlink, size,
    /// mtime, name — one entry per line, columns right-aligned.
    ///
    /// Runs in two passes: the first stats every visible entry once
    /// (caching results and computing the max digit-width of nlink and
    /// size across the directory), and the second prints using those
    /// cached stats and computed widths. This avoids re-statting each
    /// entry and ensures consistent column alignment regardless of the
    /// order entries are visited in.
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

        const now_secs = std.Io.Clock.now(.awake, self.io).toSeconds();

        // Pass 2: print using cached stats and computed widths.
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

            try self.formatMTime(stats[i].mtime, now_secs);
            try self.writer.writeByte(' ');

            try self.writer.writeAll(entry.name);
            try self.writer.writeByte('\n');
        }
    }

    /// Returns true if `name` starts with `.` (dotfile convention).
    /// Known issue: `isHidden(".git")` should return `true` and currently
    /// does (this checks the leading byte only) — the open test failure
    /// noted in project docs concerns a different edge case, not this
    /// function's core logic.
    fn isHidden(name: []const u8) bool {
        return std.mem.startsWith(u8, name, ".");
    }

    /// Case-sensitive byte-order comparator for sorting `OwnedEntry` by
    /// name. See `sortEntries` doc comment for the trailing-slash caveat.
    fn comparatorFn(_: @TypeOf(.{}), a: OwnedEntry, b: OwnedEntry) bool {
        return std.mem.order(u8, a.name, b.name) == .lt;
    }

    /// Returns the print width of one grid column: the longest visible
    /// entry name plus 3 spaces of padding.
    fn columnWidth(entries: []const *const OwnedEntry) usize {
        var max_word_length: usize = 0;
        for (entries) |entry| {
            if (max_word_length < entry.name.len)
                max_word_length = entry.name.len;
        }

        return max_word_length + 3;
    }

    /// Prints `visible` in short (default, non-`-l`) format.
    ///
    /// In pipe mode, prints one name per line with no column layout. In
    /// terminal mode, lays out entries in a column-major grid (fill order
    /// top-to-bottom within a column, then left-to-right across columns),
    /// sized to fit `config.width`. Column width is currently a single
    /// global max across all entries rather than a true per-column max
    /// (as real `ls` computes) — a known simplification.
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
