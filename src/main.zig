const std = @import("std");
const Io = std.Io;

const clap = @import("clap");
const list = @import("list.zig");

const util = @import("utils.zig");
const version = @import("build_zig_zon").version;

const ExitCode = enum(u8) {
    success = 0,
    general_error = 1,
    invalid_argument = 2,
};

pub fn main(init: std.process.Init) !void {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help             Display this help and exit
        \\--version              Output version information and exit
        \\-a, --all              Do not ignore entries starting with .
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

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;
    defer stdout_writer.flush() catch {};

    const width = try util.getTerminalSize();

    if (res.args.version != 0) {
        try stdout_writer.print("lsz v{s}", .{version});
        return;
    }

    if (res.args.help != 0)
        // return clap.usageToFile(init.io, .stderr(), clap.Help, &params);
        return clap.helpToFile(init.io, .stderr(), clap.Help, &params, .{});

    const is_terminal: bool = try Io.File.isTty(.stdout(), init.io);

    const config: list.Config = list.Config{
        .all = res.args.all != 0,
        .output_mode = if (is_terminal) list.OutputMode.terminal else list.OutputMode.pipe,
        .width = width,
    };

    const path_count: u64 = res.positionals[0].len;

    var printDirectory: list.PrintDirectoryContents = undefined;
    defer printDirectory.deinit();

    try printDirectory.init(init.io, stdout_writer, allocator, config);

    if (path_count == 0) {
        try printDirectory.printDirectories(".");
        return;
    }

    for (res.positionals[0]) |pos| {
        const stat = try Io.Dir.cwd().statFile(init.io, pos, .{});
        switch (stat.kind) {
            .directory => {
                if (path_count > 1)
                    try stdout_writer.print("\n\n{s}\n", .{pos});
                try printDirectory.printDirectories(pos);
            },
            .file => try stdout_writer.print("{s}\n", .{pos}),
            else => try stdout_writer.print("{s}\n", .{pos}),
        }
    }
}
