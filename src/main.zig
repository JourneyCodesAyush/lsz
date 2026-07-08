const std = @import("std");
const Io = std.Io;

const clap = @import("clap");
const list = @import("list.zig");

pub fn main(init: std.process.Init) !void {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help             Display this help and exit
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
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0)
        // return clap.usageToFile(init.io, .stderr(), clap.Help, &params);
        return clap.helpToFile(init.io, .stderr(), clap.Help, &params, .{});

    const config: list.Config = list.Config{ .all = res.args.all != 0 };

    const path_count: u64 = res.positionals[0].len;

    var printDirectory: list.PrintDirectoryContents = undefined;
    defer printDirectory.deinit();

    try printDirectory.init(init.io, allocator, config);

    if (path_count == 0) {
        try printDirectory.printDirectories(".");
        return;
    }

    for (res.positionals[0]) |pos| {
        const stat = try std.Io.Dir.cwd().statFile(init.io, pos, .{});
        switch (stat.kind) {
            .directory => {
                if (path_count > 1)
                    std.debug.print("\n\n{s}\n", .{pos});
                try printDirectory.printDirectories(pos);
            },
            .file => std.debug.print("{s}\n", .{pos}),
            else => std.debug.print("{s}\n", .{pos}),
        }
    }
}
