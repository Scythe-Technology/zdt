// SPDX-FileCopyrightText: 2024-2026 Florian Obersteiner
// SPDX-FileContributor: Florian Obersteiner <f.obersteiner@posteo.de>
// SPDX-FileContributor: Michael Pollind <mpollind@gmail.com>
// SPDX-FileContributor: Ratakor <45130910+Ratakor@users.noreply.github.com>
//
// SPDX-License-Identifier: Unlicense

//! test timezone from a users's perspective (no internal functionality)

const builtin = @import("builtin");
const std = @import("std");
const testing = std.testing;

const zdt = @import("zdt");
const Datetime = zdt.Datetime;
const Duration = zdt.Duration;
const Tz = zdt.Timezone;
const UTCoffset = zdt.UTCoffset;
const ZdtError = zdt.ZdtError;

const log = std.log.scoped(.test_timezone);

test "utc" {
    var utc = UTCoffset.UTC;
    try testing.expect(utc.seconds_east == 0);
    try testing.expectEqualStrings(utc.designation(), "UTC");

    var utc_now = Datetime.nowUTC(testing.io);
    try testing.expectEqualStrings(utc_now.utc_offset.?.designation(), "UTC");

    try testing.expectEqualStrings(utc_now.tzName(), "UTC");
    try testing.expectEqualStrings(utc_now.tzAbbreviation(), "Z");
}

test "offset from seconds" {
    var off = try UTCoffset.fromSeconds(999, "hello world", false);
    try testing.expect(std.mem.eql(u8, off.designation(), "hello "));

    var err: zdt.ZdtError!zdt.UTCoffset = UTCoffset.fromSeconds(-99999, "invalid", false);
    try testing.expectError(ZdtError.InvalidOffset, err);
    err = UTCoffset.fromSeconds(99999, "invalid", false);
    try testing.expectError(ZdtError.InvalidOffset, err);

    off = try UTCoffset.fromSeconds(3600, "UTC+1", false);
    const dt = try Datetime.fromFields(.{ .year = 1970, .tz_options = .{ .utc_offset = off } });
    try testing.expect(dt.unix_sec == -3600);
    try testing.expect(dt.hour == 0);

    const dt_unix = try Datetime.fromUnix(0, Duration.Resolution.second, .{ .utc_offset = off });
    try testing.expect(dt_unix.unix_sec == 0);
    try testing.expect(dt_unix.hour == 1);

    var buf: [64]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    const string = "1970-01-01T00:00:00+01:00";
    const directive = "%Y-%m-%dT%H:%M:%S%:z";
    try dt.toString(directive, &w);
    try testing.expectEqualStrings(string, w.buffered());
}

test "mem error" {
    const allocator = testing.failing_allocator;
    const err = Tz.fromTzdata(testing.io, "UTC", allocator);
    try testing.expectError(ZdtError.OutOfMemory, err);
}

test "tz deinit is mem-safe" {
    // special case: UTC - actually has nothing to de-init; just the name data needs to be cleared
    var tz_utc = Tz.UTC;
    tz_utc.deinit();

    var tzinfo = try Tz.fromTzdata(testing.io, "Asia/Tokyo", testing.allocator);
    var dt = try Datetime.fromFields(.{ .year = 2027, .tz_options = .{ .tz = &tzinfo } });
    const off = dt.utc_offset.?;
    tzinfo.deinit();

    try testing.expect(std.meta.eql(off, dt.utc_offset.?));
    try testing.expectEqual(off.seconds_east, dt.utc_offset.?.seconds_east);
    try testing.expectEqualStrings("", dt.tzName());
    try testing.expectEqualStrings("JST", dt.tzAbbreviation());

    // FIXME : declaring the tz as a var carries a footgun;
    // having tz be something else does alter the datetime:
    // tzinfo = try Tz.fromTzdata(testing.io, "Asia/Kolkata", testing.allocator);
    // defer tzinfo.deinit();
    // try testing.expectEqualStrings("JST", dt.tzAbbreviation());
    // try testing.expectEqualStrings("", dt.tzName());

    // to be save: remove the tz:
    dt = try dt.tzLocalize(null);
    try testing.expectEqualStrings("", dt.tzAbbreviation());
    try testing.expectEqualStrings("", dt.tzName());

    // making a new zoned datetime with a de-initialized tz doesn't crash...
    dt = try dt.tzLocalize(.{ .tz = &tzinfo });
    // the datetime has an undefined time zone with an offset of zero:
    try testing.expectEqual(0, dt.utc_offset.?.seconds_east);
    try testing.expectEqualStrings("", dt.tzName());
    try testing.expectEqualStrings("", dt.tzAbbreviation());
}

test "tzfile tz manifests in Unix time" {
    var tzinfo = try Tz.fromTzdata(testing.io, "Europe/Berlin", testing.allocator);
    defer tzinfo.deinit();

    const dt = try Datetime.fromFields(.{ .year = 1970, .nanosecond = 1, .tz_options = .{ .tz = &tzinfo } });
    try testing.expect(dt.unix_sec == -3600);
    try testing.expect(dt.hour == 0);
    try testing.expect(dt.nanosecond == 1);
    try testing.expect(dt.tz != null);
    try testing.expectEqualStrings("Europe/Berlin", dt.tzName());
    try testing.expectEqualStrings("CET", dt.tzAbbreviation());

    const tzinfo_noalloc = try Tz.fromTzdata(testing.io, "Europe/Berlin", null);
    const dt_ = try Datetime.fromFields(.{ .year = 1970, .nanosecond = 1, .tz_options = .{ .tz = &tzinfo_noalloc } });
    try testing.expect(dt_.unix_sec == -3600);
    try testing.expect(dt_.hour == 0);
    try testing.expect(dt_.nanosecond == 1);
    try testing.expect(dt_.tz != null);
    try testing.expectEqualStrings("Europe/Berlin", dt_.tzName());
    try testing.expectEqualStrings("CET", dt_.tzAbbreviation());
}

test "local tz db, from specified or default prefix" {
    // NOTE : Windows does not use the IANA db, so we cannot test a 'local' prefix
    if (builtin.os.tag != .linux) return error.SkipZigTest;

    const db = Tz.tzdb_prefix;
    var tzinfo = try Tz.fromSystemTzdata(testing.io, "Europe/Berlin", db, testing.allocator);
    defer tzinfo.deinit();

    var dt = try Datetime.fromFields(.{ .year = 1970, .nanosecond = 1, .tz_options = .{ .tz = &tzinfo } });
    try testing.expect(dt.unix_sec == -3600);
    try testing.expect(dt.hour == 0);
    try testing.expect(dt.nanosecond == 1);
    try testing.expect(dt.tz != null);
    try testing.expectEqualStrings("CET", dt.tzAbbreviation());
    try testing.expectEqualStrings("Europe/Berlin", dt.tzName());
}

test "embedded tzdata" {
    var tzinfo = try Tz.fromTzdata(testing.io, "Europe/Berlin", testing.allocator);
    defer tzinfo.deinit();

    var dt = try Datetime.fromFields(.{ .year = 1970, .nanosecond = 1, .tz_options = .{ .tz = &tzinfo } });
    try testing.expect(dt.unix_sec == -3600);
    try testing.expect(dt.hour == 0);
    try testing.expect(dt.nanosecond == 1);
    try testing.expect(dt.tz != null);
    try testing.expectEqualStrings("CET", dt.tzAbbreviation());
    try testing.expectEqualStrings("Europe/Berlin", dt.tzName());

    const err = Tz.fromTzdata(testing.io, "Not/Defined", testing.allocator);
    try testing.expectError(ZdtError.TzUndefined, err);
}

test "fixed size tz" {
    var tzinfo_normal = try Tz.fromTzdata(testing.io, "Europe/Berlin", testing.allocator);
    defer tzinfo_normal.deinit();

    var tzinfo_fixed = try Tz.fromTzdata(testing.io, "Europe/Berlin", null);
    defer tzinfo_fixed.deinit();

    try testing.expectEqual(
        tzinfo_normal.rules.tzif.transitions.len,
        tzinfo_fixed.rules.tzif_fixedsize.n_transitions,
    );
    try testing.expectEqual(
        tzinfo_normal.rules.tzif.timetypes.len,
        tzinfo_fixed.rules.tzif_fixedsize.n_timetypes,
    );

    var off = try UTCoffset.atUnixtime(&tzinfo_fixed, 1735686000); // 2025-01-01
    try testing.expectEqual(3600, off.seconds_east);
    off = try UTCoffset.atUnixtime(&tzinfo_normal, 1735686000); // 2025-01-01
    try testing.expectEqual(3600, off.seconds_east);

    off = try UTCoffset.atUnixtime(&tzinfo_fixed, 1749546025); // 2025-06-10
    try testing.expectEqual(7200, off.seconds_east);
    off = try UTCoffset.atUnixtime(&tzinfo_normal, 1749546025); // 2025-06-10
    try testing.expectEqual(7200, off.seconds_east);

    var dt = try Datetime.fromFields(.{ .year = 2025, .nanosecond = 1, .tz_options = .{ .tz = &tzinfo_fixed } });
    try testing.expect(dt.tz != null);
    try testing.expect(dt.unix_sec == 1735686000);
    try testing.expect(dt.hour == 0);
    try testing.expect(dt.nanosecond == 1);
    try testing.expectEqualStrings("CET", dt.tzAbbreviation());
    try testing.expectEqualStrings("Europe/Berlin", dt.tzName());
    dt = try dt.addRelative(.{ .months = 7 });
    try testing.expectEqualStrings("CEST", dt.tzAbbreviation());
}

