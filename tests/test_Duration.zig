// SPDX-FileCopyrightText: 2024-2025 Florian Obersteiner
// SPDX-FileContributor: Florian Obersteiner <f.obersteiner@posteo.de>
// SPDX-FileContributor: Michael Pollind <mpollind@gmail.com>
//
// SPDX-License-Identifier: Unlicense

//! test duration from a users's perspective (no internal functionality)

const std = @import("std");
const testing = std.testing;

const zdt = @import("zdt");
const Datetime = zdt.Datetime;
const Duration = zdt.Duration;
const Timezone = zdt.Timezone;

const log = std.log.scoped(.test_duration);

test "from timespan" {
    var td = Duration.fromTimespanMultiple(5, .nanosecond);
    try testing.expectEqual(@as(i128, 5), td.asNanoseconds());

    td = Duration.fromTimespanMultiple(32, .second);
    try testing.expectEqual(@as(i128, 32E9), td.asNanoseconds());
    try testing.expectEqual(@as(i64, 32), td.asSeconds());

    td = Duration.fromTimespanMultiple(1, .week);
    try testing.expectEqual(@as(i64, 7 * 24 * 60 * 60), td.asSeconds());
}

test "to timespan" {
    var td = Duration.fromTimespanMultiple(5, .nanosecond);
    try testing.expectEqual(@as(i128, 5), td.asNanoseconds());

    const ns = td.toTimespanMultiple(.nanosecond);
    try testing.expectEqual(@as(i128, 5), ns);

    const weeks = td.toTimespanMultiple(.week);
    try testing.expectEqual(@as(i128, 1), weeks);

    td = Duration.fromTimespanMultiple(5500, .microsecond);
    var ms = td.toTimespanMultiple(.millisecond);
    try testing.expectEqual(@as(i128, 6), ms);

    td = Duration.fromTimespanMultiple(5501, .microsecond);
    ms = td.toTimespanMultiple(.millisecond);
    try testing.expectEqual(@as(i128, 6), ms);
}

test "edge cases, min-max" {
    var td = Duration{ .__sec = Duration.max_sec, .__nsec = 999_999_999 };
    const want_max: i128 = 170141183460469231731687303714999999999;
    try testing.expectEqual(Duration.max_sec + 1, td.asSeconds());
    try testing.expectEqual(want_max, td.asNanoseconds());
    try testing.expectEqual(want_max, td.toTimespanMultiple(.nanosecond));

    td = Duration{ .__sec = Duration.min_sec, .__nsec = 0 };
    const want_min = -170141183460469231731687303715000000000;
    try testing.expectEqual(Duration.min_sec, td.asSeconds());
    try testing.expectEqual(want_min, td.asNanoseconds());
    try testing.expectEqual(want_min, td.toTimespanMultiple(.nanosecond));

    const want_max_weeks: i64 = 9223372036854775807;
    td = Duration.fromTimespanMultiple(want_max_weeks, .week);
    try testing.expectEqual(want_max_weeks, td.toTimespanMultiple(.week));

    const want_min_weeks = -9223372036854775808;
    td = Duration.fromTimespanMultiple(want_min_weeks, .week);
    try testing.expectEqual(want_min_weeks, td.toTimespanMultiple(.week));
}

test "format" {
    var buf: [64]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);

    // fraction zeros get truncated
    const d = try Duration.fromISO8601("PT0.123450000S");
    try d.format(&w);
    try testing.expectEqualStrings("PT0.12345S", w.buffered());
}

test "total seconds" {
    // Regular case
    const td = Duration.fromTimespanMultiple(3141592653, .nanosecond);
    try testing.expectEqual(3.141592653, td.totalSeconds());

    // Test large positive value
    const large_td = Duration.fromTimespanMultiple(9223372036854775807, .second);
    try testing.expectEqual(9223372036854775807.0, large_td.totalSeconds());

    // Test large negative value
    const neg_td = Duration.fromTimespanMultiple(-9223372036854775807, .second);
    try testing.expectEqual(-9223372036854775807.0, neg_td.totalSeconds());
}

test "total minutes" {
    // Regular case
    const td = Duration.fromTimespanMultiple(185, .second);
    try testing.expectEqual(3.0833333333333335, td.totalMinutes());

    // Test large positive value
    const large_td = Duration.fromTimespanMultiple(9223372036854775807, .second);
    try testing.expectEqual(9223372036854775807.0 / 60.0, large_td.totalMinutes());

    // Test large negative value
    const neg_td = Duration.fromTimespanMultiple(-9223372036854775807, .second);
    try testing.expectEqual(-9223372036854775807.0 / 60.0, neg_td.totalMinutes());
}

