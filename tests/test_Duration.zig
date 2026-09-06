// SPDX-FileCopyrightText: 2024-2026 Florian Obersteiner
// SPDX-FileContributor: Florian Obersteiner <f.obersteiner@posteo.de>
// SPDX-FileContributor: Michael Pollind <mpollind@gmail.com>
//
// SPDX-License-Identifier: Unlicense

//! test duration from a users's perspective (no internal functionality)

const std = @import("std");
const testing = std.testing;

const zdt = @import("zdt");
const ZdtError = zdt.ZdtError;
const Duration = zdt.Duration;

const log = std.log.scoped(.test_duration);

const u32_max: u32 = std.math.maxInt(u32);

const ns_per_s: i96 = 1_000_000_000;
const s_per_day: i96 = 86_400;
const s_per_min: i96 = 60;

test "from timespan" {
    var td = try Duration.fromTimespanMultiple(5, .nanosecond);
    try testing.expectEqual(@as(i96, 5), td.asNanoseconds());

    td = try Duration.fromTimespanMultiple(32, .second);
    try testing.expectEqual(@as(i96, 32E9), td.asNanoseconds());
    try testing.expectEqual(@as(i64, 32), td.asSeconds());

    td = try Duration.fromTimespanMultiple(1, .week);
    try testing.expectEqual(@as(i64, 7 * 24 * 60 * 60), td.asSeconds());

    const max_weeks = Duration.duration_range_ns.max / (ns_per_s * s_per_day * 7);
    td = try Duration.fromTimespanMultiple(max_weeks, .week);
    const rd = Duration.RelativeDelta.fromDuration(&td);
    // fields clamp at u32 max; the excess carries over to the next smaller unit:
    try testing.expectEqual((1 << 32) - 1, rd.weeks);
    try testing.expectEqual((1 << 32) - 1, rd.days);
    try testing.expectEqual((1 << 32) - 1, rd.hours);
    try testing.expectEqual((1 << 32) - 1, rd.minutes);
    // the last remainder still fits:
    try testing.expectEqual(@as(u32, 4294701900), rd.seconds);
    try testing.expectEqual(@as(u32, 0), rd.nanoseconds);
}

test "from timespan, out of range" {
    // just beyond the maximum representable number of weeks
    try testing.expectError(ZdtError.OutOfRange, Duration.fromTimespanMultiple(4934532523, .week));
    try testing.expectError(ZdtError.OutOfRange, Duration.fromTimespanMultiple(-4934532523, .week));

    // just beyond the maximum representable number of seconds
    try testing.expectError(ZdtError.OutOfRange, Duration.fromTimespanMultiple(2984405269570997, .second));
    try testing.expectError(ZdtError.OutOfRange, Duration.fromTimespanMultiple(-2984405269570997, .second));

    // huge multiplicands must error, not overflow the intermediate product
    // (regression: this used to panic with 'overflow of integer type i128')
    try testing.expectError(ZdtError.OutOfRange, Duration.fromTimespanMultiple(std.math.maxInt(i96), .week));
    try testing.expectError(ZdtError.OutOfRange, Duration.fromTimespanMultiple(std.math.minInt(i96), .week));
    try testing.expectError(ZdtError.OutOfRange, Duration.fromTimespanMultiple(std.math.maxInt(i96), .second));

    // boundary: exactly at the bounds must work
    _ = try Duration.fromTimespanMultiple(4934532522, .week);
    _ = try Duration.fromTimespanMultiple(2984405269570995, .second);
}

test "to timespan" {
    var td = try Duration.fromTimespanMultiple(5, .nanosecond);
    try testing.expectEqual(@as(i96, 5), td.asNanoseconds());

    const ns = td.toTimespanMultiple(.nanosecond);
    try testing.expectEqual(@as(i96, 5), ns);

    const weeks = td.toTimespanMultiple(.week);
    try testing.expectEqual(@as(i96, 1), weeks);

    td = try Duration.fromTimespanMultiple(5500, .microsecond);
    var ms = td.toTimespanMultiple(.millisecond);
    try testing.expectEqual(@as(i96, 6), ms);

    td = try Duration.fromTimespanMultiple(5501, .microsecond);
    ms = td.toTimespanMultiple(.millisecond);
    try testing.expectEqual(@as(i96, 6), ms);
}

