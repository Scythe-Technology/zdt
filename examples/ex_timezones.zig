// SPDX-FileCopyrightText: 2024-2026 Florian Obersteiner
// SPDX-FileContributor: Florian Obersteiner <f.obersteiner@posteo.de>
// SPDX-FileContributor: Michael Pollind <mpollind@gmail.com>
//
// SPDX-License-Identifier: Unlicense

const std = @import("std");
const builtin = @import("builtin");

const zdt = @import("zdt");
const Datetime = zdt.Datetime;
const Timezone = zdt.Timezone;

pub fn main(init: std.process.Init) !void {
    const io: std.Io = init.io;
    var stdout: std.Io.File.Writer = std.Io.File.stdout().writerStreaming(io, &.{});

    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    println(&stdout, "---> time zones example", .{});

    println(&stdout, "IANA time zone database version: {s}", .{Timezone.tzdb_version});
    println(&stdout, "path to local tz database: {s}\n", .{Timezone.tzdb_prefix});

    println(&stdout, "load timezone, dynamically allocated memory:", .{});
    var tz_berlin: Timezone = try Timezone.fromTzdata(io, "Europe/Berlin", allocator);
    defer tz_berlin.deinit();
    println(&stdout, "Info: {f}", .{tz_berlin});
    var now_berlin: Datetime = try Datetime.now(io, .{ .tz = &tz_berlin });
    const now_utc: Datetime = Datetime.nowUTC(io);
    println(&stdout, "Now, UTC time    : {f}", .{now_utc});
    println(&stdout, "Now, Berlin time : {f} ({s})", .{ now_berlin, now_berlin.tzAbbreviation() });
    println(&stdout, "Datetimes have UTC offset / time zone? : {}, {}\n", .{ now_utc.isAware(), now_berlin.isAware() });

    println(&stdout, "load timezone, static memory:", .{});
    const tz_berlin_: Timezone = try Timezone.fromTzdata(io, "Europe/Berlin", null);
    println(&stdout, "Info: {f}", .{tz_berlin_});
    const now_berlin_: Datetime = try Datetime.now(io, .{ .tz = &tz_berlin_ });
    println(&stdout, "Now, Berlin time : {f} ({s})\n", .{ now_berlin_, now_berlin_.tzAbbreviation() });

    var my_tz: Timezone = try Timezone.tzLocal(io, allocator);
    defer my_tz.deinit();
    var now_local = try now_berlin.tzConvert(.{ .tz = &my_tz });
    println(&stdout, "My time zone : {s}", .{my_tz.name()});

    println(&stdout, "Now, my time zone : {f} ({s})\n", .{ now_local, now_local.tzAbbreviation() });

    var tz_ny = try Timezone.fromTzdata(io, "America/New_York", allocator);
    defer tz_ny.deinit();
    var now_ny: Datetime = try now_local.tzConvert(.{ .tz = &tz_ny });
    println(&stdout, "Now in New York : {f} ({s})", .{ now_ny, now_ny.tzAbbreviation() });
    println(&stdout, "Wall time difference, local vs. NY: {f}\n", .{try now_ny.diffWall(now_local)});

    println(&stdout, "New York has DST currently? : {}", .{now_ny.isDST()});
    const ny_summer_2023: Datetime = try Datetime.fromFields(.{
        .year = 2023,
        .month = 8,
        .tz_options = .{ .tz = &tz_ny },
    });
    println(&stdout, "New York, summer : {f} ({s})", .{ ny_summer_2023, ny_summer_2023.tzAbbreviation() });
    const ny_winter_2023: Datetime = try Datetime.fromFields(.{
        .year = 2023,
        .month = 12,
        .tz_options = .{ .tz = &tz_ny },
    });
    println(&stdout, "New York, winter : {f} ({s})", .{ ny_winter_2023, ny_winter_2023.tzAbbreviation() });
    println(&stdout, "New York has DST in summer? : {}\n", .{ny_summer_2023.isDST()});

    // non-existing datetime: DST gap
    // always errors:
    const err_ne = Datetime.fromFields(.{ .year = 2024, .month = 3, .day = 10, .hour = 2, .minute = 30, .tz_options = .{ .tz = &tz_ny } });
    println(&stdout, "Attempt to create non-existing datetime: {any}", .{err_ne});

    // ambiguous datetime: DST fold
    // errors if 'dst_fold' is undefined:
    const err_amb = Datetime.fromFields(.{
        .year = 2024,
        .month = 11,
        .day = 3,
        .hour = 1,
        .minute = 30,
        .tz_options = .{ .tz = &tz_ny },
    });
    println(&stdout, "Attempt to create ambiguous datetime: {any}", .{err_amb});

    // we can specify on which side of the fold the datetime should fall:
    const amb_dt_early = try Datetime.fromFields(.{
        .year = 2024,
        .month = 11,
        .day = 3,
        .hour = 1,
        .minute = 30,
        .dst_fold = 0,
        .tz_options = .{ .tz = &tz_ny },
    });
    println(&stdout, "Ambiguous datetime, early side of fold: {f}", .{amb_dt_early});

    const amb_dt_late = try Datetime.fromFields(.{
        .year = 2024,
        .month = 11,
        .day = 3,
        .hour = 1,
        .minute = 30,
        .dst_fold = 1,
        .tz_options = .{ .tz = &tz_ny },
    });
    println(&stdout, "Ambiguous datetime, late side of fold: {f}", .{amb_dt_late});
}

fn println(stdout: *std.Io.File.Writer, comptime fmt: []const u8, args: anytype) void {
    var writer = &stdout.interface;
    writer.print(fmt ++ "\n", args) catch return;
}