test "total hours" {
    // Regular case
    const td = Duration.fromTimespanMultiple(6300, .second);
    try testing.expectEqual(1.75, td.totalHours());

    // Test large positive value
    const large_td = Duration.fromTimespanMultiple(9223372036854775807, .second);
    try testing.expectEqual(9223372036854775807.0 / 3600.0, large_td.totalHours());

    // Test large negative value
    const neg_td = Duration.fromTimespanMultiple(-9223372036854775807, .second);
    try testing.expectEqual(-9223372036854775807.0 / 3600.0, neg_td.totalHours());
}

test "total days" {
    // Regular case
    const td = Duration.fromTimespanMultiple(3, .day);
    try testing.expectEqual(3.0, td.totalDays());

    // Test large positive value
    const large_td = Duration.fromTimespanMultiple(9223372036854775807, .second);
    try testing.expectEqual(9223372036854775807.0 / 86400.0, large_td.totalDays());

    // Test large negative value
    const neg_td = Duration.fromTimespanMultiple(-9223372036854775807, .second);
    try testing.expectEqual(-9223372036854775807.0 / 86400.0, neg_td.totalDays());

    // Test with nanosecond precision
    const precise_td = Duration{ .__sec = 86400, .__nsec = 123456789 };
    try testing.expectEqual(1.0 + 123456789.0 / 86400000000000.0, precise_td.totalDays());
}

test "add durations, basic" {
    var a = Duration{ .__sec = 1 };
    var b = Duration{ .__sec = 1 };
    var c = try a.add(b);
    var d = a.addClip(b);
    try testing.expectEqual(@as(i64, 2), c.__sec);
    try testing.expectEqual(@as(u32, 0), c.__nsec);
    try testing.expectEqual(@as(i64, 2), d.__sec);
    try testing.expectEqual(@as(u32, 0), d.__nsec);

    a = Duration{ .__sec = 1 };
    b = Duration{ .__nsec = 1 };
    c = try a.add(b);
    d = a.addClip(b);
    try testing.expectEqual(@as(i64, 1), c.__sec);
    try testing.expectEqual(@as(u32, 1), c.__nsec);
    try testing.expectEqual(@as(i64, 1), d.__sec);
    try testing.expectEqual(@as(u32, 1), d.__nsec);

    a = Duration{ .__nsec = 500_000_000 };
    b = Duration{ .__nsec = 500_000_314 };
    c = try a.add(b);
    d = a.addClip(b);
    try testing.expectEqual(@as(i64, 1), c.__sec);
    try testing.expectEqual(@as(u32, 314), c.__nsec);
    try testing.expectEqual(@as(i64, 1), d.__sec);
    try testing.expectEqual(@as(u32, 314), d.__nsec);
}

test "add durations, edge cases" {
    // Test overflow to RangeError for add()
    var max_dur = Duration{ .__sec = Duration.max_sec, .__nsec = 999_999_999 };
    const one_ns = Duration{ .__nsec = 1 };
    try testing.expectError(error.SecondOutOfRange, max_dur.add(one_ns));

    var min_dur = Duration{ .__sec = Duration.min_sec, .__nsec = 0 };
    const neg_one_ns = Duration{ .__sec = -1, .__nsec = 999_999_999 };
    try testing.expectError(error.SecondOutOfRange, min_dur.add(neg_one_ns));

    // Test maximum positive + maximum positive overflow
    var max_sec_dur = Duration{ .__sec = Duration.max_sec };
    try testing.expectError(error.SecondOutOfRange, max_sec_dur.add(max_sec_dur));

    // Test minimum negative + minimum negative overflow
    var min_sec_dur = Duration{ .__sec = Duration.min_sec };
    try testing.expectError(error.SecondOutOfRange, min_sec_dur.add(min_sec_dur));

    // Test nanosecond overflow that causes second increment beyond max
    var almost_max = Duration{ .__sec = Duration.max_sec, .__nsec = 500_000_000 };
    const half_sec_ns = Duration{ .__nsec = 500_000_000 };
    try testing.expectError(error.SecondOutOfRange, almost_max.add(half_sec_ns));

    // Test boundary case: exactly at max must work
    var at_max = Duration{ .__sec = Duration.max_sec - 1, .__nsec = 999_999_999 };
    var result = try at_max.add(one_ns);
    try testing.expectEqual(Duration.max_sec, result.__sec);
    try testing.expectEqual(@as(u32, 0), result.__nsec);

    // Test boundary case: exactly at min must work
    var at_min = Duration{ .__sec = Duration.min_sec + 1, .__nsec = 0 };
    const neg_one_sec = Duration{ .__sec = -1 };
    result = try at_min.add(neg_one_sec);
    try testing.expectEqual(Duration.min_sec, result.__sec);
    try testing.expectEqual(@as(u32, 0), result.__nsec);

    // Test addClip() clamps to max_sec
    var clipped = max_dur.addClip(one_ns);
    try testing.expectEqual(Duration.max_sec, clipped.__sec);
    try testing.expectEqual(@as(u32, 0), clipped.__nsec);

    // Test addClip() clamps to min_sec
    clipped = min_dur.addClip(neg_one_ns);
    try testing.expectEqual(Duration.min_sec, clipped.__sec);
    try testing.expectEqual(@as(u32, 999_999_999), clipped.__nsec);

    // Test addClip() with nanosecond overflow causing clipping
    clipped = almost_max.addClip(half_sec_ns);
    try testing.expectEqual(Duration.max_sec, clipped.__sec);
    try testing.expectEqual(@as(u32, 0), clipped.__nsec);

    // Test zero addition edge cases
    const zero = Duration{};
    result = try max_dur.add(zero);
    try testing.expectEqual(Duration.max_sec, result.__sec);
    try testing.expectEqual(@as(u32, 999_999_999), result.__nsec);

    result = try min_dur.add(zero);
    try testing.expectEqual(Duration.min_sec, result.__sec);
    try testing.expectEqual(@as(u32, 0), result.__nsec);
}