test "invalid tzfile name" {
    const db = Tz.tzdb_prefix;
    var err = Tz.fromSystemTzdata(testing.io, "this is not a tzname", db, testing.allocator);
    try testing.expectError(ZdtError.InvalidIdentifier, err);
    err = Tz.fromSystemTzdata(testing.io, "../test", db, testing.allocator);
    try testing.expectError(ZdtError.InvalidIdentifier, err);
    err = Tz.fromSystemTzdata(testing.io, "*=!?:.", db, testing.allocator);
    try testing.expectError(ZdtError.InvalidIdentifier, err);
}

test "local tz" {
    var now = try Datetime.now(testing.io, null);
    try testing.expect(now.tz == null);
    try testing.expect(now.utc_offset == null);

    var tzinfo = try Tz.tzLocal(testing.io, testing.allocator);
    defer tzinfo.deinit();
    now = try Datetime.now(testing.io, .{ .tz = &tzinfo });

    try testing.expect(now.tz != null);
    try testing.expect(!std.mem.eql(u8, now.tzName(), ""));
    try testing.expect(!std.mem.eql(u8, now.tzAbbreviation(), ""));
}

test "DST transitions" {
    var tzinfo = try Tz.fromTzdata(testing.io, "Europe/Berlin", testing.allocator);
    defer tzinfo.deinit();

    // DST off --> DST on (missing datetime), 2023-03-26
    var dt_std = try Datetime.fromUnix(1679792399, Duration.Resolution.second, .{ .tz = &tzinfo });
    var dt_dst = try Datetime.fromUnix(1679792400, Duration.Resolution.second, .{ .tz = &tzinfo });
    try testing.expect(!dt_std.utc_offset.?.is_dst);
    try testing.expect(dt_dst.utc_offset.?.is_dst);

    var buf: [64]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try dt_std.toString("%Y-%m-%dT%H:%M:%S%:z", &w);
    try testing.expectEqualStrings("2023-03-26T01:59:59+01:00", w.buffered());
    w = .fixed(&buf);

    try dt_dst.toString("%Y-%m-%dT%H:%M:%S%:z", &w);
    try testing.expectEqualStrings("2023-03-26T03:00:00+02:00", w.buffered());
    w = .fixed(&buf);

    // DST on --> DST off (duplicate datetime), 2023-10-29
    dt_dst = try Datetime.fromUnix(1698541199, Duration.Resolution.second, .{ .tz = &tzinfo });
    dt_std = try Datetime.fromUnix(1698541200, Duration.Resolution.second, .{ .tz = &tzinfo });
    try testing.expect(dt_dst.utc_offset.?.is_dst);
    try testing.expect(!dt_std.utc_offset.?.is_dst);

    try dt_dst.toString("%Y-%m-%dT%H:%M:%S%:z", &w);
    try testing.expectEqualStrings("2023-10-29T02:59:59+02:00", w.buffered());
    w = .fixed(&buf);

    try dt_std.toString("%Y-%m-%dT%H:%M:%S%:z", &w);
    try testing.expectEqualStrings("2023-10-29T02:00:00+01:00", w.buffered());
    w = .fixed(&buf);
}

test "wall diff vs. abs diff" {
    var tzinfo = try Tz.fromTzdata(testing.io, "Europe/Berlin", testing.allocator);
    defer tzinfo.deinit();

    // DST off --> DST on (missing datetime), 2023-03-26
    const dt_std = try Datetime.fromUnix(
        1679792399000000001,
        Duration.Resolution.nanosecond,
        .{ .tz = &tzinfo },
    );
    const dt_dst = try Datetime.fromUnix(
        1679792400000000002,
        Duration.Resolution.nanosecond,
        .{ .tz = &tzinfo },
    );
    try testing.expect(!dt_std.utc_offset.?.is_dst);
    try testing.expect(dt_dst.utc_offset.?.is_dst);

    const diff_abs = dt_std.diff(dt_dst); // just 1 sec and 1 nanosec
    const diff_wall = try dt_std.diffWall(dt_dst); // 1 hour, 1 sec and 1 nanosec
    try testing.expectEqual(
        @as(i128, -1000000001),
        diff_abs.toTimespanMultiple(Duration.Timespan.nanosecond),
    );
    try testing.expectEqual(
        @as(i128, -3601000000001),
        diff_wall.toTimespanMultiple(Duration.Timespan.nanosecond),
    );
}

test "tz has name and abbreviation" {
    var tzinfo = try Tz.fromTzdata(testing.io, "Europe/Berlin", testing.allocator);
    defer tzinfo.deinit();

    var dt = try Datetime.fromFields(.{ .year = 2023, .month = 2, .tz_options = .{ .tz = &tzinfo } });
    try testing.expectEqualStrings("Europe/Berlin", dt.tzName());
    try testing.expectEqualStrings("CET", dt.tzAbbreviation());

    dt = try Datetime.fromFields(.{ .year = 2023, .month = 8, .tz_options = .{ .tz = &tzinfo } });
    try testing.expectEqualStrings("Europe/Berlin", dt.tzName());
    try testing.expectEqualStrings("CEST", dt.tzAbbreviation());

    dt = try Datetime.fromUnix(1672527600, Duration.Resolution.second, .{ .tz = &tzinfo });
    try testing.expectEqualStrings("Europe/Berlin", dt.tzName());
    try testing.expectEqualStrings("CET", dt.tzAbbreviation());

    dt = try Datetime.fromUnix(1690840800, Duration.Resolution.second, .{ .tz = &tzinfo });
    try testing.expectEqualStrings("Europe/Berlin", dt.tzName());
    try testing.expectEqualStrings("CEST", dt.tzAbbreviation());
}

test "Paraguay has no DST anymore in 2025 (tzdb 2025a)" {
    var tzinfo = try Tz.fromTzdata(testing.io, "America/Asuncion", testing.allocator);
    defer tzinfo.deinit();
    const dt_early = try Datetime.fromFields(.{ .year = 2025, .month = 2, .tz_options = .{ .tz = &tzinfo } });
    const dt_late = try Datetime.fromFields(.{ .year = 2025, .month = 8, .tz_options = .{ .tz = &tzinfo } });
    try testing.expectEqual(-3 * 3600, dt_early.utc_offset.?.seconds_east);
    try testing.expectEqual(-3 * 3600, dt_late.utc_offset.?.seconds_east);
}

test "longest tz name" {
    var tzinfo = try Tz.fromTzdata(testing.io, "America/Argentina/ComodRivadavia", testing.allocator);
    defer tzinfo.deinit();
    var dt = try Datetime.fromFields(.{ .year = 2023, .month = 2, .tz_options = .{ .tz = &tzinfo } });
    try testing.expectEqualStrings("America/Argentina/ComodRivadavia", dt.tzName());
}

test "early LMT, late CEST" {
    var tzinfo = try Tz.fromTzdata(testing.io, "Europe/Berlin", testing.allocator);
    defer tzinfo.deinit();

    var dt = try Datetime.fromFields(.{ .year = 1880, .tz_options = .{ .tz = &tzinfo } });
    try testing.expectEqualStrings("LMT", dt.tzAbbreviation());

    // this falls back to using the POSIX TZ from the tzif footer:
    dt = try Datetime.fromFields(.{ .year = 2500, .month = 8, .tz_options = .{ .tz = &tzinfo } });
    try testing.expectEqualStrings("CEST", dt.tzAbbreviation());
}

test "tz name and abbr correct after localize" {
    var tz_ny = try Tz.fromTzdata(testing.io, "America/New_York", testing.allocator);
    defer tz_ny.deinit();

    var now_local: Datetime = try Datetime.now(testing.io, .{ .tz = &tz_ny });
    try testing.expectEqualStrings("America/New_York", now_local.tzName());
    try testing.expect(now_local.tzAbbreviation().len > 0);

    now_local = try Datetime.now(testing.io, null);
    try testing.expect(now_local.tzAbbreviation().len == 0);
    now_local = try now_local.tzLocalize(.{ .tz = &tz_ny });
    try testing.expectEqualStrings("America/New_York", now_local.tzName());
    try testing.expect(now_local.tzAbbreviation().len > 0);

    // TODO :
    // const t = std.time.nanoTimestamp();
    // now_local = try Datetime.fromUnix(@intCast(t), Duration.Resolution.nanosecond, .{ .tz = &tz_ny });
    // try testing.expectEqualStrings("America/New_York", now_local.tzName());
    // try testing.expect(now_local.tzAbbreviation().len > 0);
    //
    // const t2 = std.time.timestamp();
    // now_local = try Datetime.fromUnix(t2, Duration.Resolution.second, .{ .tz = &tz_ny });
    // try testing.expectEqualStrings("America/New_York", now_local.tzName());
    // try testing.expect(now_local.tzAbbreviation().len > 0);

    const t3: i32 = 0;
    now_local = try Datetime.fromUnix(t3, Duration.Resolution.second, .{ .tz = &tz_ny });
    try testing.expectEqualStrings("America/New_York", now_local.tzName());
    try testing.expectEqualStrings("EST", now_local.tzAbbreviation());

    const t4: i32 = 1690840800;
    now_local = try Datetime.fromUnix(t4, Duration.Resolution.second, .{ .tz = &tz_ny });
    try testing.expectEqualStrings("America/New_York", now_local.tzName());
    try testing.expectEqualStrings("EDT", now_local.tzAbbreviation());
}