test "to timespan, negative and zero" {
    // exact negative multiples convert exactly
    var td = try Duration.fromTimespanMultiple(-2, .hour);
    try testing.expectEqual(@as(i96, -120), td.toTimespanMultiple(.minute));
    try testing.expectEqual(@as(i96, -2), td.toTimespanMultiple(.hour));

    // negative fractional values round away from zero (divFloor),
    // i.e. the result still 'contains' the duration:
    td = Duration{ .__nsec = -ns_per_s - ns_per_s / 2 }; // -1.5 s
    try testing.expectEqual(@as(i96, -2), td.toTimespanMultiple(.second));

    // sub-timespan negative values do not round up to zero
    td = Duration{ .__nsec = -1 };
    try testing.expectEqual(@as(i96, -1), td.toTimespanMultiple(.second));

    // zero converts to zero for every timespan
    const zero = Duration{};
    inline for (.{ .nanosecond, .millisecond, .second, .minute, .hour, .day, .week }) |ts| {
        try testing.expectEqual(@as(i96, 0), zero.toTimespanMultiple(ts));
    }
}

test "asSeconds, fractional and negative values" {
    // positive values truncate downwards
    try testing.expectEqual(@as(i96, 1), (Duration{ .__nsec = ns_per_s + 500 }).asSeconds());

    // zero
    try testing.expectEqual(@as(i96, 0), (Duration{}).asSeconds());

    // negative values floor (divFloor semantics), not truncate:
    // -1.5 seconds -> -2
    try testing.expectEqual(@as(i96, -2), (Duration{ .__nsec = -ns_per_s - ns_per_s / 2 }).asSeconds());
    // -0.5 seconds -> -1
    try testing.expectEqual(@as(i96, -1), (Duration{ .__nsec = -500_000_000 }).asSeconds());
}

test "edge cases, min-max" {
    var td = Duration{ .__nsec = Duration.duration_range_ns.max };
    const want_max: i96 = Duration.duration_range_ns.max;
    try testing.expectEqual(want_max, td.asNanoseconds());
    try testing.expectEqual(want_max, td.toTimespanMultiple(.nanosecond));

    td = Duration{ .__nsec = Duration.duration_range_ns.min };
    const want_min: i96 = Duration.duration_range_ns.min;
    try testing.expectEqual(want_min, td.asNanoseconds());
    try testing.expectEqual(want_min, td.toTimespanMultiple(.nanosecond));

    const want_max_weeks: i64 = 4934532522;
    td = try Duration.fromTimespanMultiple(want_max_weeks, .week);
    try testing.expectEqual(want_max_weeks, td.toTimespanMultiple(.week));

    const want_min_weeks = -4934532522;
    td = try Duration.fromTimespanMultiple(want_min_weeks, .week);
    try testing.expectEqual(want_min_weeks, td.toTimespanMultiple(.week));
}

test "format" {
    var buf: [64]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);

    // fraction zeros get truncated
    const d = try Duration.fromISO8601("PT0.123450000S");
    try d.format(&w);
    try testing.expectEqualStrings("PT0.12345S", w.buffered());

    // format zero duration
    w = .fixed(&buf);
    try (Duration{}).format(&w);
    try testing.expectEqualStrings("PT0S", w.buffered());
}

test "total seconds" {
    // regular case
    const td = try Duration.fromTimespanMultiple(3141592653, .nanosecond);
    try testing.expectEqual(3.141592653, td.totalSeconds());

    // max positive value
    const large_td = try Duration.fromTimespanMultiple(2984405269570995, .second);
    // min negative value
    const neg_td = try Duration.fromTimespanMultiple(-2984405269570995, .second);

    try testing.expectEqual(2984405269570995.0, large_td.totalSeconds());
    try testing.expectEqual(-2984405269570995.0, neg_td.totalSeconds());
}

test "total minutes" {
    const td = try Duration.fromTimespanMultiple(185, .second);
    try testing.expectEqual(3.0833333333333335, td.totalMinutes());

    const large_td = try Duration.fromTimespanMultiple(2984405269570995, .second);
    const neg_td = try Duration.fromTimespanMultiple(-2984405269570995, .second);

    try testing.expectEqual(2984405269570995.0 / 60.0, large_td.totalMinutes());
    try testing.expectEqual(-2984405269570995.0 / 60.0, neg_td.totalMinutes());
}

test "total hours" {
    const td = try Duration.fromTimespanMultiple(6300, .second);
    try testing.expectEqual(1.75, td.totalHours());

    const large_td = try Duration.fromTimespanMultiple(2984405269570995, .second);
    const neg_td = try Duration.fromTimespanMultiple(-2984405269570995, .second);

    try testing.expectEqual(2984405269570995.0 / 3600.0, large_td.totalHours());
    try testing.expectEqual(-2984405269570995.0 / 3600.0, neg_td.totalHours());
}