test "subtract durations, basic" {
    var a = Duration{ .__sec = 1 };
    var b = Duration{ .__sec = 1 };
    var c = try a.sub(b);
    var d = a.subClip(b);
    try testing.expectEqual(@as(i64, 0), c.__sec);
    try testing.expectEqual(@as(u32, 0), c.__nsec);
    try testing.expectEqual(@as(i64, 0), d.__sec);
    try testing.expectEqual(@as(u32, 0), d.__nsec);

    a = Duration{ .__sec = 1 };
    b = Duration{ .__nsec = 1 };
    c = try a.sub(b);
    d = a.subClip(b);
    try testing.expectEqual(@as(i64, 0), c.__sec);
    try testing.expectEqual(@as(u32, 999_999_999), c.__nsec);
    try testing.expectEqual(@as(i64, 0), d.__sec);
    try testing.expectEqual(@as(u32, 999_999_999), d.__nsec);

    a = Duration{ .__nsec = 500_000_000 };
    b = Duration{ .__nsec = 500_000_314 };
    c = try a.sub(b);
    d = a.subClip(b);
    try testing.expectEqual(@as(i64, -1), c.__sec);
    try testing.expectEqual(@as(u32, 999999686), c.__nsec);
    try testing.expectEqual(@as(i64, -1), d.__sec);
    try testing.expectEqual(@as(u32, 999999686), d.__nsec);
}