test "tz name and abbr correct after conversion" {
    var tz_berlin = try Tz.fromTzdata(testing.io, "Europe/Berlin", testing.allocator);
    defer tz_berlin.deinit();
    var tz_denver = try Tz.fromTzdata(testing.io, "America/Denver", testing.allocator);
    defer tz_denver.deinit();

    var dt = try Datetime.fromFields(.{ .year = 2023, .tz_options = .{ .tz = &tz_berlin } });
    var converted: Datetime = try dt.tzConvert(.{ .tz = &tz_denver });
    try testing.expectEqualStrings("Europe/Berlin", dt.tzName());
    try testing.expectEqualStrings("CET", dt.tzAbbreviation());
    try testing.expectEqualStrings("America/Denver", converted.tzName());
    try testing.expectEqualStrings("MST", converted.tzAbbreviation());

    dt = try Datetime.fromFields(.{ .year = 2023, .month = 8, .tz_options = .{ .tz = &tz_berlin } });
    converted = try dt.tzConvert(.{ .tz = &tz_denver });
    try testing.expectEqualStrings("Europe/Berlin", dt.tzName());
    try testing.expectEqualStrings("CEST", dt.tzAbbreviation());
    try testing.expectEqualStrings("America/Denver", converted.tzName());
    try testing.expectEqualStrings("MDT", converted.tzAbbreviation());
}

test "non-existent datetime" {
    var tzinfo = try Tz.fromTzdata(testing.io, "Europe/Berlin", testing.allocator);
    defer tzinfo.deinit();

    var dt = Datetime.fromFields(.{ .year = 2023, .month = 3, .day = 26, .hour = 2, .tz_options = .{ .tz = &tzinfo } });
    try testing.expectError(ZdtError.NonexistentDatetime, dt);

    var tzinfo_ = try Tz.fromTzdata(testing.io, "America/Denver", testing.allocator);
    defer tzinfo_.deinit();
    dt = Datetime.fromFields(.{ .year = 2023, .month = 3, .day = 12, .hour = 2, .minute = 59, .second = 59, .tz_options = .{ .tz = &tzinfo_ } });
    try testing.expectError(ZdtError.NonexistentDatetime, dt);
}

test "ambiguous datetime" {
    var tz_berlin = try Tz.fromTzdata(testing.io, "Europe/Berlin", testing.allocator);
    defer tz_berlin.deinit();

    var dt = Datetime.fromFields(.{ .year = 2023, .month = 10, .day = 29, .hour = 2, .tz_options = .{ .tz = &tz_berlin } });
    try testing.expectError(ZdtError.AmbiguousDatetime, dt);

    var tz_denver = try Tz.fromTzdata(testing.io, "America/Denver", testing.allocator);
    defer tz_denver.deinit();
    dt = Datetime.fromFields(.{ .year = 2023, .month = 11, .day = 5, .hour = 1, .minute = 59, .second = 59, .tz_options = .{ .tz = &tz_denver } });
    try testing.expectError(ZdtError.AmbiguousDatetime, dt);

    // Nuuk tz transitions at 12 am:
    var tz_nuuk = try Tz.fromTzdata(testing.io, "America/Nuuk", testing.allocator);
    defer tz_nuuk.deinit();
    dt = Datetime.fromFields(.{ .year = 2024, .month = 10, .day = 26, .hour = 23, .minute = 30, .tz_options = .{ .tz = &tz_nuuk } });
    try testing.expectError(ZdtError.AmbiguousDatetime, dt);

    // Troll tz has a 2-hour DST transition:
    var tz_troll = try Tz.fromTzdata(testing.io, "Antarctica/Troll", testing.allocator);
    defer tz_troll.deinit();
    dt = Datetime.fromFields(.{ .year = 2024, .month = 10, .day = 27, .hour = 1, .minute = 30, .tz_options = .{ .tz = &tz_troll } });
    try testing.expectError(ZdtError.AmbiguousDatetime, dt);
    dt = Datetime.fromFields(.{ .year = 2024, .month = 10, .day = 27, .hour = 2, .minute = 30, .tz_options = .{ .tz = &tz_troll } });
    try testing.expectError(ZdtError.AmbiguousDatetime, dt);
}

test "ambiguous datetime / DST fold" {
    var tz_berlin = try Tz.fromTzdata(testing.io, "Europe/Berlin", testing.allocator);
    defer tz_berlin.deinit();

    // DST on, offset 7200 s
    var dt_early = try Datetime.fromFields(.{ .year = 2023, .month = 10, .day = 29, .hour = 2, .dst_fold = 0, .tz_options = .{ .tz = &tz_berlin } });
    // DST off, offset 3600 s
    var dt_late = try Datetime.fromFields(.{ .year = 2023, .month = 10, .day = 29, .hour = 2, .dst_fold = 1, .tz_options = .{ .tz = &tz_berlin } });
    try testing.expectEqual(7200, dt_early.utc_offset.?.seconds_east);
    try testing.expectEqual(3600, dt_late.utc_offset.?.seconds_east);

    var tz_mountain = try Tz.fromTzdata(testing.io, "America/Denver", testing.allocator);
    defer tz_mountain.deinit();
    dt_early = try Datetime.fromFields(.{ .year = 2023, .month = 11, .day = 5, .hour = 1, .minute = 59, .second = 59, .dst_fold = 0, .tz_options = .{ .tz = &tz_mountain } });
    dt_late = try Datetime.fromFields(.{ .year = 2023, .month = 11, .day = 5, .hour = 1, .minute = 59, .second = 59, .dst_fold = 1, .tz_options = .{ .tz = &tz_mountain } });
    try testing.expectEqual(-21600, dt_early.utc_offset.?.seconds_east);
    try testing.expectEqual(-25200, dt_late.utc_offset.?.seconds_east);
}

test "tz without transitions at UTC+9" {
    var tzinfo = try Tz.fromTzdata(testing.io, "Asia/Tokyo", testing.allocator);
    defer tzinfo.deinit();

    var dt = try Datetime.fromFields(.{ .year = 2023, .month = 3, .day = 26, .hour = 2, .tz_options = .{ .tz = &tzinfo } });
    try testing.expectEqual(@as(i32, 9 * 3600), dt.utc_offset.?.seconds_east);
    dt = try Datetime.fromFields(.{ .year = 2023, .month = 3, .day = 12, .hour = 2, .minute = 59, .second = 59, .tz_options = .{ .tz = &tzinfo } });
    try testing.expectEqual(@as(i32, 9 * 3600), dt.utc_offset.?.seconds_east);
    dt = try Datetime.fromFields(.{ .year = 2023, .month = 10, .day = 29, .hour = 2, .tz_options = .{ .tz = &tzinfo } });
    try testing.expectEqual(@as(i32, 9 * 3600), dt.utc_offset.?.seconds_east);
    dt = try Datetime.fromFields(.{ .year = 2023, .month = 11, .day = 5, .hour = 1, .minute = 59, .second = 59, .tz_options = .{ .tz = &tzinfo } });
    try testing.expectEqual(@as(i32, 9 * 3600), dt.utc_offset.?.seconds_east);
}

test "make datetime aware" {
    var tzinfo = try Tz.fromTzdata(testing.io, "Europe/Berlin", testing.allocator);
    defer tzinfo.deinit();

    const dt_naive = try Datetime.fromUnix(0, Duration.Resolution.second, null);
    try testing.expect(dt_naive.utc_offset == null);
    try testing.expect(dt_naive.tz == null);

    var dt_aware = try dt_naive.tzLocalize(.{ .tz = &tzinfo });
    try testing.expect(dt_aware.tz != null);
    try testing.expect(dt_aware.unix_sec != dt_naive.unix_sec);
    try testing.expect(dt_aware.unix_sec == -3600);
    try testing.expect(dt_aware.year == dt_naive.year);
    try testing.expect(dt_aware.day == dt_naive.day);
    try testing.expect(dt_aware.hour == dt_naive.hour);

    const naive_again = try dt_aware.tzLocalize(null);
    try testing.expect(std.meta.eql(dt_naive, naive_again));
}