test "total days" {
    const td = try Duration.fromTimespanMultiple(3, .day);
    try testing.expectEqual(3.0, td.totalDays());

    const large_td = try Duration.fromTimespanMultiple(2984405269570995, .second);
    const neg_td = try Duration.fromTimespanMultiple(-2984405269570995, .second);

    try testing.expectEqual(2984405269570995.0 / 86400.0, large_td.totalDays());
    try testing.expectEqual(-2984405269570995.0 / 86400.0, neg_td.totalDays());

    // with nanosecond precision
    const precise_td = Duration{ .__nsec = s_per_day * ns_per_s + 123456789 };
    try testing.expectEqual(1.0 + 123456789.0 / 86400000000000.0, precise_td.totalDays());
}

test "add durations, basic" {
    var a = Duration{ .__nsec = 1 * ns_per_s };
    var b = Duration{ .__nsec = 1 * ns_per_s };
    var c = try a.add(b);
    var d = a.addClip(b);
    try testing.expectEqual(@as(i96, 2 * ns_per_s), c.__nsec);
    try testing.expectEqual(@as(i96, 2 * ns_per_s), c.asNanoseconds());
    try testing.expectEqual(@as(i96, 2 * ns_per_s), d.__nsec);

    a = Duration{ .__nsec = ns_per_s + 1 };
    c = try a.add(b);
    d = a.addClip(b);
    try testing.expectEqual(@as(i96, 2 * ns_per_s + 1), c.__nsec);
    try testing.expectEqual(@as(i96, 2 * ns_per_s + 1), c.asNanoseconds());
    try testing.expectEqual(@as(i96, 2 * ns_per_s + 1), d.__nsec);

    a = Duration{ .__nsec = 500_000_000 };
    b = Duration{ .__nsec = 500_000_314 };
    c = try a.add(b);
    d = a.addClip(b);
    try testing.expectEqual(@as(i96, ns_per_s + 314), c.__nsec);
    try testing.expectEqual(@as(i96, ns_per_s + 314), c.asNanoseconds());
    try testing.expectEqual(@as(i96, ns_per_s + 314), d.__nsec);
}

test "add durations, edge cases" {
    // overflow to RangeError for add()
    var max_dur = Duration{ .__nsec = Duration.duration_range_ns.max };
    const one_ns = Duration{ .__nsec = 1 };
    try testing.expectError(ZdtError.OutOfRange, max_dur.add(one_ns));

    var min_dur = Duration{ .__nsec = Duration.duration_range_ns.min };
    const neg_one_ns = Duration{ .__nsec = -1 };
    try testing.expectError(ZdtError.OutOfRange, min_dur.add(neg_one_ns));

    // maximum positive + maximum positive overflow
    var max_sec_dur = Duration{ .__nsec = Duration.duration_range_ns.max };
    try testing.expectError(ZdtError.OutOfRange, max_sec_dur.add(max_sec_dur));

    // minimum negative + minimum negative overflow
    var min_sec_dur = Duration{ .__nsec = Duration.duration_range_ns.min };
    try testing.expectError(ZdtError.OutOfRange, min_sec_dur.add(min_sec_dur));

    // boundary case: exactly at max must work
    var at_max = Duration{ .__nsec = Duration.duration_range_ns.max - 1 };
    var result = try at_max.add(one_ns);
    try testing.expectEqual(Duration.duration_range_ns.max, result.__nsec);

    // boundary case: exactly at min must work
    var at_min = Duration{ .__nsec = Duration.duration_range_ns.min + 1 };
    result = try at_min.add(neg_one_ns);
    try testing.expectEqual(Duration.duration_range_ns.min, result.__nsec);

    // addClip() clamps to max_sec
    var clipped = max_dur.addClip(one_ns);
    try testing.expectEqual(Duration.duration_range_ns.max, clipped.__nsec);

    // addClip() clamps to min_sec
    clipped = min_dur.addClip(neg_one_ns);
    try testing.expectEqual(Duration.duration_range_ns.min, clipped.__nsec);

    // zero addition edge cases
    const zero = Duration{};
    result = try max_dur.add(zero);
    try testing.expectEqual(Duration.duration_range_ns.max, result.__nsec);

    result = try min_dur.add(zero);
    try testing.expectEqual(Duration.duration_range_ns.min, result.__nsec);
}