test "subtract durations, edge cases" {
    // Test underflow to RangeError for sub()
    var min_dur = Duration{ .__sec = Duration.min_sec, .__nsec = 0 };
    const one_ns = Duration{ .__nsec = 1 };
    try testing.expectError(error.SecondOutOfRange, min_dur.sub(one_ns));

    var max_dur = Duration{ .__sec = Duration.max_sec, .__nsec = 999_999_999 };
    const neg_one_ns = Duration{ .__sec = -1, .__nsec = 999_999_999 };
    try testing.expectError(error.SecondOutOfRange, max_dur.sub(neg_one_ns));

    // Test maximum positive - maximum negative overflow
    var max_sec_dur = Duration{ .__sec = Duration.max_sec };
    var min_sec_dur = Duration{ .__sec = Duration.min_sec };
    try testing.expectError(error.SecondOutOfRange, max_sec_dur.sub(min_sec_dur));

    // Test minimum negative - maximum positive underflow
    try testing.expectError(error.SecondOutOfRange, min_sec_dur.sub(max_sec_dur));

    // Test nanosecond borrowing that causes second decrement beyond min
    var almost_min = Duration{ .__sec = Duration.min_sec, .__nsec = 0 };
    try testing.expectError(error.SecondOutOfRange, almost_min.sub(one_ns));

    // Test boundary case: exactly at min must work
    var at_min_plus_one = Duration{ .__sec = Duration.min_sec + 1, .__nsec = 0 };
    const one_sec = Duration{ .__sec = 1 };
    var result = try at_min_plus_one.sub(one_sec);
    try testing.expectEqual(Duration.min_sec, result.__sec);
    try testing.expectEqual(@as(u32, 0), result.__nsec);

    // Test boundary case: exactly at max must work
    var at_max_minus_one = Duration{ .__sec = Duration.max_sec - 1, .__nsec = 999_999_999 };
    const neg_one_sec = Duration{ .__sec = -1 };
    result = try at_max_minus_one.sub(neg_one_sec);
    try testing.expectEqual(Duration.max_sec, result.__sec);
    try testing.expectEqual(@as(u32, 999_999_999), result.__nsec);

    // Test subClip() clamps to min_sec when underflow occurs
    var clipped = min_dur.subClip(one_ns);
    try testing.expectEqual(Duration.min_sec, clipped.__sec);
    try testing.expectEqual(@as(u32, 999_999_999), clipped.__nsec);

    // Test subClip() clamps to max_sec when overflow occurs
    clipped = max_dur.subClip(neg_one_ns);
    try testing.expectEqual(Duration.max_sec, clipped.__sec);
    try testing.expectEqual(@as(u32, 0), clipped.__nsec);

    // Test nanosecond borrowing edge case
    var test_dur = Duration{ .__sec = 1, .__nsec = 0 };
    const ns_999 = Duration{ .__nsec = 999_999_999 };
    result = try test_dur.sub(ns_999);
    try testing.expectEqual(@as(i128, 0), result.__sec);
    try testing.expectEqual(@as(u32, 1), result.__nsec);

    // Test nanosecond borrowing at boundary
    var boundary_dur = Duration{ .__sec = Duration.min_sec + 1, .__nsec = 0 };
    result = try boundary_dur.sub(one_ns);
    try testing.expectEqual(Duration.min_sec, result.__sec);
    try testing.expectEqual(@as(u32, 999_999_999), result.__nsec);

    // Test zero subtraction edge cases
    var zero = Duration{};
    result = try max_dur.sub(zero);
    try testing.expectEqual(Duration.max_sec, result.__sec);
    try testing.expectEqual(@as(u32, 999_999_999), result.__nsec);

    result = try min_dur.sub(zero);
    try testing.expectEqual(Duration.min_sec, result.__sec);
    try testing.expectEqual(@as(u32, 0), result.__nsec);

    // Test subtracting from zero
    result = try zero.sub(Duration{ .__sec = 1, .__nsec = 500_000_000 });
    try testing.expectEqual(@as(i128, -2), result.__sec);
    try testing.expectEqual(@as(u32, 500_000_000), result.__nsec);
}

test "add duration to datetime" {
    var dt = try Datetime.fromFields(.{ .year = 1970, .second = 42 });
    var dt_want = try Datetime.fromFields(.{ .year = 1970, .second = 43 });
    dt = try dt.add(Duration{ .__sec = 1, .__nsec = 0 });
    try testing.expectEqual(@as(i64, 43), dt.unix_sec);
    try testing.expectEqual(dt_want, dt);

    dt = try dt.add(Duration{ .__sec = -1, .__nsec = 0 });
    dt_want = try Datetime.fromFields(.{ .year = 1970, .second = 42 });
    try testing.expectEqual(@as(i64, 42), dt.unix_sec);
    try testing.expectEqual(dt_want, dt);

    dt = try dt.add(Duration{ .__sec = -1, .__nsec = 1E9 });
    try testing.expectEqual(@as(i64, 42), dt.unix_sec);
    try testing.expectEqual(@as(u32, 0), dt.nanosecond);

    dt = try dt.add(Duration.fromTimespanMultiple(1, .week));
    try testing.expectEqual(@as(u8, 8), dt.day);

    const err = dt.add(Duration.fromTimespanMultiple(9223372036854775807, .week));
    try testing.expectError(error.UnixOutOfRange, err);
}

test "subtract duration from datetime" {
    var dt = try Datetime.fromFields(.{ .year = 1970, .second = 42 });
    dt = try dt.sub(Duration{ .__sec = -1, .__nsec = 0 });
    try testing.expectEqual(@as(i64, 43), dt.unix_sec);

    dt = try dt.sub(Duration{ .__sec = 1, .__nsec = 0 });
    try testing.expectEqual(@as(i64, 42), dt.unix_sec);

    dt = try dt.sub(Duration{ .__sec = 1, .__nsec = 1E9 });
    try testing.expectEqual(@as(i64, 42), dt.unix_sec);
    try testing.expectEqual(@as(u32, 0), dt.nanosecond);

    const err = dt.sub(Duration.fromTimespanMultiple(9223372036854775807, .week));
    try testing.expectError(error.UnixOutOfRange, err);
}