test "replace tz in aware datetime" {
    var tz_Berlin = try Tz.fromTzdata(testing.io, "Europe/Berlin", testing.allocator);
    defer tz_Berlin.deinit();

    const dt_utc = Datetime.epoch;
    const dt_berlin = try dt_utc.tzLocalize(.{ .tz = &tz_Berlin });

    try testing.expect(dt_berlin.utc_offset != null);
    try testing.expect(dt_berlin.unix_sec != dt_utc.unix_sec);
    try testing.expect(dt_berlin.unix_sec == -3600);
    try testing.expect(dt_berlin.year == dt_utc.year);
    try testing.expect(dt_berlin.day == dt_utc.day);
    try testing.expect(dt_berlin.hour == dt_utc.hour);
}

test "replace tz fails for non-existent datetime in target tz" {
    var tz_Berlin = try Tz.fromTzdata(testing.io, "Europe/Berlin", testing.allocator);
    defer tz_Berlin.deinit();

    const dt_utc = try Datetime.fromFields(.{ .year = 2023, .month = 3, .day = 26, .hour = 2, .tz_options = .{ .utc_offset = UTCoffset.UTC } });
    const err = dt_utc.tzLocalize(.{ .tz = &tz_Berlin });

    try testing.expectError(ZdtError.NonexistentDatetime, err);
}

test "convert time zone" {
    var tzinfo = try Tz.fromTzdata(testing.io, "Europe/Berlin", testing.allocator);
    defer tzinfo.deinit();

    const dt_naive = try Datetime.fromUnix(42, Duration.Resolution.nanosecond, null);
    const err = dt_naive.tzConvert(.{ .tz = &tzinfo });
    try testing.expectError(ZdtError.TzUndefined, err);

    const dt_Berlin = try Datetime.fromUnix(42, Duration.Resolution.nanosecond, .{ .tz = &tzinfo });

    var tzinfo_ = try Tz.fromTzdata(testing.io, "America/New_York", testing.allocator);
    defer tzinfo_.deinit();
    const dt_NY = try dt_Berlin.tzConvert(.{ .tz = &tzinfo_ });

    try testing.expect(dt_Berlin.unix_sec == dt_NY.unix_sec);
    try testing.expect(dt_Berlin.nanosecond == dt_NY.nanosecond);
    try testing.expect(dt_Berlin.hour != dt_NY.hour);
}

test "floor to date changes UTC offset" {
    var tzinfo = try Tz.fromTzdata(testing.io, "Europe/Berlin", testing.allocator);
    defer tzinfo.deinit();

    var dt = try Datetime.fromFields(.{ .year = 2023, .month = 10, .day = 29, .hour = 5, .tz_options = .{ .tz = &tzinfo } });
    var dt_floored = try dt.floorTo(Duration.Timespan.day);
    try testing.expectEqual(@as(u8, 0), dt_floored.hour);
    try testing.expectEqual(@as(u8, 0), dt_floored.minute);
    try testing.expectEqual(@as(u8, 0), dt_floored.second);
    try testing.expectEqual(@as(i32, 3600), dt.utc_offset.?.seconds_east);
    try testing.expectEqual(@as(i32, 7200), dt_floored.utc_offset.?.seconds_east);

    dt = try Datetime.fromFields(.{ .year = 2023, .month = 3, .day = 26, .hour = 3, .tz_options = .{ .tz = &tzinfo } });
    dt_floored = try dt.floorTo(Duration.Timespan.day);
    try testing.expectEqual(@as(u8, 0), dt_floored.hour);
    try testing.expectEqual(@as(u8, 0), dt_floored.minute);
    try testing.expectEqual(@as(u8, 0), dt_floored.second);
    try testing.expectEqual(@as(i32, 7200), dt.utc_offset.?.seconds_east);
    try testing.expectEqual(@as(i32, 3600), dt_floored.utc_offset.?.seconds_east);
}