test "subtract durations, basic" {
    var a = Duration{ .__nsec = 1 * ns_per_s };
    var b = Duration{ .__nsec = 1 * ns_per_s };
    var c = try a.sub(b);
    var d = a.subClip(b);
    try testing.expectEqual(@as(i96, 0), c.__nsec);
    try testing.expectEqual(@as(i96, 0), c.asNanoseconds());
    try testing.expectEqual(@as(i96, 0), d.__nsec);

    a = Duration{ .__nsec = 1 * ns_per_s };
    b = Duration{ .__nsec = 1 };
    c = try a.sub(b);
    d = a.subClip(b);
    try testing.expectEqual(@as(i96, ns_per_s - 1), c.__nsec);
    try testing.expectEqual(@as(i96, 999_999_999), c.asNanoseconds());
    try testing.expectEqual(@as(i96, ns_per_s - 1), d.__nsec);

    a = Duration{ .__nsec = 500_000_000 };
    b = Duration{ .__nsec = 500_000_314 };
    c = try a.sub(b);
    d = a.subClip(b);
    try testing.expectEqual(@as(i96, -314), c.__nsec);
    try testing.expectEqual(@as(i96, -314), c.asNanoseconds());
    try testing.expectEqual(@as(i96, -314), d.__nsec);

    a = Duration{ .__nsec = 1_510_000_000 };
    b = Duration{ .__nsec = 3 * ns_per_s };
    c = try a.sub(b);
    try testing.expectEqual(@as(i96, -1_490_000_000), c.__nsec);
    try testing.expectEqual(@as(i96, -1_490_000_000), c.asNanoseconds());
}

test "subtract durations, edge cases" {
    // underflow to RangeError for sub()
    var min_dur = Duration{ .__nsec = Duration.duration_range_ns.min };
    var max_dur = Duration{ .__nsec = Duration.duration_range_ns.max };
    const one_ns = Duration{ .__nsec = 1 };
    const neg_one_ns = Duration{ .__nsec = -1 };
    try testing.expectError(ZdtError.OutOfRange, min_dur.sub(one_ns));
    try testing.expectError(ZdtError.OutOfRange, max_dur.sub(neg_one_ns));

    // boundary case: exactly at min must work
    var at_min_plus_one = Duration{ .__nsec = Duration.duration_range_ns.min + ns_per_s };
    const one_sec = Duration{ .__nsec = ns_per_s };
    var result = try at_min_plus_one.sub(one_sec);
    try testing.expectEqual(Duration.duration_range_ns.min, result.__nsec);

    // boundary case: exactly at max must work
    var at_max_minus_one = Duration{ .__nsec = Duration.duration_range_ns.max - ns_per_s };
    const neg_one_sec = Duration{ .__nsec = -ns_per_s };
    result = try at_max_minus_one.sub(neg_one_sec);
    try testing.expectEqual(Duration.duration_range_ns.max, result.__nsec);

    // subClip() clamps to min_sec when underflow occurs
    var clipped = min_dur.subClip(one_ns);
    try testing.expectEqual(Duration.duration_range_ns.min, clipped.__nsec);

    // subClip() clamps to max_sec when overflow occurs
    clipped = max_dur.subClip(neg_one_ns);
    try testing.expectEqual(Duration.duration_range_ns.max, clipped.__nsec);

    // zero subtraction edge cases
    var zero = Duration{};
    result = try max_dur.sub(zero);
    try testing.expectEqual(Duration.duration_range_ns.max, result.__nsec);

    result = try min_dur.sub(zero);
    try testing.expectEqual(Duration.duration_range_ns.min, result.__nsec);

    // subtracting from zero
    result = try zero.sub(Duration{ .__nsec = 1_500_000_000 });
    try testing.expectEqual(@as(i96, -1_500_000_000), result.__nsec);
}

const TestCaseISODur = struct {
    string: []const u8 = "",
    fields: Duration.RelativeDelta = .{},
    duration: Duration = .{},
};