test "datetime difference" {
    var a = try Datetime.fromFields(.{ .year = 1970, .second = 1 });
    var b = try Datetime.fromFields(.{ .year = 1970, .second = 1 });
    var diff = a.diff(b);
    try testing.expectEqual(@as(i64, 0), diff.__sec);
    try testing.expectEqual(@as(u32, 0), diff.__nsec);

    a = try Datetime.fromFields(.{ .year = 1970, .second = 0 });
    b = try Datetime.fromFields(.{ .year = 1970, .second = 1 });
    diff = a.diff(b);
    try testing.expectEqual(@as(i64, -1), diff.__sec);
    try testing.expectEqual(@as(u32, 0), diff.__nsec);

    diff = b.diff(a);
    try testing.expectEqual(@as(i64, 1), diff.__sec);
    try testing.expectEqual(@as(u32, 0), diff.__nsec);

    a = try Datetime.fromUnix(Datetime.unix_s_min, .second, null);
    b = try Datetime.fromUnix(Datetime.unix_s_max, .second, null);
    // just ensure that this works and isn't out-of-range for the duration:
    diff = a.diff(b);
}

test "leap second difference" {
    var a = try Datetime.fromISO8601("1972-06-30");
    var b = try Datetime.fromISO8601("1972-07-01");
    var leaps = a.diffLeap(b);
    try testing.expectEqual(@as(i64, -1), leaps.__sec);
    try testing.expectEqual(@as(u32, 0), leaps.__nsec);
    var diff = a.diff(b);
    diff = try diff.add(leaps);
    try testing.expectEqual(@as(i64, -86401), diff.__sec);
    try testing.expectEqual(@as(u32, 0), diff.__nsec);

    a = try Datetime.fromISO8601("1973-01-01");
    b = try Datetime.fromISO8601("1972-06-30");
    leaps = a.diffLeap(b);
    try testing.expectEqual(@as(i64, 2), leaps.__sec);
    try testing.expectEqual(@as(u32, 0), leaps.__nsec);

    a = try Datetime.fromISO8601("1970-01-01");
    b = try Datetime.fromISO8601("2024-01-01");
    leaps = a.diffLeap(b);
    try testing.expectEqual(@as(i64, -27), leaps.__sec);
    try testing.expectEqual(@as(u32, 0), leaps.__nsec);

    a = try Datetime.fromISO8601("2024-01-01");
    b = try Datetime.fromISO8601("2016-12-31"); // before last leap second insertion
    leaps = a.diffLeap(b);
    try testing.expectEqual(@as(i64, 1), leaps.__sec);
    try testing.expectEqual(@as(u32, 0), leaps.__nsec);

    a = try Datetime.fromISO8601("2024-10-01");
    b = try Datetime.fromISO8601("2024-10-02");
    leaps = a.diffLeap(b);
    try testing.expectEqual(@as(i64, 0), leaps.__sec);
    try testing.expectEqual(@as(u32, 0), leaps.__nsec);
    diff = a.diff(b);
    diff = try diff.add(leaps);
    try testing.expectEqual(@as(i64, -86400), diff.__sec);
    try testing.expectEqual(@as(u32, 0), diff.__nsec);
}

const TestCaseISODur = struct {
    string: []const u8 = "",
    fields: Duration.RelativeDelta = .{},
    duration: Duration = .{},
};

test "iso duration parser, full valid input" {
    const cases = [_]TestCaseISODur{
        .{
            .string = "P1Y2M3DT4H5M6.789S",
            .fields = .{ .years = 1, .months = 2, .days = 3, .hours = 4, .minutes = 5, .seconds = 6, .nanoseconds = 789000000 },
        },
        .{
            .string = "P2Y3M4DT5H6M7.89S",
            .fields = .{ .years = 2, .months = 3, .days = 4, .hours = 5, .minutes = 6, .seconds = 7, .nanoseconds = 890000000 },
        },
        .{
            .string = "P999Y0M0DT0H0M0.123S",
            .fields = .{ .years = 999, .months = 0, .days = 0, .hours = 0, .minutes = 0, .seconds = 0, .nanoseconds = 123000000 },
        },
        .{
            .string = "P3Y4M5DT6H7M8.9S",
            .fields = .{ .years = 3, .months = 4, .days = 5, .hours = 6, .minutes = 7, .seconds = 8, .nanoseconds = 900000000 },
        },
        .{
            .string = "P5Y6M7DT8H9M10.111000001S",
            .fields = .{ .years = 5, .months = 6, .days = 7, .hours = 8, .minutes = 9, .seconds = 10, .nanoseconds = 111000001 },
        },
        .{
            .string = "P7Y8M9DT10H11M12.123S",
            .fields = .{ .years = 7, .months = 8, .days = 9, .hours = 10, .minutes = 11, .seconds = 12, .nanoseconds = 123000000 },
        },
        .{
            .string = "P8Y9M10DT11H12M13.145S",
            .fields = .{ .years = 8, .months = 9, .days = 10, .hours = 11, .minutes = 12, .seconds = 13, .nanoseconds = 145000000 },
        },
        .{
            .string = "-P9Y10M11DT12H13M14.156S",
            .fields = .{
                .years = 9,
                .months = 10,
                .days = 11,
                .hours = 12,
                .minutes = 13,
                .seconds = 14,
                .nanoseconds = 156000000,
                .negative = true,
            },
        },
        .{
            .string = "-P9Y10M41W11DT12H13M14.156S",
            .fields = .{
                .years = 9,
                .months = 10,
                .weeks = 41,
                .days = 11,
                .hours = 12,
                .minutes = 13,
                .seconds = 14,
                .nanoseconds = 156000000,
                .negative = true,
            },
        },
        .{
            .string = "P1M7WT7M",
            .fields = .{ .months = 1, .weeks = 7, .minutes = 7 },
        },
    };

    for (cases) |case| {
        const fields = try Duration.RelativeDelta.fromISO8601(case.string);
        try testing.expectEqual(case.fields, fields);
        // all test cases have year or month != 0, so conversion to duration fails:
        try testing.expectError(error.InvalidFormat, Duration.fromISO8601(case.string));
    }
}