test "load a lot of zones" {
    const zones = [_][]const u8{
        "Africa/Abidjan",
        "Africa/Accra",
        "Africa/Addis_Ababa",
        "Africa/Algiers",
        "Africa/Asmara",
        "Africa/Asmera",
        "Africa/Bamako",
        "Africa/Bangui",
        "Africa/Banjul",
        "Africa/Bissau",
        "Africa/Blantyre",
        "Africa/Brazzaville",
        "Africa/Bujumbura",
        "Africa/Cairo",
        "Africa/Casablanca",
        "Africa/Ceuta",
        "Africa/Conakry",
        "Africa/Dakar",
        "Africa/Dar_es_Salaam",
        "Africa/Djibouti",
        "Africa/Douala",
        "Africa/El_Aaiun",
        "Africa/Freetown",
        "Africa/Gaborone",
        "Africa/Harare",
        "Africa/Johannesburg",
        "Africa/Juba",
        "Africa/Kampala",
        "Africa/Khartoum",
        "Africa/Kigali",
        "Africa/Kinshasa",
        "Africa/Lagos",
        "Africa/Libreville",
        "Africa/Lome",
        "Africa/Luanda",
        "Africa/Lubumbashi",
        "Africa/Lusaka",
        "Africa/Malabo",
        "Africa/Maputo",
        "Africa/Maseru",
        "Africa/Mbabane",
        "Africa/Mogadishu",
        "Africa/Monrovia",
        "Africa/Nairobi",
        "Africa/Ndjamena",
        "Africa/Niamey",
        "Africa/Nouakchott",
        "Africa/Ouagadougou",
        "Africa/Porto-Novo",
        "Africa/Sao_Tome",
        "Africa/Timbuktu",
        "Africa/Tripoli",
        "Africa/Tunis",
        "Africa/Windhoek",
        "America/Adak",
        "America/Anchorage",
        "America/Anguilla",
        "America/Antigua",
        "America/Araguaina",
        "America/Argentina/Buenos_Aires",
        "America/Argentina/Catamarca",
        "America/Argentina/ComodRivadavia",
        "America/Argentina/Cordoba",
        "America/Argentina/Jujuy",
        "America/Argentina/La_Rioja",
        "America/Argentina/Mendoza",
        "America/Argentina/Rio_Gallegos",
        "America/Argentina/Salta",
        "America/Argentina/San_Juan",
        "America/Argentina/San_Luis",
        "America/Argentina/Tucuman",
        "America/Argentina/Ushuaia",
        "America/Aruba",
        "America/Asuncion",
        "America/Atikokan",
        "America/Atka",
        "America/Bahia",
        "America/Bahia_Banderas",
        "America/Barbados",
        "America/Belem",
        "America/Belize",
        "America/Blanc-Sablon",
        "America/Boa_Vista",
        "America/Bogota",
        "America/Boise",
        "America/Buenos_Aires",
        "America/Cambridge_Bay",
        "America/Campo_Grande",
        "America/Cancun",
        "America/Caracas",
        "America/Catamarca",
        "America/Cayenne",
        "America/Cayman",
        "America/Chicago",
        "America/Chihuahua",
        "America/Ciudad_Juarez",
        "America/Coral_Harbour",
        "America/Cordoba",
        "America/Costa_Rica",
        "America/Creston",
        "America/Cuiaba",
        "America/Curacao",
        "America/Danmarkshavn",
        "America/Dawson",
        "America/Dawson_Creek",
        "America/Denver",
        "America/Detroit",
        "America/Dominica",
        "America/Edmonton",
        "America/Eirunepe",
        "America/El_Salvador",
        "America/Ensenada",
        "America/Fort_Nelson",
        "America/Fort_Wayne",
        "America/Fortaleza",
        "America/Glace_Bay",
        "America/Godthab",
        "America/Goose_Bay",
        "America/Grand_Turk",
        "America/Grenada",
        "America/Guadeloupe",
        "America/Guatemala",
        "America/Guayaquil",
        "America/Guyana",
        "America/Halifax",
        "America/Havana",
        "America/Hermosillo",
        "America/Indiana/Indianapolis",
        "America/Indiana/Knox",
        "America/Indiana/Marengo",
        "America/Indiana/Petersburg",
        "America/Indiana/Tell_City",
        "America/Indiana/Vevay",
        "America/Indiana/Vincennes",
        "America/Indiana/Winamac",
        "America/Indianapolis",
        "America/Inuvik",
        "America/Iqaluit",
        "America/Jamaica",
        "America/Jujuy",
        "America/Juneau",
        "America/Kentucky/Louisville",
        "America/Kentucky/Monticello",
        "America/Knox_IN",
        "America/Kralendijk",
        "America/La_Paz",
        "America/Lima",
        "America/Los_Angeles",
        "America/Louisville",
        "America/Lower_Princes",
        "America/Maceio",
        "America/Managua",
        "America/Manaus",
        "America/Marigot",
        "America/Martinique",
        "America/Matamoros",
        "America/Mazatlan",
        "America/Mendoza",
        "America/Menominee",
        "America/Merida",
        "America/Metlakatla",
        "America/Mexico_City",
        "America/Miquelon",
        "America/Moncton",
        "America/Monterrey",
        "America/Montevideo",
        "America/Montreal",
        "America/Montserrat",
        "America/Nassau",
        "America/New_York",
        "America/Nipigon",
        "America/Nome",
        "America/Noronha",
        "America/North_Dakota/Beulah",
        "America/North_Dakota/Center",
        "America/North_Dakota/New_Salem",
        "America/Nuuk",
        "America/Ojinaga",
        "America/Panama",
        "America/Pangnirtung",
        "America/Paramaribo",
        "America/Phoenix",
        "America/Port-au-Prince",
        "America/Port_of_Spain",
        "America/Porto_Acre",
        "America/Porto_Velho",
        "America/Puerto_Rico",
        "America/Punta_Arenas",
        "America/Rainy_River",
        "America/Rankin_Inlet",
        "America/Recife",
        "America/Regina",
        "America/Resolute",
        "America/Rio_Branco",
        "America/Rosario",
        "America/Santa_Isabel",
        "America/Santarem",
        "America/Santiago",
        "America/Santo_Domingo",
        "America/Sao_Paulo",
        "America/Scoresbysund",
        "America/Shiprock",
        "America/Sitka",
        "America/St_Barthelemy",
        "America/St_Johns",
        "America/St_Kitts",
        "America/St_Lucia",
        "America/St_Thomas",
        "America/St_Vincent",
        "America/Swift_Current",
        "America/Tegucigalpa",
        "America/Thule",
        "America/Thunder_Bay",
        "America/Tijuana",
        "America/Toronto",
        "America/Tortola",
        "America/Vancouver",
        "America/Virgin",
        "America/Whitehorse",
        "America/Winnipeg",
        "America/Yakutat",
        "America/Yellowknife",
        "Antarctica/Casey",
        "Antarctica/Davis",
        "Antarctica/DumontDUrville",
        "Antarctica/Macquarie",
        "Antarctica/Mawson",
        "Antarctica/McMurdo",
        "Antarctica/Palmer",
        "Antarctica/Rothera",
        "Antarctica/South_Pole",
        "Antarctica/Syowa",
        "Antarctica/Troll",
        "Antarctica/Vostok",
        "Arctic/Longyearbyen",
        "Asia/Aden",
        "Asia/Almaty",
        "Asia/Amman",
        "Asia/Anadyr",
        "Asia/Aqtau",
        "Asia/Aqtobe",
        "Asia/Ashgabat",
        "Asia/Ashkhabad",
        "Asia/Atyrau",
        "Asia/Baghdad",
        "Asia/Bahrain",
        "Asia/Baku",
        "Asia/Bangkok",
        "Asia/Barnaul",
        "Asia/Beirut",
        "Asia/Bishkek",
        "Asia/Brunei",
        "Asia/Calcutta",
        "Asia/Chita",
        "Asia/Choibalsan",
        "Asia/Chongqing",
        "Asia/Chungking",
        "Asia/Colombo",
        "Asia/Dacca",
        "Asia/Damascus",
        "Asia/Dhaka",
        "Asia/Dili",
        "Asia/Dubai",
        "Asia/Dushanbe",
        "Asia/Famagusta",
        "Asia/Gaza",
        "Asia/Harbin",
        "Asia/Hebron",
        "Asia/Ho_Chi_Minh",
        "Asia/Hong_Kong",
        "Asia/Hovd",
        "Asia/Irkutsk",
        "Asia/Istanbul",
        "Asia/Jakarta",
        "Asia/Jayapura",
        "Asia/Jerusalem",
        "Asia/Kabul",
        "Asia/Kamchatka",
        "Asia/Karachi",
        "Asia/Kashgar",
        "Asia/Kathmandu",
        "Asia/Katmandu",
        "Asia/Khandyga",
        "Asia/Kolkata",
        "Asia/Krasnoyarsk",
        "Asia/Kuala_Lumpur",
        "Asia/Kuching",
        "Asia/Kuwait",
        "Asia/Macao",
        "Asia/Macau",
        "Asia/Magadan",
        "Asia/Makassar",
        "Asia/Manila",
        "Asia/Muscat",
        "Asia/Nicosia",
        "Asia/Novokuznetsk",
        "Asia/Novosibirsk",
        "Asia/Omsk",
        "Asia/Oral",
        "Asia/Phnom_Penh",
        "Asia/Pontianak",
        "Asia/Pyongyang",
        "Asia/Qatar",
        "Asia/Qostanay",
        "Asia/Qyzylorda",
        "Asia/Rangoon",
        "Asia/Riyadh",
        "Asia/Saigon",
        "Asia/Sakhalin",
        "Asia/Samarkand",
        "Asia/Seoul",
        "Asia/Shanghai",
        "Asia/Singapore",
        "Asia/Srednekolymsk",
        "Asia/Taipei",
        "Asia/Tashkent",
        "Asia/Tbilisi",
        "Asia/Tehran",
        "Asia/Tel_Aviv",
        "Asia/Thimbu",
        "Asia/Thimphu",
        "Asia/Tokyo",
        "Asia/Tomsk",
        "Asia/Ujung_Pandang",
        "Asia/Ulaanbaatar",
        "Asia/Ulan_Bator",
        "Asia/Urumqi",
        "Asia/Ust-Nera",
        "Asia/Vientiane",
        "Asia/Vladivostok",
        "Asia/Yakutsk",
        "Asia/Yangon",
        "Asia/Yekaterinburg",
        "Asia/Yerevan",
        "Atlantic/Azores",
        "Atlantic/Bermuda",
        "Atlantic/Canary",
        "Atlantic/Cape_Verde",
        "Atlantic/Faeroe",
        "Atlantic/Faroe",
        "Atlantic/Jan_Mayen",
        "Atlantic/Madeira",
        "Atlantic/Reykjavik",
        "Atlantic/South_Georgia",
        "Atlantic/St_Helena",
        "Atlantic/Stanley",
        "Australia/ACT",
        "Australia/Adelaide",
        "Australia/Brisbane",
        "Australia/Broken_Hill",
        "Australia/Canberra",
        "Australia/Currie",
        "Australia/Darwin",
        "Australia/Eucla",
        "Australia/Hobart",
        "Australia/LHI",
        "Australia/Lindeman",
        "Australia/Lord_Howe",
        "Australia/Melbourne",
        "Australia/NSW",
        "Australia/North",
        "Australia/Perth",
        "Australia/Queensland",
        "Australia/South",
        "Australia/Sydney",
        "Australia/Tasmania",
        "Australia/Victoria",
        "Australia/West",
        "Australia/Yancowinna",
        "Brazil/Acre",
        "Brazil/DeNoronha",
        "Brazil/East",
        "Brazil/West",
        "CET",
        "CST6CDT",
        "Canada/Atlantic",
        "Canada/Central",
        "Canada/Eastern",
        "Canada/Mountain",
        "Canada/Newfoundland",
        "Canada/Pacific",
        "Canada/Saskatchewan",
        "Canada/Yukon",
        "Chile/Continental",
        "Chile/EasterIsland",
        "Cuba",
        "EET",
        "EST",
        "EST5EDT",
        "Egypt",
        "Eire",
        "Etc/GMT",
        "Etc/GMT+0",
        "Etc/GMT+1",
        "Etc/GMT+10",
        "Etc/GMT+11",
        "Etc/GMT+12",
        "Etc/GMT+2",
        "Etc/GMT+3",
        "Etc/GMT+4",
        "Etc/GMT+5",
        "Etc/GMT+6",
        "Etc/GMT+7",
        "Etc/GMT+8",
        "Etc/GMT+9",
        "Etc/GMT-0",
        "Etc/GMT-1",
        "Etc/GMT-10",
        "Etc/GMT-11",
        "Etc/GMT-12",
        "Etc/GMT-13",
        "Etc/GMT-14",
        "Etc/GMT-2",
        "Etc/GMT-3",
        "Etc/GMT-4",
        "Etc/GMT-5",
        "Etc/GMT-6",
        "Etc/GMT-7",
        "Etc/GMT-8",
        "Etc/GMT-9",
        "Etc/GMT0",
        "Etc/Greenwich",
        "Etc/UCT",
        "Etc/UTC",
        "Etc/Universal",
        "Etc/Zulu",
        "Europe/Amsterdam",
        "Europe/Andorra",
        "Europe/Astrakhan",
        "Europe/Athens",
        "Europe/Belfast",
        "Europe/Belgrade",
        "Europe/Berlin",
        "Europe/Bratislava",
        "Europe/Brussels",
        "Europe/Bucharest",
        "Europe/Budapest",
        "Europe/Busingen",
        "Europe/Chisinau",
        "Europe/Copenhagen",
        "Europe/Dublin",
        "Europe/Gibraltar",
        "Europe/Guernsey",
        "Europe/Helsinki",
        "Europe/Isle_of_Man",
        "Europe/Istanbul",
        "Europe/Jersey",
        "Europe/Kaliningrad",
        "Europe/Kiev",
        "Europe/Kirov",
        "Europe/Kyiv",
        "Europe/Lisbon",
        "Europe/Ljubljana",
        "Europe/London",
        "Europe/Luxembourg",
        "Europe/Madrid",
        "Europe/Malta",
        "Europe/Mariehamn",
        "Europe/Minsk",
        "Europe/Monaco",
        "Europe/Moscow",
        "Europe/Nicosia",
        "Europe/Oslo",
        "Europe/Paris",
        "Europe/Podgorica",
        "Europe/Prague",
        "Europe/Riga",
        "Europe/Rome",
        "Europe/Samara",
        "Europe/San_Marino",
        "Europe/Sarajevo",
        "Europe/Saratov",
        "Europe/Simferopol",
        "Europe/Skopje",
        "Europe/Sofia",
        "Europe/Stockholm",
        "Europe/Tallinn",
        "Europe/Tirane",
        "Europe/Tiraspol",
        "Europe/Ulyanovsk",
        "Europe/Uzhgorod",
        "Europe/Vaduz",
        "Europe/Vatican",
        "Europe/Vienna",
        "Europe/Vilnius",
        "Europe/Volgograd",
        "Europe/Warsaw",
        "Europe/Zagreb",
        "Europe/Zaporozhye",
        "Europe/Zurich",
        "Factory",
        "GB",
        "GB-Eire",
        "GMT",
        "GMT+0",
        "GMT-0",
        "GMT0",
        "Greenwich",
        "HST",
        "Hongkong",
        "Iceland",
        "Indian/Antananarivo",
        "Indian/Chagos",
        "Indian/Christmas",
        "Indian/Cocos",
        "Indian/Comoro",
        "Indian/Kerguelen",
        "Indian/Mahe",
        "Indian/Maldives",
        "Indian/Mauritius",
        "Indian/Mayotte",
        "Indian/Reunion",
        "Iran",
        "Israel",
        "Jamaica",
        "Japan",
        "Kwajalein",
        "Libya",
        "MET",
        "MST",
        "MST7MDT",
        "Mexico/BajaNorte",
        "Mexico/BajaSur",
        "Mexico/General",
        "NZ",
        "NZ-CHAT",
        "Navajo",
        "PRC",
        "PST8PDT",
        "Pacific/Apia",
        "Pacific/Auckland",
        "Pacific/Bougainville",
        "Pacific/Chatham",
        "Pacific/Chuuk",
        "Pacific/Easter",
        "Pacific/Efate",
        "Pacific/Enderbury",
        "Pacific/Fakaofo",
        "Pacific/Fiji",
        "Pacific/Funafuti",
        "Pacific/Galapagos",
        "Pacific/Gambier",
        "Pacific/Guadalcanal",
        "Pacific/Guam",
        "Pacific/Honolulu",
        "Pacific/Johnston",
        "Pacific/Kanton",
        "Pacific/Kiritimati",
        "Pacific/Kosrae",
        "Pacific/Kwajalein",
        "Pacific/Majuro",
        "Pacific/Marquesas",
        "Pacific/Midway",
        "Pacific/Nauru",
        "Pacific/Niue",
        "Pacific/Norfolk",
        "Pacific/Noumea",
        "Pacific/Pago_Pago",
        "Pacific/Palau",
        "Pacific/Pitcairn",
        "Pacific/Pohnpei",
        "Pacific/Ponape",
        "Pacific/Port_Moresby",
        "Pacific/Rarotonga",
        "Pacific/Saipan",
        "Pacific/Samoa",
        "Pacific/Tahiti",
        "Pacific/Tarawa",
        "Pacific/Tongatapu",
        "Pacific/Truk",
        "Pacific/Wake",
        "Pacific/Wallis",
        "Pacific/Yap",
        "Poland",
        "Portugal",
        "ROC",
        "ROK",
        "Singapore",
        "Turkey",
        "UCT",
        "US/Alaska",
        "US/Aleutian",
        "US/Arizona",
        "US/Central",
        "US/East-Indiana",
        "US/Eastern",
        "US/Hawaii",
        "US/Indiana-Starke",
        "US/Michigan",
        "US/Mountain",
        "US/Pacific",
        "US/Samoa",
        "UTC",
        "Universal",
        "W-SU",
        "WET",
        "Zulu",
    };

    for (zones) |zone| {
        var tz_a = try Tz.fromTzdata(testing.io, zone, testing.allocator);
        const dt_a = try Datetime.fromUnix(0, Duration.Resolution.second, .{ .tz = &tz_a });
        try testing.expect(dt_a.utc_offset != null);
        try testing.expectEqualStrings(zone, dt_a.tzName());
        tz_a.deinit();

        if (builtin.os.tag != .windows) {
            var tz_b = Tz.fromSystemTzdata(testing.io, zone, Tz.tzdb_prefix, testing.allocator) catch {
                log.warn("skip: tz file '{s}' not available on system", .{zone});
                continue;
            };
            const dt_b = try Datetime.fromUnix(0, Duration.Resolution.second, .{ .tz = &tz_b });
            try testing.expect(dt_b.utc_offset != null);
            try testing.expectEqualStrings(zone, dt_b.tzName());
            tz_b.deinit();
        }
    }
}