test "iso duration parser, valid input" {
    const cases = [_]TestCaseISODur{
        .{
            .string = "P1Y2M",
            .fields = .{ .years = 1, .months = 2 },
        },
        .{
            .string = "P1M",
            .fields = .{ .years = 0, .months = 1 },
        },
        .{
            .string = "P1Y0M",
            .fields = .{ .years = 1, .months = 0 },
        },
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
            .string = "P1MT2M",
            .fields = .{ .months = 1, .minutes = 2 },
        },
        .{
            .string = "P1M7WT7M",
            .fields = .{ .months = 1, .weeks = 7, .minutes = 7 },
        },
    };

    for (cases) |case| {
        const fields = try Duration.RelativeDelta.fromISO8601(case.string);
        try testing.expectEqual(case.fields, fields);
        if (fields.years != 0 or fields.months != 0)
            try testing.expectError(ZdtError.OutOfRange, Duration.fromISO8601(case.string));
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
            .duration = .{ .__nsec = -(46 * 60 + 59) * ns_per_s - 789_000_000 },
        },
        .{
            .string = "PT4H5M6.789S",
            .duration = .{ .__nsec = (4 * 3600 + 5 * 60 + 6) * ns_per_s + 789_000_000 },
        },
        .{
            .string = "P1DT13H12.789000001S",
            .duration = .{ .__nsec = (s_per_day + 13 * 3600 + 12) * ns_per_s + 789_000_001 },
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
        .{ .string = "PT7HT7S", .expected = ZdtError.InvalidFormat },
        .{ .string = "PT7D", .expected = ZdtError.InvalidFormat },
        .{ .string = "P7HT7S", .expected = ZdtError.InvalidFormat },
        .{ .string = "P7S7M", .expected = ZdtError.InvalidFormat },
        .{ .string = "P7W7M", .expected = ZdtError.InvalidFormat },
        .{ .string = "P7.1W", .expected = ZdtError.InvalidCharacter },
        .{ .string = "P.1S", .expected = ZdtError.InvalidFormat },
        .{ .string = "P-7D", .expected = ZdtError.InvalidFormat },
        .{ .string = "P7M7M", .expected = ZdtError.InvalidFormat },
        .{ .string = "PT3HT4S", .expected = ZdtError.InvalidFormat },
        .{ .string = "P7M7S", .expected = ZdtError.InvalidFormat },
        .{ .string = "PT7M7M", .expected = ZdtError.InvalidFormat },
        .{ .string = "P7M7MT7S", .expected = ZdtError.InvalidFormat },
        .{ .string = "−PT7D", .expected = ZdtError.InvalidFormat },
        .{ .string = "PT59,789S", .expected = ZdtError.InvalidCharacter },
        .{ .string = "PT59.789M", .expected = ZdtError.InvalidCharacter },
        .{ .string = "P2020-01-01T00-00-01", .expected = ZdtError.InvalidFormat },
        .{ .string = "P20200101T000001", .expected = ZdtError.InvalidFormat },
        .{ .string = "-PT;0H46M59.789S", .expected = ZdtError.InvalidFormat },
        .{ .string = "yPT0H46M59.789S", .expected = ZdtError.InvalidFormat },
        .{ .string = "-P--T0H46M59.789S", .expected = ZdtError.InvalidFormat },
        .{ .string = "P1Y2M3DT4K5M6.789S", .expected = ZdtError.InvalidFormat },
        .{ .string = "PX2Y3M4DT5H6M7.89S", .expected = ZdtError.InvalidFormat },
        .{ .string = "P999Y0M0D 0H0M0.123S", .expected = ZdtError.InvalidFormat },
        .{ .string = "P+999Y0M0DT0H0M0.123S", .expected = ZdtError.InvalidFormat },
        .{ .string = "P3Y4M5DT6H7M8.9>", .expected = ZdtError.InvalidFormat },
        .{ .string = "P-+5Y6M7DT8H9M10.111000001S", .expected = ZdtError.InvalidFormat },
        .{ .string = "P7Y8M9DT10H11M12;123S", .expected = ZdtError.InvalidCharacter },
        .{ .string = "P-8Y9M10XT11H12M13.145S", .expected = ZdtError.InvalidFormat },
        .{ .string = "-P9Y10M11DT12H13M14.156s", .expected = ZdtError.InvalidFormat },
        .{ .string = "UwKMxofSAIQSil8gW", .expected = ZdtError.InvalidFormat },
        .{ .string = "gikNDeWiEh4yRt01haAPWqxQWOUSG2hC3EWSiAn3BNnt", .expected = ZdtError.InvalidFormat },
        .{ .string = "PT1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000S", .expected = ZdtError.InvalidFormat },

        // designator order / structure
        .{ .string = "P1M1Y", .expected = ZdtError.InvalidFormat },
        .{ .string = "PT1S1M", .expected = ZdtError.InvalidFormat },
        .{ .string = "PT1M1H", .expected = ZdtError.InvalidFormat },
        .{ .string = "P1DT", .expected = ZdtError.InvalidFormat },
        .{ .string = "pt1h", .expected = ZdtError.InvalidFormat },
        .{ .string = "P1d", .expected = ZdtError.InvalidFormat },
        .{ .string = "PT1H1MT", .expected = ZdtError.InvalidFormat },
        .{ .string = "P1T1H", .expected = ZdtError.InvalidFormat },

        // sign / whitespace / separators
        .{ .string = "-P1Y-2M", .expected = ZdtError.InvalidFormat },
        .{ .string = "P1D ", .expected = ZdtError.InvalidFormat },
        .{ .string = "P-1D ", .expected = ZdtError.InvalidFormat },
        .{ .string = " P1D", .expected = ZdtError.InvalidFormat },
        .{ .string = "P1,5D", .expected = ZdtError.InvalidCharacter },
        .{ .string = "PT1H,5M", .expected = ZdtError.InvalidCharacter },

        // fraction edge cases
        .{ .string = "PT5.S", .expected = ZdtError.InvalidCharacter },
        .{ .string = "PT.5S", .expected = ZdtError.InvalidFormat },
        .{ .string = "PT1.2.3S", .expected = ZdtError.InvalidCharacter },
        .{ .string = "PT0.5H", .expected = ZdtError.InvalidCharacter },
        .{ .string = "P1.5W", .expected = ZdtError.InvalidCharacter },

        // overflow boundaries
        .{ .string = "PT4294967296S", .expected = ZdtError.Overflow },
        .{ .string = "PT4294967296M", .expected = ZdtError.Overflow },
        .{ .string = "PT4294967296H", .expected = ZdtError.Overflow },
        .{ .string = "P4294967296D", .expected = ZdtError.Overflow },
        .{ .string = "P4294967296W", .expected = ZdtError.Overflow },
        .{ .string = "P4294967296M", .expected = ZdtError.Overflow },
        .{ .string = "P4294967296Y", .expected = ZdtError.Overflow },

        // minimal / degenerate
        .{ .string = "", .expected = ZdtError.InvalidFormat },
        .{ .string = "0", .expected = ZdtError.InvalidFormat },
        .{ .string = "P", .expected = ZdtError.InvalidFormat },
        .{ .string = "-P", .expected = ZdtError.InvalidFormat },
        .{ .string = "T5S", .expected = ZdtError.InvalidFormat },
        .{ .string = "P5S", .expected = ZdtError.InvalidFormat },
        .{ .string = "PT", .expected = ZdtError.InvalidFormat },
        .{ .string = "P0", .expected = ZdtError.InvalidFormat },
        .{ .string = "-PT", .expected = ZdtError.InvalidFormat },
    };

    for (cases) |case| {
        try testing.expectError(case.expected, Duration.RelativeDelta.fromISO8601(case.string));
    }
}

