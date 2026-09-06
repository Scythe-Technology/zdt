// SPDX-FileCopyrightText: 2023-2026 Florian Obersteiner
// SPDX-FileContributor: Florian Obersteiner <f.obersteiner@posteo.de>
//
// SPDX-License-Identifier: Unlicense

//! integration tests: interactions between the core types
//! (Datetime <-> Duration, Datetime <-> Duration <-> Timezone).
//!
//! Convention: tests that primarily exercise ONE type live in that type's
//! test file (test_Datetime.zig, test_Duration.zig, test_Timezone.zig).
//! Tests that need two or more core types in a non-trivial way belong here,
//! so that the per-type test files don't have to reach into each other's
//! territory. Note that test_Timezone.zig necessarily uses Datetime as a
//! fixture (a time zone can't be tested without datetimes) -- that is fine;
//! what belongs here are tests whose *subject* is the interaction itself.

const std = @import("std");
const testing = std.testing;
const log = std.log.scoped(.test_integration);

const zdt = @import("zdt");
const Datetime = zdt.Datetime;
const Duration = zdt.Duration;
const Tz = zdt.Timezone;

const ns_per_s: i96 = 1_000_000_000;
const s_per_day: i96 = 86_400;

test "add duration to datetime" {
    var dt = try Datetime.fromFields(.{ .year = 1970, .second = 42 });
    var dt_want = try Datetime.fromFields(.{ .year = 1970, .second = 43 });
    dt = try dt.add(Duration{ .__nsec = ns_per_s });
    try testing.expectEqual(@as(i64, 43), dt.unix_sec);
    try testing.expectEqual(dt_want, dt);

    dt = try dt.add(Duration{ .__nsec = -ns_per_s });
    dt_want = try Datetime.fromFields(.{ .year = 1970, .second = 42 });
    try testing.expectEqual(@as(i64, 42), dt.unix_sec);
    try testing.expectEqual(dt_want, dt);

    dt = try dt.add(try Duration.fromTimespanMultiple(1, .week));
    try testing.expectEqual(@as(u8, 8), dt.day);

    const err = dt.add(try Duration.fromTimespanMultiple((1 << 32) - 1, .week));
    try testing.expectError(error.UnixOutOfRange, err);
}

test "subtract duration from datetime" {
    var dt = try Datetime.fromFields(.{ .year = 1970, .second = 42 });
    dt = try dt.sub(Duration{ .__nsec = -ns_per_s });
    try testing.expectEqual(@as(i64, 43), dt.unix_sec);

    dt = try dt.sub(Duration{ .__nsec = ns_per_s });
    try testing.expectEqual(@as(i64, 42), dt.unix_sec);

    try testing.expectEqual(@as(u32, 0), dt.nanosecond);

    const err = dt.sub(try Duration.fromTimespanMultiple((1 << 32) - 1, .week));
    try testing.expectError(error.UnixOutOfRange, err);
}

test "datetime difference" {
    var a = try Datetime.fromFields(.{ .year = 1970, .second = 1 });
    var b = try Datetime.fromFields(.{ .year = 1970, .second = 1 });
    var diff = a.diff(b);
    try testing.expectEqual(@as(i96, 0), diff.__nsec);

    a = try Datetime.fromFields(.{ .year = 1970, .second = 0 });
    b = try Datetime.fromFields(.{ .year = 1970, .second = 1 });
    diff = a.diff(b);
    try testing.expectEqual(-ns_per_s, diff.__nsec);

    diff = b.diff(a);
    try testing.expectEqual(ns_per_s, diff.__nsec);

    a = try Datetime.fromUnix(Datetime.unix_s_min, .second, null);
    b = try Datetime.fromUnix(Datetime.unix_s_max, .second, null);

    // just ensure that this works and isn't out-of-range for the duration:
    diff = a.diff(b);
}

test "leap second difference" {
    var a = try Datetime.fromISO8601("1972-06-30");
    var b = try Datetime.fromISO8601("1972-07-01");
    var leaps = a.diffLeap(b);
    try testing.expectEqual(-ns_per_s, leaps.__nsec);

    var diff = a.diff(b);
    diff = try diff.add(leaps);
    try testing.expectEqual(-ns_per_s * (s_per_day + 1), diff.__nsec);

    a = try Datetime.fromISO8601("1973-01-01");
    b = try Datetime.fromISO8601("1972-06-30");
    leaps = a.diffLeap(b);
    try testing.expectEqual(2 * ns_per_s, leaps.__nsec);

    a = try Datetime.fromISO8601("1970-01-01");
    b = try Datetime.fromISO8601("2024-01-01");
    leaps = a.diffLeap(b);
    try testing.expectEqual(-27 * ns_per_s, leaps.__nsec);

    a = try Datetime.fromISO8601("2024-01-01");
    b = try Datetime.fromISO8601("2016-12-31"); // before last leap second insertion
    leaps = a.diffLeap(b);
    try testing.expectEqual(ns_per_s, leaps.__nsec);

    a = try Datetime.fromISO8601("2024-10-01");
    b = try Datetime.fromISO8601("2024-10-02");
    leaps = a.diffLeap(b);
    try testing.expectEqual(0, leaps.__nsec);

    diff = a.diff(b);
    diff = try diff.add(leaps);
    try testing.expectEqual(-ns_per_s * s_per_day, diff.__nsec);
}