test "Canada / BC: permanent DST (2026+)" {
    var tz_BC = try Tz.fromTzdata(testing.io, "Canada/Pacific", null);
    defer tz_BC.deinit();

    // winter time offset is -8 hours
    const dt_no_DST = try Datetime.fromFields(.{ .year = 2026, .tz_options = .{ .tz = &tz_BC } });
    try testing.expectEqual(3600 * -8, dt_no_DST.utc_offset.?.seconds_east);
    try testing.expect(!dt_no_DST.isDST());

    // summer time / DST offset is -7 hours
    const dt_DST = try Datetime.fromFields(.{ .year = 2026, .month = 6, .tz_options = .{ .tz = &tz_BC } });
    try testing.expectEqual(3600 * -7, dt_DST.utc_offset.?.seconds_east);
    try testing.expect(dt_DST.isDST());

    // this is not considered DST anymore, but the offset remains
    const dt_still_DST_offset = try Datetime.fromFields(.{ .year = 2026, .month = 12, .tz_options = .{ .tz = &tz_BC } });
    try testing.expectEqual(3600 * -7, dt_still_DST_offset.utc_offset.?.seconds_east);
    try testing.expect(!dt_still_DST_offset.isDST());

    // next year / 2027 should not have DST
    const dt_DST_anymore = try Datetime.fromFields(.{ .year = 2027, .month = 6, .tz_options = .{ .tz = &tz_BC } });
    try testing.expectEqual(3600 * -7, dt_DST.utc_offset.?.seconds_east);
    try testing.expect(!dt_DST_anymore.isDST());
}

test "conversion between random time zones, no-alloc" {
    var tz_a = try Tz.fromTzdata(testing.io, "Africa/Luanda", null);
    var tz_b = try Tz.fromTzdata(testing.io, "Europe/Kaliningrad", null);

    var dt_a = try Datetime.fromUnix(-816207319, Duration.Resolution.second, .{ .tz = &tz_a });
    var dt_b = try Datetime.fromUnix(1921722761, Duration.Resolution.second, .{ .tz = &tz_b });
    var dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });

    var buf: [64]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);

    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("2030-11-24T04:52:41+01:00:00", w.buffered());
    w = .fixed(&buf);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("1944-02-20T04:44:41+01:00:00", w.buffered());

    tz_a = try Tz.fromTzdata(testing.io, "Europe/Sarajevo", null);
    tz_b = try Tz.fromTzdata(testing.io, "Pacific/Wallis", null);

    dt_a = try Datetime.fromUnix(1942114456, Duration.Resolution.second, .{ .tz = &tz_a });
    dt_b = try Datetime.fromUnix(-1893647018, Duration.Resolution.second, .{ .tz = &tz_b });
    dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });

    w = .fixed(&buf);
    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("1909-12-29T19:56:22+01:00:00", w.buffered());
    w = .fixed(&buf);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("2031-07-18T16:14:16+12:00:00", w.buffered());

    tz_a = try Tz.fromTzdata(testing.io, "America/Caracas", null);
    tz_b = try Tz.fromTzdata(testing.io, "Europe/Vienna", null);

    dt_a = try Datetime.fromUnix(-485869856, Duration.Resolution.second, .{ .tz = &tz_a });
    dt_b = try Datetime.fromUnix(-1894391592, Duration.Resolution.second, .{ .tz = &tz_b });
    dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });

    w = .fixed(&buf);
    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("1909-12-20T23:39:08-04:27:40", w.buffered());
    w = .fixed(&buf);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("1954-08-09T13:09:04+01:00:00", w.buffered());
}

// the following test is auto-generated by gen_test_tzones.py. do not edit this line and below.

