// SPDX-FileCopyrightText: 2024-2026 Florian Obersteiner
// SPDX-FileContributor: Florian Obersteiner <f.obersteiner@posteo.de>
// SPDX-FileContributor: Michael Pollind <mpollind@gmail.com>
//
// SPDX-License-Identifier: Unlicense

const std = @import("std");
const builtin = @import("builtin");
const zdt = @import("zdt");

pub fn main(init: std.process.Init) !void {
    // Can use an allocator for the time zones as the size of the rule-files varies.
    const allocator = init.arena.allocator();
    const io = init.io;

    // zdt embeds the IANA tz database (about 700k of raw data).
    // If you pass 'null' instead of the allocator, a fixed-size structure will be used,
    // see ex_timezones.zig - this is faster, but requires more memory.
    var tz_LA = try zdt.Timezone.fromTzdata(io, "America/Los_Angeles", allocator);
    defer tz_LA.deinit();

    // You can also use your system's tz data at runtime;
    // this will very likely not work on Windows, so we use the embedded version here as well.
    var tz_Paris = switch (builtin.os.tag) {
        .windows => try zdt.Timezone.fromTzdata(io, "Europe/Paris", allocator),
        else => try zdt.Timezone.fromSystemTzdata(io, "Europe/Paris", zdt.Timezone.tzdb_prefix, allocator),
    };
    defer tz_Paris.deinit();

    // ISO8601 parser on-board, accepts wide variety of compatible formats
    const a_datetime = try zdt.Datetime.fromISO8601("2022-03-07");
    const this_time_LA = try a_datetime.tzLocalize(.{ .tz = &tz_LA });

    // string output requires buffer memory...
    var buf = std.mem.zeroes([16]u8);
    var w: std.Io.Writer = .fixed(&buf);
    try this_time_LA.toString("%I %p, %Z", &w);

    const this_time_Paris: zdt.Datetime = try this_time_LA.tzConvert(.{ .tz = &tz_Paris });

    // '{f}' directive gives ISO8601 format by default;
    std.debug.print(
        "Time, LA : {f} ({s})\n... that's {f} in Paris ({s})\n\n",
        // we can also print the buffer from above:
        .{ this_time_LA, buf, this_time_Paris, this_time_Paris.tzAbbreviation() },
    );
    // Time, LA : 2022-03-07T00:00:00-08:00 (12 am, PST)
    // ... that's 2022-03-07T09:00:00+01:00 in Paris

    const wall_diff: zdt.Duration = try this_time_Paris.diffWall(this_time_LA);
    const abs_diff: zdt.Duration = this_time_Paris.diff(this_time_LA);

    std.debug.print("Wall clock time difference: {f}\nAbsolute time difference: {f}\n\n", .{ wall_diff, abs_diff });
    // Wall clock time difference: PT9H
    // Absolute time difference: PT0S

    // Easteregg:
    std.debug.print(
        "Easter this year is on {f}\n",
        .{try zdt.Datetime.EasterDate(zdt.Datetime.nowUTC(io).year)},
    );
    // Easter this year is on 2026-04-05T00:00:00
}