test "iso duration valid edge cases" {
    const cases = [_]TestCaseISODur{
        .{ // smallest representable fraction
            .string = "PT0.000000001S",
            .duration = .{ .__nsec = 1 },
        },
        .{ // max u32 seconds and nanoseconds
            .string = "PT4294967295.999999999S",
            .duration = .{ .__nsec = u32_max * ns_per_s + 999999999 },
        },
        .{ // shortest form
            .string = "P0D",
            .duration = .{},
        },
        .{
            .string = "-P0D",
            .duration = .{},
        },
        .{ // weeks alone, positive and negative
            .string = "P1W",
            .duration = .{ .__nsec = 7 * s_per_day * ns_per_s },
        },
        .{
            .string = "-P1W",
            .duration = .{ .__nsec = -(7 * s_per_day) * ns_per_s },
        },
        .{ // max u32 days
            .string = "P4294967295D",
            .duration = .{ .__nsec = u32_max * s_per_day * ns_per_s },
        },
        .{ // max u32 weeks
            .string = "P4294967295W",
            .duration = .{ .__nsec = u32_max * s_per_day * 7 * ns_per_s },
        },
        .{ // all maxed
            .string = "P4294967295W4294967295DT4294967295H4294967295M4294967295.999999999S",
            .duration = .{
                .__nsec = (@as(i96, u32_max) * s_per_day * 7 + // weeks
                    @as(i96, u32_max) * s_per_day + // days
                    @as(i96, u32_max) * 3600 + // hours
                    @as(i96, u32_max) * 60 + // minutes
                    @as(i96, u32_max)) * ns_per_s + // seconds
                    999999999, // nanos
            },
        },
        // absolute duration type cannot represent months / years
    };

    for (cases) |case| {
        try testing.expectEqual(case.duration, try Duration.fromISO8601(case.string));
    }
}

test "Duration.fromISO8601 rejects ambiguous units" {
    try testing.expectError(ZdtError.OutOfRange, Duration.fromISO8601("P1M"));
    try testing.expectError(ZdtError.OutOfRange, Duration.fromISO8601("P1Y"));
    try testing.expectError(ZdtError.OutOfRange, Duration.fromISO8601("P1Y0M"));
}

