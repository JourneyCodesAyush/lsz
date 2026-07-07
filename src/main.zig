const std = @import("std");
const Io = std.Io;

const clap = @import("clap");
const list = @import("list.zig");

pub fn main(init: std.process.Init) !void {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help             Display this help and exit
        \\<str>...               Files or directories to list 
    );

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
        return clap.helpToFile(init.io, .stderr(), clap.Help, &params, .{});

    if (res.positionals.len == 0) {
        try list.printDirectories(".", init.io);
    }

    for (res.positionals[0]) |pos| {
        const stat = try std.Io.Dir.cwd().statFile(init.io, pos, .{});
        switch (stat.kind) {
            .directory => {
                std.debug.print("\n\n{s}\n", .{pos});
                try list.printDirectories(pos, init.io);
            },
            .file => std.debug.print("{s}\n", .{pos}),
            else => std.debug.print("{s}\n", .{pos}),
        }
    }
}
