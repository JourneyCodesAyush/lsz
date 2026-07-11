//! Entry point for `lsz`, an `ls` clone written in Zig.
//!
//! Parses CLI arguments, resolves terminal width and TTY status, then
//! delegates to `list.zig` for the actual directory-listing logic. Handles
//! both single- and multi-positional-argument invocations, matching the
//! output conventions of real `ls` (directory headers, blank-line
//! separators) where in scope.

const std = @import("std");
const Io = std.Io;

const clap = @import("clap");
const list = @import("list.zig");

const util = @import("utils.zig");
const version = @import("build_zig_zon").version;

/// Process exit codes returned by `lsz`.
const ExitCode = enum(u8) {
    /// Command completed successfully.
    success = 0,
    /// Unspecified runtime failure.
    general_error = 1,
    /// Argument parsing failed (unknown flag, malformed input, etc).
    invalid_argument = 2,
};

pub fn main(init: std.process.Init) !void {
    // CLI schema, parsed at comptime via zig-clap.
    const params = comptime clap.parseParamsComptime(
        \\-h, --help             Display this help and exit
        \\--version              Output version information and exit
        \\-a, --all              Do not ignore entries starting with .
        \\-l, --long             Use long listing format
        \\<str>...               Files or directories to list 
    );

    const allocator = init.arena.allocator();

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, init.minimal.args, .{
        .diagnostic = &diag,
        .allocator = init.gpa,
    }) catch |err| {
        // Report useful error and exit.
        try diag.reportToFile(init.io, .stderr(), err);
        std.process.exit(@intFromEnum(ExitCode.invalid_argument));
    };
    defer res.deinit();

    // Buffered writer over stdout — flushed once on return via `defer`.
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;
    defer stdout_writer.flush() catch {};

    const stdout_file = std.Io.File.stdout();
    // Terminal column width, used for multi-column grid layout. Falls back
    // to 80 on platforms without a native width query (see utils.zig).
    const width = try util.getTerminalSize(stdout_file.handle);

    if (res.args.version != 0) {
        try stdout_writer.print("lsz v{s}", .{version});
        return;
    }

    if (res.args.help != 0)
        // return clap.usageToFile(init.io, .stderr(), clap.Help, &params);
        return clap.helpToFile(init.io, .stderr(), clap.Help, &params, .{});

    // Whether stdout is an interactive terminal (vs. piped/redirected).
    // Determines grid layout (terminal) vs. one-name-per-line (pipe).
    const is_terminal: bool = try Io.File.isTty(.stdout(), init.io);

    const config: list.Config = list.Config{
        .all = res.args.all != 0,
        .output_mode = if (is_terminal) list.OutputMode.terminal else list.OutputMode.pipe,
        .width = width,
        .long = res.args.long != 0,
    };

    const path_count: u64 = res.positionals[0].len;

    var printDirectory: list.PrintDirectoryContents = undefined;
    defer printDirectory.deinit();

    try printDirectory.init(init.io, stdout_writer, allocator, config);

    // No positional args: list the current directory and exit.
    if (path_count == 0) {
        try printDirectory.printDirectories(".");
        return;
    }

    // Tracks whether any output has been printed yet, so we can emit a
    // blank-line separator *between* listings without a trailing blank
    // line after the last one.
    var printed_any: bool = false;
    for (res.positionals[0]) |pos| {
        const stat = Io.Dir.cwd().statFile(init.io, pos, .{}) catch |err| {
            switch (err) {
                error.FileNotFound => {
                    try stdout_writer.print("lsz: '{s}' does not exist\n", .{pos});
                    continue;
                },
                error.AccessDenied => {
                    try stdout_writer.print("lsz: '{s}': access denied\n", .{pos});
                    continue;
                },
                else => return err,
            }
        };
        switch (stat.kind) {
            .directory => {
                // Print a `name:` header only when listing multiple paths,
                // matching real `ls` behavior for single- vs multi-arg
                // invocations.
                if (path_count > 1) {
                    if (printed_any) try stdout_writer.print("\n", .{});
                    try stdout_writer.print("{s}:\n", .{pos});
                    // Reset accumulated entries from the previous directory.
                    // Only called here (not unconditionally per-iteration)
                    // to avoid clearing state before it's ever been
                    // populated, and to avoid an unneeded call for file args.
                    printDirectory.clear();
                }
                try printDirectory.printDirectories(pos);
                printed_any = true;
            },
            .file => {
                try stdout_writer.print("{s}\n", .{pos});
                printed_any = true;
            },
            else => {
                try stdout_writer.print("{s}\n", .{pos});
                printed_any = true;
            },
        }
    }
}