test "conversion between random time zones" {
    var tz_a = try Tz.fromTzdata(testing.io, "Europe/Malta", testing.allocator);
    var tz_b = try Tz.fromTzdata(testing.io, "Europe/Samara", testing.allocator);

    var dt_a = try Datetime.fromUnix(-816207319, Duration.Resolution.second, .{ .tz = &tz_a });
    var dt_b = try Datetime.fromUnix(1921722761, Duration.Resolution.second, .{ .tz = &tz_b });
    var dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });

    var buf: [64]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);

    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("2030-11-24T04:52:41+01:00:00", w.buffered());
    w = .fixed(&buf);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("1944-02-20T07:44:41+04:00:00", w.buffered());

    tz_a.deinit();
    tz_b.deinit();

    tz_a = try Tz.fromTzdata(testing.io, "Indian/Maldives", testing.allocator);
    tz_b = try Tz.fromTzdata(testing.io, "Africa/Mogadishu", testing.allocator);

    dt_a = try Datetime.fromUnix(1942114456, Duration.Resolution.second, .{ .tz = &tz_a });
    dt_b = try Datetime.fromUnix(-1893647018, Duration.Resolution.second, .{ .tz = &tz_b });
    dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });

    w = .fixed(&buf);
    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("1909-12-29T23:50:22+04:54:00", w.buffered());
    w = .fixed(&buf);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("2031-07-18T07:14:16+03:00:00", w.buffered());

    tz_a.deinit();
    tz_b.deinit();

    tz_a = try Tz.fromTzdata(testing.io, "Europe/Stockholm", testing.allocator);
    tz_b = try Tz.fromTzdata(testing.io, "UTC", testing.allocator);

    dt_a = try Datetime.fromUnix(-1128113058, Duration.Resolution.second, .{ .tz = &tz_a });
    dt_b = try Datetime.fromUnix(1223021131, Duration.Resolution.second, .{ .tz = &tz_b });
    dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });

    w = .fixed(&buf);
    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("2008-10-03T10:05:31+02:00:00", w.buffered());
    w = .fixed(&buf);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("1934-04-03T03:15:42+00:00:00", w.buffered());

    tz_a.deinit();
    tz_b.deinit();

    tz_a = try Tz.fromTzdata(testing.io, "NZ-CHAT", testing.allocator);
    tz_b = try Tz.fromTzdata(testing.io, "America/Kentucky/Monticello", testing.allocator);

    dt_a = try Datetime.fromUnix(-485869856, Duration.Resolution.second, .{ .tz = &tz_a });
    dt_b = try Datetime.fromUnix(-1894391592, Duration.Resolution.second, .{ .tz = &tz_b });
    dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });

    w = .fixed(&buf);
    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("1909-12-21T16:21:48+12:15:00", w.buffered());
    w = .fixed(&buf);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("1954-08-09T06:09:04-06:00:00", w.buffered());

    tz_a.deinit();
    tz_b.deinit();

    tz_a = try Tz.fromTzdata(testing.io, "Pacific/Auckland", testing.allocator);
    tz_b = try Tz.fromTzdata(testing.io, "Europe/Stockholm", testing.allocator);

    dt_a = try Datetime.fromUnix(-999522008, Duration.Resolution.second, .{ .tz = &tz_a });
    dt_b = try Datetime.fromUnix(719055854, Duration.Resolution.second, .{ .tz = &tz_b });
    dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });

    w = .fixed(&buf);
    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("1992-10-14T22:44:14+13:00:00", w.buffered());
    w = .fixed(&buf);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("1938-04-30T11:59:52+01:00:00", w.buffered());

    tz_a.deinit();
    tz_b.deinit();

    tz_a = try Tz.fromTzdata(testing.io, "America/Coyhaique", testing.allocator);
    tz_b = try Tz.fromTzdata(testing.io, "America/Detroit", testing.allocator);

    dt_a = try Datetime.fromUnix(-1389478107, Duration.Resolution.second, .{ .tz = &tz_a });
    dt_b = try Datetime.fromUnix(-195234029, Duration.Resolution.second, .{ .tz = &tz_b });
    dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });

    w = .fixed(&buf);
    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("1963-10-25T04:19:31-04:00:00", w.buffered());
    w = .fixed(&buf);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("1925-12-20T20:51:33-05:00:00", w.buffered());

    tz_a.deinit();
    tz_b.deinit();

    tz_a = try Tz.fromTzdata(testing.io, "America/Indiana/Vevay", testing.allocator);
    tz_b = try Tz.fromTzdata(testing.io, "Atlantic/Faroe", testing.allocator);

    dt_a = try Datetime.fromUnix(794111713, Duration.Resolution.second, .{ .tz = &tz_a });
    dt_b = try Datetime.fromUnix(-1262529920, Duration.Resolution.second, .{ .tz = &tz_b });
    dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });

    w = .fixed(&buf);
    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("1929-12-29T03:14:40-06:00:00", w.buffered());
    w = .fixed(&buf);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("1995-03-02T02:35:13+00:00:00", w.buffered());

    tz_a.deinit();
    tz_b.deinit();

    tz_a = try Tz.fromTzdata(testing.io, "Europe/Nicosia", testing.allocator);
    tz_b = try Tz.fromTzdata(testing.io, "EET", testing.allocator);

    dt_a = try Datetime.fromUnix(-1846174622, Duration.Resolution.second, .{ .tz = &tz_a });
    dt_b = try Datetime.fromUnix(364596200, Duration.Resolution.second, .{ .tz = &tz_b });
    dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });

    w = .fixed(&buf);
    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("1981-07-21T23:43:20+03:00:00", w.buffered());
    w = .fixed(&buf);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("1911-07-02T07:17:50+01:34:52", w.buffered());

    tz_a.deinit();
    tz_b.deinit();

    tz_a = try Tz.fromTzdata(testing.io, "Atlantic/Bermuda", testing.allocator);
    tz_b = try Tz.fromTzdata(testing.io, "America/Eirunepe", testing.allocator);

    dt_a = try Datetime.fromUnix(1967326856, Duration.Resolution.second, .{ .tz = &tz_a });
    dt_b = try Datetime.fromUnix(142696408, Duration.Resolution.second, .{ .tz = &tz_b });
    dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });

    w = .fixed(&buf);
    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("1974-07-10T10:53:28-03:00:00", w.buffered());
    w = .fixed(&buf);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("2032-05-04T18:40:56-05:00:00", w.buffered());

    tz_a.deinit();
    tz_b.deinit();

    tz_a = try Tz.fromTzdata(testing.io, "Asia/Tbilisi", testing.allocator);
    tz_b = try Tz.fromTzdata(testing.io, "Asia/Novosibirsk", testing.allocator);

    dt_a = try Datetime.fromUnix(-865972273, Duration.Resolution.second, .{ .tz = &tz_a });
    dt_b = try Datetime.fromUnix(-639392452, Duration.Resolution.second, .{ .tz = &tz_b });
    dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });

    w = .fixed(&buf);
    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("1949-09-27T17:59:08+03:00:00", w.buffered());
    w = .fixed(&buf);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("1942-07-24T11:08:47+07:00:00", w.buffered());

    tz_a.deinit();
    tz_b.deinit();

    tz_a = try Tz.fromTzdata(testing.io, "Asia/Magadan", testing.allocator);
    tz_b = try Tz.fromTzdata(testing.io, "Navajo", testing.allocator);

    dt_a = try Datetime.fromUnix(-1571932065, Duration.Resolution.second, .{ .tz = &tz_a });
    dt_b = try Datetime.fromUnix(-782078436, Duration.Resolution.second, .{ .tz = &tz_b });
    dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });

    w = .fixed(&buf);
    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("1945-03-21T14:59:24+11:00:00", w.buffered());
    w = .fixed(&buf);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("1920-03-10T01:12:15-07:00:00", w.buffered());

    tz_a.deinit();
    tz_b.deinit();

    tz_a = try Tz.fromTzdata(testing.io, "Asia/Tomsk", testing.allocator);
    tz_b = try Tz.fromTzdata(testing.io, "Asia/Magadan", testing.allocator);

    dt_a = try Datetime.fromUnix(-1516539100, Duration.Resolution.second, .{ .tz = &tz_a });
    dt_b = try Datetime.fromUnix(986091715, Duration.Resolution.second, .{ .tz = &tz_b });
    dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });

    w = .fixed(&buf);
    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("2001-04-01T10:21:55+08:00:00", w.buffered());
    w = .fixed(&buf);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("1921-12-11T21:11:32+10:03:12", w.buffered());

    tz_a.deinit();
    tz_b.deinit();

    tz_a = try Tz.fromTzdata(testing.io, "Africa/Mbabane", testing.allocator);
    tz_b = try Tz.fromTzdata(testing.io, "America/Atka", testing.allocator);

    dt_a = try Datetime.fromUnix(-1215106914, Duration.Resolution.second, .{ .tz = &tz_a });
    dt_b = try Datetime.fromUnix(-487293440, Duration.Resolution.second, .{ .tz = &tz_b });
    dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });

    w = .fixed(&buf);
    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("1954-07-24T02:42:40+02:00:00", w.buffered());
    w = .fixed(&buf);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("1931-06-30T19:18:06-11:00:00", w.buffered());

    tz_a.deinit();
    tz_b.deinit();

    tz_a = try Tz.fromTzdata(testing.io, "WET", testing.allocator);
    tz_b = try Tz.fromTzdata(testing.io, "Africa/Lusaka", testing.allocator);

    dt_a = try Datetime.fromUnix(1367598722, Duration.Resolution.second, .{ .tz = &tz_a });
    dt_b = try Datetime.fromUnix(-1473054982, Duration.Resolution.second, .{ .tz = &tz_b });
    dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });

    w = .fixed(&buf);
    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("1923-04-28T18:03:38+00:00:00", w.buffered());
    w = .fixed(&buf);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("2013-05-03T18:32:02+02:00:00", w.buffered());

    tz_a.deinit();
    tz_b.deinit();

    tz_a = try Tz.fromTzdata(testing.io, "Asia/Kuching", testing.allocator);
    tz_b = try Tz.fromTzdata(testing.io, "Indian/Cocos", testing.allocator);

    dt_a = try Datetime.fromUnix(-260468215, Duration.Resolution.second, .{ .tz = &tz_a });
    dt_b = try Datetime.fromUnix(-1511958403, Duration.Resolution.second, .{ .tz = &tz_b });
    dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });

    w = .fixed(&buf);
    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("1922-02-02T18:54:37+07:21:20", w.buffered());
    w = .fixed(&buf);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("1961-09-30T14:13:05+06:30:00", w.buffered());

    tz_a.deinit();
    tz_b.deinit();

    tz_a = try Tz.fromTzdata(testing.io, "Europe/Vaduz", testing.allocator);
    tz_b = try Tz.fromTzdata(testing.io, "Canada/Mountain", testing.allocator);

    dt_a = try Datetime.fromUnix(824105261, Duration.Resolution.second, .{ .tz = &tz_a });
    dt_b = try Datetime.fromUnix(477126985, Duration.Resolution.second, .{ .tz = &tz_b });
    dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });

    w = .fixed(&buf);
    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("1985-02-13T08:16:25+01:00:00", w.buffered());
    w = .fixed(&buf);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("1996-02-11T23:07:41-07:00:00", w.buffered());

    tz_a.deinit();
    tz_b.deinit();

    tz_a = try Tz.fromTzdata(testing.io, "America/Paramaribo", testing.allocator);
    tz_b = try Tz.fromTzdata(testing.io, "Europe/Gibraltar", testing.allocator);

    dt_a = try Datetime.fromUnix(-444856409, Duration.Resolution.second, .{ .tz = &tz_a });
    dt_b = try Datetime.fromUnix(-2017440120, Duration.Resolution.second, .{ .tz = &tz_b });
    dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });

    w = .fixed(&buf);
    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("1906-01-26T20:17:20-03:40:40", w.buffered());
    w = .fixed(&buf);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("1955-11-27T04:46:31+00:00:00", w.buffered());

    tz_a.deinit();
    tz_b.deinit();

    tz_a = try Tz.fromTzdata(testing.io, "Pacific/Rarotonga", testing.allocator);
    tz_b = try Tz.fromTzdata(testing.io, "Europe/Moscow", testing.allocator);

    dt_a = try Datetime.fromUnix(2081029752, Duration.Resolution.second, .{ .tz = &tz_a });
    dt_b = try Datetime.fromUnix(230882752, Duration.Resolution.second, .{ .tz = &tz_b });
    dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });

    w = .fixed(&buf);
    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("1977-04-25T19:35:52-10:30:00", w.buffered());
    w = .fixed(&buf);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("2035-12-12T02:49:12+03:00:00", w.buffered());

    tz_a.deinit();
    tz_b.deinit();

    tz_a = try Tz.fromTzdata(testing.io, "Indian/Antananarivo", testing.allocator);
    tz_b = try Tz.fromTzdata(testing.io, "NZ", testing.allocator);

    dt_a = try Datetime.fromUnix(1751368983, Duration.Resolution.second, .{ .tz = &tz_a });
    dt_b = try Datetime.fromUnix(693621470, Duration.Resolution.second, .{ .tz = &tz_b });
    dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });

    w = .fixed(&buf);
    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("1991-12-25T03:37:50+03:00:00", w.buffered());
    w = .fixed(&buf);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("2025-07-01T23:23:03+12:00:00", w.buffered());

    tz_a.deinit();
    tz_b.deinit();

    tz_a = try Tz.fromTzdata(testing.io, "Asia/Famagusta", testing.allocator);
    tz_b = try Tz.fromTzdata(testing.io, "Pacific/Apia", testing.allocator);

    dt_a = try Datetime.fromUnix(715858672, Duration.Resolution.second, .{ .tz = &tz_a });
    dt_b = try Datetime.fromUnix(-373086081, Duration.Resolution.second, .{ .tz = &tz_b });
    dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });

    w = .fixed(&buf);
    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("1958-03-06T22:58:39+02:00:00", w.buffered());
    w = .fixed(&buf);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("1992-09-06T22:37:52-11:00:00", w.buffered());

    tz_a.deinit();
    tz_b.deinit();

    tz_a = try Tz.fromTzdata(testing.io, "Africa/Djibouti", testing.allocator);
    tz_b = try Tz.fromTzdata(testing.io, "Asia/Macao", testing.allocator);

    dt_a = try Datetime.fromUnix(-293022949, Duration.Resolution.second, .{ .tz = &tz_a });
    dt_b = try Datetime.fromUnix(-1445358615, Duration.Resolution.second, .{ .tz = &tz_b });
    dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });

    w = .fixed(&buf);
    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("1924-03-14T09:59:45+02:30:00", w.buffered());
    w = .fixed(&buf);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("1960-09-18T21:44:11+09:00:00", w.buffered());

    tz_a.deinit();
    tz_b.deinit();

    tz_a = try Tz.fromTzdata(testing.io, "Asia/Samarkand", testing.allocator);
    tz_b = try Tz.fromTzdata(testing.io, "Asia/Baghdad", testing.allocator);

    dt_a = try Datetime.fromUnix(560485083, Duration.Resolution.second, .{ .tz = &tz_a });
    dt_b = try Datetime.fromUnix(2064615505, Duration.Resolution.second, .{ .tz = &tz_b });
    dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });

    w = .fixed(&buf);
    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("2035-06-05T05:18:25+05:00:00", w.buffered());
    w = .fixed(&buf);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("1987-10-06T05:18:03+03:00:00", w.buffered());

    tz_a.deinit();
    tz_b.deinit();

    tz_a = try Tz.fromTzdata(testing.io, "Etc/GMT-10", testing.allocator);
    tz_b = try Tz.fromTzdata(testing.io, "Etc/GMT-1", testing.allocator);

    dt_a = try Datetime.fromUnix(-1010224506, Duration.Resolution.second, .{ .tz = &tz_a });
    dt_b = try Datetime.fromUnix(579644539, Duration.Resolution.second, .{ .tz = &tz_b });
    dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });

    w = .fixed(&buf);
    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("1988-05-15T06:22:19+10:00:00", w.buffered());
    w = .fixed(&buf);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("1937-12-27T15:04:54+01:00:00", w.buffered());

    tz_a.deinit();
    tz_b.deinit();

    tz_a = try Tz.fromTzdata(testing.io, "US/Eastern", testing.allocator);
    tz_b = try Tz.fromTzdata(testing.io, "Australia/Melbourne", testing.allocator);

    dt_a = try Datetime.fromUnix(42640281, Duration.Resolution.second, .{ .tz = &tz_a });
    dt_b = try Datetime.fromUnix(-1385885032, Duration.Resolution.second, .{ .tz = &tz_b });
    dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });

    w = .fixed(&buf);
    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("1926-01-31T10:56:08-05:00:00", w.buffered());
    w = .fixed(&buf);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("1971-05-09T22:31:21+10:00:00", w.buffered());

    tz_a.deinit();
    tz_b.deinit();

    tz_a = try Tz.fromTzdata(testing.io, "Europe/Vaduz", testing.allocator);
    tz_b = try Tz.fromTzdata(testing.io, "America/Port_of_Spain", testing.allocator);

    dt_a = try Datetime.fromUnix(1094749082, Duration.Resolution.second, .{ .tz = &tz_a });
    dt_b = try Datetime.fromUnix(775994453, Duration.Resolution.second, .{ .tz = &tz_b });
    dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });

    w = .fixed(&buf);
    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("1994-08-04T12:00:53+02:00:00", w.buffered());
    w = .fixed(&buf);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("2004-09-09T12:58:02-04:00:00", w.buffered());

    tz_a.deinit();
    tz_b.deinit();

    tz_a = try Tz.fromTzdata(testing.io, "Asia/Kuala_Lumpur", testing.allocator);
    tz_b = try Tz.fromTzdata(testing.io, "Pacific/Pitcairn", testing.allocator);

    dt_a = try Datetime.fromUnix(-44705548, Duration.Resolution.second, .{ .tz = &tz_a });
    dt_b = try Datetime.fromUnix(788932013, Duration.Resolution.second, .{ .tz = &tz_b });
    dt_c = try dt_a.tzConvert(.{ .tz = &tz_b });
    dt_b = try dt_b.tzConvert(.{ .tz = &tz_a });

    w = .fixed(&buf);
    try dt_b.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("1995-01-01T11:46:53+08:00:00", w.buffered());
    w = .fixed(&buf);
    try dt_c.toString("%Y-%m-%dT%H:%M:%S%::z", &w);
    try testing.expectEqualStrings("1968-08-01T05:17:32-08:30:00", w.buffered());

    tz_a.deinit();
    tz_b.deinit();
}
