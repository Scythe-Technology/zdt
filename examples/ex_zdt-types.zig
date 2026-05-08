// SPDX-FileCopyrightText: 2024-2026 Florian Obersteiner
// SPDX-FileContributor: Florian Obersteiner <f.obersteiner@posteo.de>
//
// SPDX-License-Identifier: Unlicense

const std = @import("std");
const builtin = @import("builtin");

const zdt = @import("zdt");
const Datetime = zdt.Datetime;
const Duration = zdt.Duration;
const Timezone = zdt.Timezone;
const UTCoffset = zdt.UTCoffset;

pub fn main(init: std.process.Init) !void {
    const io: std.Io = init.io;
    var stdout: std.Io.File.Writer = std.Io.File.stdout().writerStreaming(io, &.{});

    println(&stdout, "OS: {s}, architecture: {s}", .{ @tagName(builtin.os.tag), @tagName(builtin.cpu.arch) });
    println(&stdout, "Zig version: {s}\n", .{builtin.zig_version_string});

    println(&stdout, "---> Datetime", .{});
    println(&stdout, "size of {s}: {} bytes", .{ @typeName(Datetime), @sizeOf(Datetime) });
    inline for (std.meta.fields(Datetime)) |field| {
        println(&stdout, "  field {s} byte offset: {}", .{ field.name, @offsetOf(Datetime, field.name) });
    }

    println(&stdout, "\n---> Duration", .{});
    println(&stdout, "size of {s}: {} bytes", .{ @typeName(Duration), @sizeOf(Duration) });
    inline for (std.meta.fields(Duration)) |field| {
        println(&stdout, "  field {s} byte offset: {}", .{ field.name, @offsetOf(Duration, field.name) });
    }

    println(&stdout, "\n---> Timezone", .{});
    println(&stdout, "size of {s}: {} bytes", .{ @typeName(Timezone), @sizeOf(Timezone) });
    inline for (std.meta.fields(Timezone)) |field| {
        println(&stdout, "  field {s} byte offset: {}", .{ field.name, @offsetOf(Timezone, field.name) });
    }

    println(&stdout, "\n---> Timezone Database", .{});
    println(&stdout, "  {d} bytes", .{Timezone.sizeOfTZdata()});

    println(&stdout, "\n---> UTCoffset", .{});
    println(&stdout, "size of {s}: {} bytes", .{ @typeName(UTCoffset), @sizeOf(UTCoffset) });
    inline for (std.meta.fields(UTCoffset)) |field| {
        println(&stdout, "  field {s} byte offset: {}", .{ field.name, @offsetOf(UTCoffset, field.name) });
    }
}

fn println(stdout: *std.Io.File.Writer, comptime fmt: []const u8, args: anytype) void {
    var writer = &stdout.interface;
    writer.print(fmt ++ "\n", args) catch return;
}
