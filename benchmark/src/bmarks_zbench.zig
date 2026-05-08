// SPDX-FileCopyrightText: 2025-2026 Florian Obersteiner
// SPDX-FileContributor: Florian Obersteiner <f.obersteiner@posteo.de>
//
// SPDX-License-Identifier: Unlicense

const std = @import("std");
const config = @import("config.zig");

const zeit = @import("zeit");

const zbench = @import("zbench");
const zdt_latest = @import("zdt_current");

var gpa = std.heap.DebugAllocator(.{}){};

// -------- ISO ------------------------------------------------------------------------------------
// parse an ISO8601 formatted string to a datetime

fn benchParseISOlatest(_: std.mem.Allocator) void {
    _ = zdt_latest.Datetime.fromISO8601(config.str) catch unreachable;
}

fn benchParseISOstrplatest(_: std.mem.Allocator) void {
    _ = zdt_latest.Datetime.fromString(config.str, config.directive) catch unreachable;
}

const benchParseISOzeitInst = struct {
    io: std.Io,
    pub fn run(self: *benchParseISOzeitInst, _: std.mem.Allocator) void {
        // only make an instant
        _ = zeit.instant(self.io, .{ .source = .{ .iso8601 = config.str } }) catch unreachable;
    }
};
//
const benchParseISOzeit = struct {
    io: std.Io,
    pub fn run(self: *benchParseISOzeit, _: std.mem.Allocator) void {
        // make an instant and convert to datetime
        const t = zeit.instant(self.io, .{ .source = .{ .iso8601 = config.str } }) catch unreachable;
        _ = t.time();
    }
};

// -------- MEMORY --------------------------------------------------------------------------------
// make a datetime in a timezone

const benchZonedZdt = struct {
    io: std.Io,
    pub fn run(self: *benchZonedZdt, allocator: std.mem.Allocator) void {
        var mytz: zdt_latest.Timezone = zdt_latest.Timezone.fromTzdata(self.io, "Europe/Berlin", allocator) catch unreachable;
        defer mytz.deinit();
        _ = zdt_latest.Datetime.now(self.io, .{ .tz = &mytz }) catch unreachable;
    }
};

const benchZonedZdtNoAlloc = struct {
    io: std.Io,
    pub fn run(self: *benchZonedZdtNoAlloc, _: std.mem.Allocator) void {
        var mytz: zdt_latest.Timezone = zdt_latest.Timezone.fromTzdata(self.io, "Europe/Berlin", null) catch unreachable;
        _ = zdt_latest.Datetime.now(self.io, .{ .tz = &mytz }) catch unreachable;
    }
};

const benchZonedZeit = struct {
    io: std.Io,
    pub fn run(self: *benchZonedZeit, allocator: std.mem.Allocator) void {
        const now = zeit.instant(self.io, .{}) catch unreachable;
        const zone = zeit.loadTimeZone(allocator, self.io, .@"Europe/Berlin", .{}) catch unreachable;
        const now_local = now.in(&zone);
        _ = now_local.time();
    }
};

// -------- EASTER --------------------------------------------------------------------------------

fn benchEasterLatest(_: std.mem.Allocator) void {
    _ = zdt_latest.Datetime.EasterDate(2025) catch unreachable;
}

fn benchEasterJulLatest(_: std.mem.Allocator) void {
    _ = zdt_latest.Datetime.EasterDateJulian(2025) catch unreachable;
}

pub fn run(io: std.Io) !void {
    const stdout: std.Io.File = .stdout();

    var bench = zbench.Benchmark.init(gpa.allocator(), .{});
    defer bench.deinit();

    try bench.add("iso zdt", benchParseISOlatest, .{ .iterations = config.N });
    try bench.add("iso zdt strp", benchParseISOstrplatest, .{ .iterations = config.N });

    const _benchParseISOzeitInst = benchParseISOzeitInst{ .io = io };
    try bench.addParam("iso zeit 0.8 inst", &_benchParseISOzeitInst, .{ .iterations = config.N });
    const _benchParseISOzeit = benchParseISOzeit{ .io = io };
    try bench.addParam("iso zeit 0.8 full", &_benchParseISOzeit, .{ .iterations = config.N });

    try bench.add("Easter dt zdt", benchEasterLatest, .{ .iterations = config.N });
    try bench.add("Easter JL zdt", benchEasterJulLatest, .{ .iterations = config.N });

    const _benchZonedZdt = benchZonedZdt{ .io = io };
    try bench.addParam("Zoned local, zdt", &_benchZonedZdt, .{ .iterations = 1000 });
    try bench.addParam("Zoned local, zdt", &_benchZonedZdt, .{ .iterations = 1000, .track_allocations = true });
    const _benchZonedZdtNoAlloc = benchZonedZdtNoAlloc{ .io = io };
    try bench.addParam("(Zero-Alloc) zdt", &_benchZonedZdtNoAlloc, .{ .iterations = 1000 });

    const _benchZonedZeit = benchZonedZeit{ .io = io };
    try bench.addParam("Zoned local, zeit", &_benchZonedZeit, .{ .iterations = 1000 });
    try bench.addParam("Zoned local, zeit", &_benchZonedZeit, .{ .iterations = 1000, .track_allocations = true });

    try bench.run(io, stdout);

    std.debug.print("\n", .{});
}