test "relative delta normalizer" {
    // nanoseconds above 999_999_999 carry into whole seconds
    var rd = Duration.RelativeDelta{ .nanoseconds = ns_per_s + 1 };
    var rd_norm = try rd.normalize();
    try testing.expectEqual(1, rd_norm.nanoseconds);
    try testing.expectEqual(1, rd_norm.seconds);

    rd = Duration.RelativeDelta{ .nanoseconds = u32_max };
    rd_norm = try rd.normalize();
    try testing.expectEqual(4, rd_norm.seconds);
    try testing.expectEqual(294_967_295, rd_norm.nanoseconds);

    // same for minutes >= 60 etc.
    rd = Duration.RelativeDelta{ .seconds = 61 };
    rd_norm = try rd.normalize();
    try testing.expectEqual(1, rd_norm.seconds);
    try testing.expectEqual(1, rd_norm.minutes);

    // degenerate, but representable: value must be preserved
    rd = Duration.RelativeDelta{
        .nanoseconds = u32_max, // incorrect; must be max. 999_999_999
        .seconds = u32_max,
        .minutes = u32_max,
    };
    rd_norm = try rd.normalize();
    const d = Duration{
        .__nsec = u32_max + u32_max * ns_per_s + u32_max * ns_per_s * s_per_min,
    };
    try testing.expectEqual(d, rd_norm.toDuration());

    // boundary: max weeks + 6 days is exactly representable
    rd = Duration.RelativeDelta{ .weeks = u32_max, .days = 6 };
    rd_norm = try rd.normalize();
    try testing.expectEqual(u32_max, rd_norm.weeks);
    try testing.expectEqual(6, rd_norm.days);

    // boundary: one more day saturates 'weeks' at u32 max; the excess is
    // carried into 'days' -- still value-preserving, no error:
    rd = Duration.RelativeDelta{ .weeks = u32_max, .days = 7 };
    rd_norm = try rd.normalize();
    try testing.expectEqual(u32_max, rd_norm.weeks);
    try testing.expectEqual(7, rd_norm.days);

    // degenerate: all quantities up to nanoseconds at max. The seconds field
    // saturates and the remainder (u32_max ns) cannot be represented as a
    // sub-second fraction (< 1 s): OutOfRange.
    rd = Duration.RelativeDelta{
        .nanoseconds = u32_max, // incorrect; must be max. 999_999_999
        .seconds = u32_max,
        .minutes = u32_max,
        .hours = u32_max,
        .days = u32_max,
        .weeks = u32_max,
    };
    try testing.expectError(ZdtError.OutOfRange, rd.normalize());

    // 12 months are exactly one year: redistributed, other fields untouched
    rd = Duration.RelativeDelta{ .years = 1, .months = 13, .days = 1 };
    rd_norm = try rd.normalize();
    try testing.expectEqual(2, rd_norm.years);
    try testing.expectEqual(1, rd_norm.months);
    try testing.expectEqual(1, rd_norm.days);

    // years already maxed: the excess stays in months (value-preserving);
    // u32_max years + u32_max months redistribute to u32_max years + u32_max months
    rd = Duration.RelativeDelta{ .years = u32_max, .months = u32_max };
    rd_norm = try rd.normalize();
    try testing.expectEqual(u32_max, rd_norm.years);
    try testing.expectEqual(u32_max, rd_norm.months);
    // months_total is preserved: 13 * u32_max months
    try testing.expectEqual(@as(u64, u32_max) * 13, @as(u64, rd_norm.years) * 12 + rd_norm.months);
}

