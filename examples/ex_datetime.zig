// SPDX-FileCopyrightText: 2024-2026 Florian Obersteiner
// SPDX-FileContributor: Florian Obersteiner <f.obersteiner@posteo.de>
//
// SPDX-License-Identifier: Unlicense

const std = @import("std");
const builtin = @import("builtin");

const zdt = @import("zdt");
const Datetime = zdt.Datetime;
const Duration = zdt.Duration;
const Tz = zdt.Timezone;

pub fn main(init: std.process.Init) !void {
    const io: std.Io = init.io;
    var stdout: std.Io.File.Writer = std.Io.File.stdout().writerStreaming(io, &.{});

    println(&stdout, "---> datetime example", .{});

    println(&stdout, "---> Unix epoch: datetime from timestamp", .{});

    const unix_epoch_naive = try Datetime.fromUnix(0, Duration.Resolution.second, null);
    println(&stdout, "'Unix epoch', naive datetime : {f}", .{unix_epoch_naive});

    var unix_epoch_correct = try Datetime.fromUnix(0, Duration.Resolution.second, .{ .tz = &Tz.UTC });
    println(&stdout, "'Unix epoch', aware datetime : {f}", .{unix_epoch_correct});
    println(&stdout, "'Unix epoch', tz name : {s}\n", .{unix_epoch_correct.tzName()});

    println(&stdout, "---> Now: datetime from system's time", .{});

    // we can directly write to stdout with the 'toString' method:
    const now = Datetime.nowUTC(io);
    const now_tai = Datetime.nowTAI(io);

    try now.toString("'now', UTC      : %T\n", &stdout.interface);
    try now_tai.toString("'now', TAI      : %T\n", &stdout.interface);
    try now.toString("'now', UTC      : %Y-%m-%dT%H:%M:%S.%:f%:Z (only ms shown)\n", &stdout.interface);

    const now_s = try now.floorTo(Duration.Timespan.second);
    println(&stdout, "(nanos removed) : {f}", .{now_s});

    const now_date = try now.floorTo(Duration.Timespan.day);
    try now_date.toString("(date only)     : %Y-%m-%d\n", &stdout.interface);
}

fn println(stdout: *std.Io.File.Writer, comptime fmt: []const u8, args: anytype) void {
    var writer = &stdout.interface;
    writer.print(fmt ++ "\n", args) catch return;
}