test "iso duration to Duration type round-trip" {
    const cases = [_]TestCaseISODur{
        .{
            .string = "PT0S",
            .duration = .{},
        },
        .{
            .string = "-PT46M59.789S",
            .duration = .{ .__sec = -(46 * 60 + 59), .__nsec = 789000000 },
        },
        .{
            .string = "PT4H5M6.789S",
            .duration = .{ .__sec = 4 * 3600 + 5 * 60 + 6, .__nsec = 789000000 },
        },
        .{
            .string = "P1DT13H12.789000001S",
            .duration = .{ .__sec = 37 * 3600 + 12, .__nsec = 789000001 },
        },
        .{
            .string = "-PT46M59.789S",
            .duration = .{ .__sec = -(46 * 60 + 59), .__nsec = 789000000 },
        },
    };

    var buf: [64]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    for (cases) |case| {
        const dur = try Duration.fromISO8601(case.string);
        try testing.expectEqual(case.duration, dur);

        w = .fixed(&buf);
        try case.duration.format(&w);
        try testing.expectEqualStrings(case.string, w.buffered());
    }
}

const TestCaseISODurFail = struct {
    string: []const u8,
    expected: anyerror,
};

test "iso duration fail cases" {
    const cases = [_]TestCaseISODurFail{
        .{ .string = "PT7HT7S", .expected = error.InvalidFormat },
        .{ .string = "PT7D", .expected = error.InvalidFormat },
        .{ .string = "P7HT7S", .expected = error.InvalidFormat },
        .{ .string = "P7S7M", .expected = error.InvalidFormat },
        .{ .string = "P7W7M", .expected = error.InvalidFormat },
        .{ .string = "P7.1W", .expected = error.InvalidCharacter },
        .{ .string = "P.1S", .expected = error.InvalidFormat },
        .{ .string = "P-7D", .expected = error.InvalidFormat },
        .{ .string = "P7M7M", .expected = error.InvalidFormat },
        .{ .string = "PT3HT4S", .expected = error.InvalidFormat },
        .{ .string = "P7M7S", .expected = error.InvalidFormat },
        .{ .string = "PT7M7M", .expected = error.InvalidFormat },
        .{ .string = "P7M7MT7S", .expected = error.InvalidFormat },
        .{ .string = "−PT7D", .expected = error.InvalidFormat },
        .{ .string = "PT59,789S", .expected = error.InvalidCharacter },
        .{ .string = "PT59.789M", .expected = error.InvalidCharacter },
        .{ .string = "P2020-01-01T00-00-01", .expected = error.InvalidFormat },
        .{ .string = "P20200101T000001", .expected = error.InvalidFormat },
        .{ .string = "-PT;0H46M59.789S", .expected = error.InvalidFormat },
        .{ .string = "yPT0H46M59.789S", .expected = error.InvalidFormat },
        .{ .string = "-P--T0H46M59.789S", .expected = error.InvalidFormat },
        .{ .string = "P1Y2M3DT4K5M6.789S", .expected = error.InvalidFormat },
        .{ .string = "PX2Y3M4DT5H6M7.89S", .expected = error.InvalidFormat },
        .{ .string = "P999Y0M0D 0H0M0.123S", .expected = error.InvalidCharacter },
        .{ .string = "P+999Y0M0DT0H0M0.123S", .expected = error.InvalidFormat },
        .{ .string = "P3Y4M5DT6H7M8.9>", .expected = error.InvalidFormat },
        .{ .string = "P-+5Y6M7DT8H9M10.111000001S", .expected = error.InvalidFormat },
        .{ .string = "P7Y8M9DT10H11M12;123S", .expected = error.InvalidCharacter },
        .{ .string = "P-8Y9M10XT11H12M13.145S", .expected = error.InvalidFormat },
        .{ .string = "-P9Y10M11DT12H13M14.156s", .expected = error.InvalidFormat },
        .{ .string = "UwKMxofSAIQSil8gW", .expected = error.InvalidFormat },
        .{ .string = "gikNDeWiEh4yRt01haAPWqxQWOUSG2hC3EWSiAn3BNnt", .expected = error.InvalidFormat },
        .{ .string = "PT1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000S", .expected = error.InvalidFormat },

        // designator order / structure
        .{ .string = "P1M1Y", .expected = error.InvalidFormat },
        .{ .string = "PT1S1M", .expected = error.InvalidFormat },
        .{ .string = "PT1M1H", .expected = error.InvalidFormat },
        .{ .string = "P1DT", .expected = error.InvalidFormat },
        .{ .string = "pt1h", .expected = error.InvalidFormat },
        .{ .string = "P1d", .expected = error.InvalidFormat },
        .{ .string = "PT1H1MT", .expected = error.InvalidFormat },
        .{ .string = "P1T1H", .expected = error.InvalidFormat },

        // sign / whitespace / separators
        .{ .string = "-P1Y-2M", .expected = error.InvalidFormat },
        .{ .string = "P1D ", .expected = error.InvalidFormat },
        .{ .string = "P-1D ", .expected = error.InvalidFormat },
        .{ .string = " P1D", .expected = error.InvalidFormat },
        .{ .string = "P1,5D", .expected = error.InvalidCharacter },
        .{ .string = "PT1H,5M", .expected = error.InvalidCharacter },

        // fraction edge cases
        .{ .string = "PT5.S", .expected = error.InvalidCharacter },
        .{ .string = "PT.5S", .expected = error.InvalidFormat },
        .{ .string = "PT1.2.3S", .expected = error.InvalidCharacter },
        .{ .string = "PT0.5H", .expected = error.InvalidCharacter },
        .{ .string = "P1.5W", .expected = error.InvalidCharacter },

        // overflow boundaries
        .{ .string = "PT4294967296S", .expected = error.Overflow },
        .{ .string = "PT4294967296M", .expected = error.Overflow },
        .{ .string = "PT4294967296H", .expected = error.Overflow },
        .{ .string = "P4294967296D", .expected = error.Overflow },
        .{ .string = "P4294967296W", .expected = error.Overflow },
        .{ .string = "P4294967296M", .expected = error.Overflow },
        .{ .string = "P4294967296Y", .expected = error.Overflow },

        // minimal / degenerate
        .{ .string = "", .expected = error.InvalidFormat },
        .{ .string = "0", .expected = error.InvalidFormat },
        .{ .string = "P", .expected = error.InvalidFormat },
        .{ .string = "-P", .expected = error.InvalidFormat },
        .{ .string = "T5S", .expected = error.InvalidFormat },
        .{ .string = "P5S", .expected = error.InvalidFormat },
        .{ .string = "PT", .expected = error.InvalidFormat },
        .{ .string = "P0", .expected = error.InvalidFormat },
        .{ .string = "-PT", .expected = error.InvalidFormat },
    };

    for (cases) |case| {
        try testing.expectError(case.expected, Duration.RelativeDelta.fromISO8601(case.string));
    }
}