test "relative delta normalizer, from ISO8601" {
    const cases = [_]TestCaseISODur{
        .{
            .string = "PT6.789S",
            .fields = .{ .seconds = 6, .nanoseconds = 789000000, .negative = false },
            .duration = .{ .__nsec = 6 * ns_per_s + 789000000 },
        },
        .{
            .string = "-PT6.789S",
            .fields = .{ .seconds = 6, .nanoseconds = 789000000, .negative = true },
            .duration = .{ .__nsec = -6 * ns_per_s - 789000000 },
        },
        .{
            .string = "PT61.789S",
            .fields = .{ .minutes = 1, .seconds = 1, .nanoseconds = 789000000 },
            .duration = .{ .__nsec = 61 * ns_per_s + 789000000 },
        },
        .{
            .string = "PT60M",
            .fields = .{ .hours = 1 },
            .duration = .{ .__nsec = 3600 * ns_per_s },
        },
        .{
            .string = "-P1DT1H1M",
            .fields = .{ .days = 1, .hours = 1, .minutes = 1, .negative = true },
            .duration = .{ .__nsec = -(s_per_day + 3600 + 60) * ns_per_s },
        },
        .{
            .string = "-PT24H60M60S",
            .fields = .{ .days = 1, .hours = 1, .minutes = 1, .negative = true },
            .duration = .{ .__nsec = -(s_per_day + 3600 + 60) * ns_per_s },
        },
        .{
            .string = "P1W2DT3H4M5S",
            .fields = .{ .weeks = 1, .days = 2, .hours = 3, .minutes = 4, .seconds = 5 },
            .duration = .{ .__nsec = (9 * s_per_day + 3 * 3600 + 4 * 60 + 5) * ns_per_s },
        },
        .{
            .string = "-P1W2DT3H4M5S",
            .fields = .{ .weeks = 1, .days = 2, .hours = 3, .minutes = 4, .seconds = 5, .negative = true },
            .duration = .{ .__nsec = -(9 * s_per_day + 3 * 3600 + 4 * 60 + 5) * ns_per_s },
        },
        .{
            .string = "PT4294967295S",
            .fields = .{ .weeks = 7101, .days = 3, .hours = 6, .minutes = 28, .seconds = 15 },
            .duration = .{ .__nsec = (7 * 7101 * s_per_day + 3 * s_per_day + 6 * 3600 + 28 * 60 + 15) * ns_per_s },
        },
        // boundary cases: exactly one day / week must carry over
        .{
            .string = "PT24H",
            .fields = .{ .days = 1 },
            .duration = .{ .__nsec = s_per_day * ns_per_s },
        },
        .{
            .string = "P7D",
            .fields = .{ .weeks = 1 },
            .duration = .{ .__nsec = 7 * s_per_day * ns_per_s },
        },
        .{
            .string = "PT48H",
            .fields = .{ .days = 2 },
            .duration = .{ .__nsec = 2 * s_per_day * ns_per_s },
        },
        .{
            .string = "P14D",
            .fields = .{ .weeks = 2 },
            .duration = .{ .__nsec = 14 * s_per_day * ns_per_s },
        },
    };

    for (cases) |case| {
        const fields = try Duration.RelativeDelta.fromISO8601(case.string);
        const normalized_fields = try fields.normalize();
        const dur = Duration.RelativeDelta.fromDuration(&case.duration);
        try testing.expectEqual(case.fields, normalized_fields);
        try testing.expectEqual(normalized_fields, dur);
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

test "RelativeDelta toDuration, roundtrip and error cases" {
    // roundtrip: Duration -> RelativeDelta -> Duration
    const cases = [_]Duration{
        try Duration.fromISO8601("PT1H2M3.5S"),
        try Duration.fromISO8601("P1W2DT3H"),
        try Duration.fromISO8601("-P10DT0.001S"),
        Duration{},
    };
    for (cases) |case| {
        const delta = Duration.RelativeDelta.fromDuration(&case);
        const roundtrip = try Duration.RelativeDelta.toDuration(delta);
        try testing.expectEqual(case, roundtrip);
    }

    // years / months are not convertible to a fixed Duration
    var delta = Duration.RelativeDelta{ .years = 1 };
    var err = Duration.RelativeDelta.toDuration(delta);
    try testing.expectError(ZdtError.OutOfRange, err);

    delta = Duration.RelativeDelta{ .months = 1 };
    err = Duration.RelativeDelta.toDuration(delta);
    try testing.expectError(ZdtError.OutOfRange, err);

    // negative durations keep their sign
    const neg = try Duration.fromISO8601("-P1DT0.000000001S");
    const delta_neg = Duration.RelativeDelta.fromDuration(&neg);
    try testing.expectEqual(true, delta_neg.negative);
    const back = try Duration.RelativeDelta.toDuration(delta_neg);
    try testing.expectEqual(neg, back);

    const rd_max = Duration.RelativeDelta{
        .weeks = (1 << 32) - 1,
        .days = (1 << 32) - 1,
        .hours = (1 << 32) - 1,
        .minutes = (1 << 32) - 1,
        .seconds = (1 << 32) - 1,
        .nanoseconds = 999_999_999,
    };
    const rd_dur_max = try rd_max.toDuration();
    try testing.expectEqual(rd_max, Duration.RelativeDelta.fromDuration(&rd_dur_max));
}

test "parse negative fractional ISO duration, value" {
    const d = try Duration.fromISO8601("-PT1.500000001S");
    try testing.expectEqual(-1_500_000_001, d.asNanoseconds());

    const d2 = try Duration.fromISO8601("-PT0.51S");
    try testing.expectEqual(-510_000_000, d2.asNanoseconds());
}

test "format negative fractional duration round-trips value" {
    const neg = Duration{ .__nsec = -1_500_000_000 };

    const delta = Duration.RelativeDelta.fromDuration(&neg);
    try testing.expectEqual(true, delta.negative);
    try testing.expectEqual(1, delta.seconds);
    try testing.expectEqual(500_000_000, delta.nanoseconds);

    var buf: [64]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try neg.format(&w);
    try testing.expectEqualStrings("-PT1.5S", w.buffered());
}