test "add/sub duration to datetime with UTC offset" {
    const dt = try Datetime.fromISO8601("2026-08-01T12:00:00+02:00");
    try testing.expect(dt.isAware());

    const one_hour = try Duration.fromTimespanMultiple(1, Duration.Timespan.hour);

    var buf: [64]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);

    var result = try dt.add(one_hour);
    try testing.expect(result.isAware());
    try result.format(&w);
    try testing.expectEqualStrings("2026-08-01T13:00:00+02:00", w.buffered());

    w = .fixed(&buf);
    result = try dt.sub(one_hour);
    try testing.expect(result.isAware());
    try result.format(&w);
    try testing.expectEqualStrings("2026-08-01T11:00:00+02:00", w.buffered());
}

test "addRelative to datetime with UTC offset" {
    const dt = try Datetime.fromISO8601("2026-08-01T12:00:00+02:00");

    var result = try dt.addRelative(.{ .days = 1 });
    try testing.expect(result.isAware());

    var buf: [64]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try result.format(&w);
    try testing.expectEqualStrings("2026-08-02T12:00:00+02:00", w.buffered());

    w = .fixed(&buf);
    result = try dt.addRelative(.{ .months = 1 });
    try testing.expect(result.isAware());
    try result.format(&w);
    try testing.expectEqualStrings("2026-09-01T12:00:00+02:00", w.buffered());
}

test "add duration to naive datetime stays naive" {
    const dt = try Datetime.fromFields(.{ .year = 2026, .month = 8, .day = 1, .hour = 12 });
    const one_hour = try Duration.fromTimespanMultiple(1, Duration.Timespan.hour);
    const result = try dt.add(one_hour);
    try testing.expect(result.isNaive());
    try testing.expectEqual(@as(u8, 13), result.hour);
}

test "add relative delta to aware datetime" {
    var tz = try Tz.fromTzdata(testing.io, "Europe/Berlin", testing.allocator);
    defer tz.deinit();

    var have: Datetime = try Datetime.fromFields(.{ .year = 1970, .tz_options = .{ .tz = &tz } });
    var delta: Duration.RelativeDelta = try Duration.RelativeDelta.fromISO8601("P1Y");
    var want: Datetime = try Datetime.fromFields(.{ .year = 1971, .tz_options = .{ .tz = &tz } });
    var new: Datetime = try have.addRelative(delta);
    try testing.expectEqual(want, new);
    delta.negative = true;
    new = try want.addRelative(delta);
    try testing.expectEqual(have, new);

    // 23 hours absolute is 1 day relative during DST off --> on
    have = try Datetime.fromFields(.{ .year = 2024, .month = 3, .day = 30, .hour = 8, .tz_options = .{ .tz = &tz } });
    delta = try Duration.RelativeDelta.fromISO8601("P1D");
    want = try Datetime.fromFields(.{ .year = 2024, .month = 3, .day = 31, .hour = 8, .tz_options = .{ .tz = &tz } });
    new = try have.addRelative(delta);
    try testing.expectEqual(want, new);
    var abs_diff: Duration = new.diff(have);
    var wall_diff: Duration = try new.diffWall(have);
    try testing.expectEqual(try Duration.fromISO8601("PT23H"), abs_diff);
    try testing.expectEqual(try Duration.fromISO8601("PT24H"), wall_diff);
    delta.negative = true;
    new = try want.addRelative(delta);
    try testing.expectEqual(have, new);

    // 25 hours absolute is 1 day relative during DST on --> off
    have = try Datetime.fromFields(.{ .year = 2024, .month = 10, .day = 26, .hour = 8, .tz_options = .{ .tz = &tz } });
    delta = try Duration.RelativeDelta.fromISO8601("P1D");
    want = try Datetime.fromFields(.{ .year = 2024, .month = 10, .day = 27, .hour = 8, .tz_options = .{ .tz = &tz } });
    new = try have.addRelative(delta);
    try testing.expectEqual(want, new);
    abs_diff = new.diff(have);
    wall_diff = try new.diffWall(have);
    try testing.expectEqual(try Duration.fromISO8601("PT25H"), abs_diff);
    try testing.expectEqual(try Duration.fromISO8601("PT24H"), wall_diff);
    delta.negative = true;
    new = try want.addRelative(delta);
    try testing.expectEqual(have, new);
}