test "iso duration valid edge cases" {
    const cases = [_]TestCaseISODur{
        .{ // smallest representable fraction
            .string = "PT0.000000001S",
            .duration = .{ .__sec = 0, .__nsec = 1 },
        },
        .{ // max u32 seconds and nanoseconds
            .string = "PT4294967295.999999999S",
            .duration = .{ .__sec = 4294967295, .__nsec = 999999999 },
        },
        .{ // shortest form
            .string = "P0D",
            .duration = .{},
        },
        .{
            .string = "-P0D",
            .duration = .{},
        },
        .{ // max u32 days
            .string = "P4294967295D",
            .duration = .{ .__sec = 4294967295 * 86400 },
        },
        .{ // max u32 weeks
            .string = "P4294967295W",
            .duration = .{ .__sec = 4294967295 * 86400 * 7 },
        },
        .{ // all maxed
            .string = "P4294967295W4294967295DT4294967295H4294967295M4294967295.999999999S",
            .duration = .{
                .__sec = 4294967295 * 86400 * 7 + // weeks
                    4294967295 * 86400 + // days
                    4294967295 * 3600 + // hours
                    4294967295 * 60 + // minutes
                    4294967295, // seconds
                .__nsec = 999999999,
            },
        },
        // absolute duration type cannot represent months / years
    };

    for (cases) |case| {
        try testing.expectEqual(case.duration, try Duration.fromISO8601(case.string));
    }
}

