const std = @import("std");
const builtin = @import("builtin");

const zdt = @import("zdt");
const Datetime = zdt.Datetime;
const Duration = zdt.Duration;
const Tz = zdt.Timezone;

pub fn main() !void {
    println("---> datetime example", .{});

    println("---> Unix epoch: datetime from timestamp", .{});

    const unix_epoch_naive = try Datetime.fromUnix(0, Duration.Resolution.second, null);
    println("'Unix epoch', naive datetime : {f}", .{unix_epoch_naive});

    var unix_epoch_correct = try Datetime.fromUnix(0, Duration.Resolution.second, .{ .tz = &Tz.UTC });
    println("'Unix epoch', aware datetime : {f}", .{unix_epoch_correct});
    println("'Unix epoch', tz name : {s}", .{unix_epoch_correct.tzName()});

    println("", .{});
    println("---> Now: datetime from system time", .{});

    const now = Datetime.nowUTC();
    println("'now', UTC      : {f}", .{now});
    // println("'now', UTC      : {f:.3} (only ms shown)", .{now}); TODO :

    const now_s = try now.floorTo(Duration.Timespan.second);
    println("(nanos removed) : {f}", .{now_s});

    const now_date = try now.floorTo(Duration.Timespan.day);
    println("           (date) : {f}", .{now_date});
    // println("(date, formatted) : {%Y-%m-%d}", .{now_date}); TODO :
}

fn println(comptime fmt: []const u8, args: anytype) void {
    var stdout = std.fs.File.stdout().writerStreaming(&.{});
    var writer = &stdout.interface;
    writer.print(fmt ++ "\n", args) catch return;
}
