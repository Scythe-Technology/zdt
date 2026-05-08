// SPDX-FileCopyrightText: 2024-2026 Florian Obersteiner
// SPDX-FileContributor: Florian Obersteiner <f.obersteiner@posteo.de>
// SPDX-FileContributor: Michael Pollind <mpollind@gmail.com>
//
// SPDX-License-Identifier: Unlicense

const std = @import("std");
const builtin = @import("builtin");

const zdt = @import("zdt");
const Datetime = zdt.Datetime;
const Duration = zdt.Duration;
const Timezone = zdt.Timezone;

pub fn main(init: std.process.Init) !void {
    const io: std.Io = init.io;
    var stdout: std.Io.File.Writer = std.Io.File.stdout().writerStreaming(io, &.{});

    println(&stdout, "---> duration example", .{});

    const now_utc = Datetime.nowUTC(io);
    println(&stdout, "now, UTC : {f}", .{now_utc});

    const past_midnight = try now_utc.floorTo(.day);

    // difference between two datetimes expressed as Duration:
    println(
        &stdout,
        "{d:.3} seconds have passed since midnight ({f})\n",
        .{ now_utc.diff(past_midnight).totalSeconds(), past_midnight },
    );

    // Durations from Timespans:
    const tomorrow = try now_utc.add(Duration.fromTimespanMultiple(1, .day));
    println(&stdout, "tomorrow, same time : {f}", .{tomorrow});
    println(&stdout, "tomorrow, same time, is {d} seconds away from now\n", .{tomorrow.diff(now_utc).asSeconds()});

    // Timespan units range from nanoseconds to weeks:
    const two_weeks_ago = try now_utc.sub(Duration.fromTimespanMultiple(2, .week));
    println(&stdout, "two weeks ago : {f}", .{two_weeks_ago});

    // ISO8601-duration parser on-board:
    const one_wk_one_h = try Duration.fromISO8601("P7DT1H");
    const in_a_week = try now_utc.add(one_wk_one_h);
    println(&stdout, "in a week and an hour : {f}\n", .{in_a_week});

    // wall-time arithmetic across DST transition using Duration.RelativeDelta:
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var tz_berlin: Timezone = try Timezone.fromTzdata(io, "Europe/Berlin", allocator);
    defer tz_berlin.deinit();

    const delta = try Duration.RelativeDelta.fromISO8601("P1D");
    const dt_dst_off = try Datetime.fromFields(.{ .year = 2024, .month = 3, .day = 30, .hour = 8, .tz_options = .{ .tz = &tz_berlin } });
    const dt_dst_on = try dt_dst_off.addRelative(delta);
    println(&stdout, "{f} --> {f}", .{ dt_dst_off, dt_dst_on });
    println(&stdout, "wall diff: {f}, absolute diff: {f}", .{ try dt_dst_on.diffWall(dt_dst_off), dt_dst_on.diff(dt_dst_off) });
}

fn println(stdout: *std.Io.File.Writer, comptime fmt: []const u8, args: anytype) void {
    var writer = &stdout.interface;
    writer.print(fmt ++ "\n", args) catch return;
}