test "Duration.fromISO8601 rejects ambiguous units" {
    try testing.expectError(error.InvalidFormat, Duration.fromISO8601("P1M"));
    try testing.expectError(error.InvalidFormat, Duration.fromISO8601("P1Y"));
    try testing.expectError(error.InvalidFormat, Duration.fromISO8601("P1Y0M"));
}

test "relative delta normalizer" {
    const cases = [_]TestCaseISODur{
        .{
            .string = "PT6.789S",
            .fields = .{ .seconds = 6, .nanoseconds = 789000000, .negative = false },
            .duration = .{ .__sec = 6, .__nsec = 789000000 },
        },
        .{
            .string = "-PT6.789S",
            .fields = .{ .seconds = 6, .nanoseconds = 789000000, .negative = true },
            .duration = .{ .__sec = -6, .__nsec = 789000000 },
        },
        .{
            .string = "PT61.789S",
            .fields = .{ .minutes = 1, .seconds = 1, .nanoseconds = 789000000 },
            .duration = .{ .__sec = 61, .__nsec = 789000000 },
        },
        .{
            .string = "PT60M",
            .fields = .{ .hours = 1 },
            .duration = .{ .__sec = 3600 },
        },
        .{
            .string = "-P1DT1H1M",
            .fields = .{ .days = 1, .hours = 1, .minutes = 1, .negative = true },
            .duration = .{ .__sec = -(86400 + 3600 + 60) },
        },
        .{
            .string = "-PT24H60M60S",
            .fields = .{ .days = 1, .hours = 1, .minutes = 1, .negative = true },
            .duration = .{ .__sec = -(86400 + 3600 + 60) },
        },
        .{
            .string = "P1W2DT3H4M5S",
            .fields = .{ .weeks = 1, .days = 2, .hours = 3, .minutes = 4, .seconds = 5 },
            .duration = .{ .__sec = 9 * 86400 + 3 * 3600 + 4 * 60 + 5 },
        },
        .{
            .string = "-P1W2DT3H4M5S",
            .fields = .{ .weeks = 1, .days = 2, .hours = 3, .minutes = 4, .seconds = 5, .negative = true },
            .duration = .{ .__sec = -(9 * 86400 + 3 * 3600 + 4 * 60 + 5) },
        },
        .{
            .string = "PT4294967295S",
            .fields = .{ .weeks = 7101, .days = 3, .hours = 6, .minutes = 28, .seconds = 15 },
            .duration = .{ .__sec = 4294967295 },
        },
        // boundary cases: exactly one day / week must carry over
        .{
            .string = "PT24H",
            .fields = .{ .days = 1 },
            .duration = .{ .__sec = 86400 },
        },
        .{
            .string = "P7D",
            .fields = .{ .weeks = 1 },
            .duration = .{ .__sec = 7 * 86400 },
        },
        .{
            .string = "PT48H",
            .fields = .{ .days = 2 },
            .duration = .{ .__sec = 2 * 86400 },
        },
        .{
            .string = "P14D",
            .fields = .{ .weeks = 2 },
            .duration = .{ .__sec = 14 * 86400 },
        },
    };

    for (cases) |case| {
        const fields = try Duration.RelativeDelta.fromISO8601(case.string);
        const normalized_fields = fields.normalize();
        try testing.expectEqual(case.fields, normalized_fields);
        try testing.expectEqual(normalized_fields, Duration.RelativeDelta.fromDuration(&case.duration));
    }
}

const TestCaseFormatter = struct {
    have: []const u8,
    want: []const u8,
};

test "ISO8601 duration parse and normalize" {
    const cases = [_]TestCaseFormatter{
        .{ .have = "PT24H", .want = "P1D" },
        .{ .have = "PT24H60M", .want = "P1DT1H" },
        .{ .have = "PT249H", .want = "P1W3DT9H" },
        .{ .have = "PT294423.9S", .want = "P3DT9H47M3.9S" },
        .{ .have = "PT10080000M", .want = "P1000W" },
    };

    var buf: [64]u8 = undefined;
    for (cases) |case| {
        var w: std.Io.Writer = .fixed(&buf);
        const reldelta = try Duration.fromISO8601(case.have);
        try reldelta.format(&w);
        try testing.expectEqualStrings(case.want, w.buffered());
    }
}
