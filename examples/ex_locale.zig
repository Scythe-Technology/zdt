// SPDX-FileCopyrightText: 2024-2026 Florian Obersteiner
// SPDX-FileContributor: Florian Obersteiner <f.obersteiner@posteo.de>
// SPDX-FileContributor: Ratakor <45130910+Ratakor@users.noreply.github.com>
//
// SPDX-License-Identifier: Unlicense

const std = @import("std");
const builtin = @import("builtin");

const zdt = @import("zdt");
const Datetime = zdt.Datetime;

extern fn setlocale(__category: c_int, __locale: [*c]const u8) [*c]u8;

pub fn main(init: std.process.Init) !void {
    const io: std.Io = init.io;
    var stdout: std.Io.File.Writer = std.Io.File.stdout().writerStreaming(io, &.{});

    println(&stdout, "---> locale example", .{});

    const time_mask: c_int = switch (builtin.os.tag) {
        .linux, .windows => 6,
        else => 2,
    };

    const loc = "de_DE.UTF-8";
    const new_loc = setlocale(time_mask, loc);
    if (new_loc == null) {
        std.log.err("skip example, failed to set locale", .{});
    }

    const dt = try Datetime.fromISO8601("2024-10-12");

    var buf: [32]u8 = std.mem.zeroes([32]u8);
    var w: std.Io.Writer = .fixed(&buf);

    // datetime to string
    //
    try dt.toString("%a, %b %d %Y, %H:%Mh", &w);
    println(&stdout, "\nformatted {f}\n  to '{s}'", .{ dt, buf });

    w = std.Io.Writer.fixed(&buf);
    try dt.toString("%A, %B %d %Y, %H:%Mh", &w);
    println(&stdout, "\nformatted {f}\n  to '{s}'", .{ dt, buf });

    // string to datetime
    //
    const input = "Mittwoch, 23. Januar 1974, 03:17h";
    const parsed = try Datetime.fromString(input, "%A, %d. %B %Y, %H:%Mh");
    println(&stdout, "\nparsed '{s}'\n  to '{f}'", .{ input, parsed });

    // by adding a modifier character, you can always parse English month names,
    // independent of the locale:
    const input_eng = "Wednesday, January 23 1974, 03:17h";
    const parsed_eng = try Datetime.fromString(input_eng, "%:A, %:B %d %Y, %H:%Mh");
    println(&stdout, "\nparsed '{s}'\n  to '{f}'", .{ input_eng, parsed_eng });
}

fn println(stdout: *std.Io.File.Writer, comptime fmt: []const u8, args: anytype) void {
    var writer = &stdout.interface;
    writer.print(fmt ++ "\n", args) catch return;
}
