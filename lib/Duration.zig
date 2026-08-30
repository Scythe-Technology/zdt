// SPDX-FileCopyrightText: 2024-2026 Florian Obersteiner
// SPDX-FileContributor: Florian Obersteiner <f.obersteiner@posteo.de>
//
// SPDX-License-Identifier: Unlicense

//! a period in time

const std = @import("std");
const log = std.log.scoped(.zdt__Duration);
const testing = std.testing;
const Writer = std.Io.Writer;

const FormatError = @import("./errors.zig").FormatError;
const RangeError = @import("./errors.zig").RangeError;

const Duration = @This();

// max. digits per quantity in an ISO8601 duration string (arbitrary)
const max_n_digits: usize = 96;

/// For the 'asNanoseconds' method to work correctly, the maximum number of seconds
/// that can be represented by a Duration's __sec is (max(i128) - (1e9 - 1)) / 1e9.
/// The minus 1e9 are required to correctly handle __nsec, which can be (1e9 - 1) max.
pub const max_sec: i128 = 170141183460469231731687303714; // ~36909691 years

/// For the minimum, it is just min(i128) / 1e9 since the __nsec is always positive.
pub const min_sec: i128 = -170141183460469231731687303715;

/// Any duration represented in seconds.
/// Do not modify directly.
__sec: i128 = 0,

/// Fractional seconds in nanoseconds, always >= 0.
/// Do not modify directly.
__nsec: u32 = 0,

/// Create a duration from multiple of specific a timespan.
///
/// The Duration type can represent any timespan that can fit into  a 64 bit
/// signed integer, i.e. up to 2^63 weeks. Therefore, no error is returned.
pub fn fromTimespanMultiple(n: i64, timespan: Timespan) Duration {
    const ns: i128 = @as(i128, @intCast(@backingInt(timespan))) * n;
    return .{
        .__sec = @intCast(@divFloor(ns, 1_000_000_000)),
        .__nsec = @intCast(@mod(ns, 1_000_000_000)),
    };
}

/// Create a duration from an 'ISO8601 duration' style string, e.g.
///
/// ```
/// "PT9H" : 9 hours
/// "PT1.234S" : 1 second, 234 milliseconds
/// ```
///
/// Restrictions / what we deliberately do NOT support:
/// - Since the Duration type represents an absolute difference in time,
///   'years' and 'months' fields of the string ('Y', 'M') must be zero.
/// - A fractional value is only allowed for seconds ('S').
/// - The string might be prefixed '-' to indicate a negative duration.
///   Individual signed components are not allowed.
pub fn fromISO8601(string: []const u8) FormatError!Duration {
    const fields: RelativeDelta = try RelativeDelta.fromISO8601(string);
    return try RelativeDelta.toDuration(fields);
}

/// Convert a Duration to the smallest multiple of the given timespan
/// that can contain the duration
pub fn toTimespanMultiple(duration: Duration, timespan: Timespan) i128 {
    const ns: i128 = duration.asNanoseconds();
    const divisor: u64 = @backingInt(timespan);
    return std.math.divCeil(i128, ns, @as(i128, divisor)) catch unreachable;
}

/// Representation as seconds with fractional seconds
pub fn totalSeconds(duration: Duration) f64 {
    const ns = duration.asNanoseconds();
    return @floatCast(@as(f128, @floatFromInt(ns)) / 1_000_000_000);
}

/// Representation as minutes with fractional minutes
pub fn totalMinutes(duration: Duration) f64 {
    const ns = duration.asNanoseconds();
    return @floatCast(@as(f128, @floatFromInt(ns)) / 60_000_000_000);
}

/// Representation as hours with fractional hours
pub fn totalHours(duration: Duration) f64 {
    const ns = duration.asNanoseconds();
    return @floatCast(@as(f128, @floatFromInt(ns)) / 3_600_000_000_000);
}

/// Representation as days with fractional days
pub fn totalDays(duration: Duration) f64 {
    const ns = duration.asNanoseconds();
    return @floatCast(@as(f128, @floatFromInt(ns)) / 86_400_000_000_000);
}

/// Add a duration to another. Makes a new Duration.
///
/// Returns RangeError.SecondsOutOfRange if the sum of the durations
/// wouldn't satisfy the requirement of 'asNanoseconds()' to work.
pub fn add(this: Duration, other: Duration) RangeError!Duration {
    const s: i128 = this.__sec + other.__sec;
    const ns: u32 = this.__nsec + other.__nsec;
    const result = Duration{
        .__sec = s + @divFloor(ns, 1_000_000_000),
        .__nsec = @truncate(@mod(ns, 1_000_000_000)),
    };
    if (result.__sec > max_sec or result.__sec < min_sec) return RangeError.SecondOutOfRange;
    return result;
}

/// Add a duration to another. Makes a new Duration.
///
/// If the resulting Duration would be out-of-range to satisfy the
/// requirement of 'asNanoseconds()' to work, the result is clipped
/// to max_sec or min_sec, respectively.
pub fn addClip(this: Duration, other: Duration) Duration {
    const s: i128 = this.__sec + other.__sec;
    const ns: u32 = this.__nsec + other.__nsec;
    var result = Duration{
        .__sec = s + @divFloor(ns, 1_000_000_000),
        .__nsec = @truncate(@mod(ns, 1_000_000_000)),
    };
    if (result.__sec > max_sec) {
        result.__sec = max_sec;
        return result;
    }
    if (result.__sec < min_sec) {
        result.__sec = min_sec;
        return result;
    }
    return result;
}

/// Subtract a duration from another. Makes a new Duration.
///
/// Returns RangeError.SecondsOutOfRange if the difference of the durations
/// wouldn't satisfy the requirement of 'asNanoseconds()' to work.
pub fn sub(this: Duration, other: Duration) RangeError!Duration {
    var s: i128 = this.__sec - other.__sec;
    var ns: i32 = @as(i32, @intCast(this.__nsec)) - @as(i32, @intCast(other.__nsec));
    if (ns < 0) {
        s -= 1;
        ns += 1_000_000_000;
    }
    const result = Duration{ .__sec = s, .__nsec = @intCast(ns) };
    if (result.__sec > max_sec or result.__sec < min_sec) return RangeError.SecondOutOfRange;
    return result;
}

/// Subtract a duration from another. Makes a new Duration.
///
/// If the resulting Duration would be out-of-range to satisfy the
/// requirement of 'asNanoseconds()' to work, the result is clipped
/// to max_sec or min_sec, respectively.
pub fn subClip(this: Duration, other: Duration) Duration {
    var s: i128 = this.__sec - other.__sec;
    var ns: i32 = @as(i32, @intCast(this.__nsec)) - @as(i32, @intCast(other.__nsec));
    if (ns < 0) {
        s -= 1;
        ns += 1_000_000_000;
    }
    var result = Duration{ .__sec = s, .__nsec = @intCast(ns) };
    if (result.__sec < min_sec) {
        result.__sec = min_sec;
        return result;
    }
    if (result.__sec > max_sec) {
        result.__sec = max_sec;
        return result;
    }
    return result;
}

/// Convert a duration to seconds, don't forget the nanos just because they're small 😎
pub fn asSeconds(duration: Duration) i128 {
    if (duration.__nsec > 500_000_000) return duration.__sec + 1;
    return duration.__sec;
}

/// Convert a duration to nanos.
pub fn asNanoseconds(duration: Duration) i128 {
    return duration.__sec * 1_000_000_000 + duration.__nsec;
}

/// Formatted printing for Duration type. Defaults to 'ISO8601-duration'-like format.
pub fn format(
    duration: Duration,
    writer: *Writer,
) Writer.Error!void {
    if (duration.__sec == 0 and duration.__nsec == 0) return try writer.print("PT0S", .{});

    const rd = RelativeDelta.fromDuration(&duration);

    const is_negative = duration.__sec < 0;
    if (is_negative) try writer.print("-P", .{}) else try writer.print("P", .{});

    if (rd.weeks > 0) try writer.print("{d}W", .{rd.weeks});
    if (rd.days > 0) try writer.print("{d}D", .{rd.days});

    if (rd.hours > 0 or rd.minutes > 0 or rd.seconds > 0 or rd.nanoseconds > 0)
        try writer.print("T", .{})
    else
        return;

    if (rd.hours > 0) try writer.print("{d}H", .{rd.hours});
    if (rd.minutes > 0) try writer.print("{d}M", .{rd.minutes});

    if (rd.seconds == 0 and rd.nanoseconds == 0) return;

    var frac = duration.__nsec;
    if (frac > 0) {
        // Truncate zeros from fractional part.
        // Note: kcov claims this is untested, which is incorrect
        while (frac % 10 == 0) : (frac /= 10) {}
    }

    if (frac > 0) {
        try writer.print("{d}.{d}S", .{ rd.seconds, frac });
    } else {
        try writer.print("{d}S", .{rd.seconds});
    }
}

/// Resolution of a duration in terms of fractions of a second. Mainly used
/// to specify input resolution for creating datetime from Unix time.
pub const Resolution = enum(u32) {
    second = 1,
    millisecond = 1_000,
    microsecond = 1_000_000,
    nanosecond = 1_000_000_000,
};

/// Span in time of a duration, in terms of multiples of a nanosecond.
pub const Timespan = enum(u64) {
    nanosecond = 1,
    microsecond = 1_000,
    millisecond = 1_000_000,
    second = 1_000_000_000,
    minute = 1_000_000_000 * 60,
    hour = 1_000_000_000 * 60 * 60,
    day = 1_000_000_000 * 60 * 60 * 24,
    week = 1_000_000_000 * 60 * 60 * 24 * 7,
};

// Helper for the ISO8601 Duration parser
const tracker = struct {
    _flags: u8 = 0,

    pub const token = enum(u8) {
        none = 0,
        seconds = 1,
        minutes = (1 << 1),
        hours = (1 << 2),
        time_separator = (1 << 3),
        days = (1 << 4),
        weeks = (1 << 5),
        months = (1 << 6),
        years = (1 << 7),
    };

    pub fn add(self: *tracker, new_flag: tracker.token) void {
        self._flags |= @backingInt(new_flag);
    }

    pub fn have(self: *const tracker, check_flag: tracker.token) bool {
        return self._flags & @backingInt(check_flag) != 0;
    }

    // Note that this depends on the ordering of the enum backing integer:
    pub fn ge(self: *const tracker, compare_flag: tracker.token) bool {
        return self._flags >= @backingInt(compare_flag);
    }
};

test "iso8601 duration quantities tracker flags" {
    var token_tracker = tracker{};

    token_tracker.add(.seconds);
    try testing.expectEqual(1, token_tracker._flags);
    try testing.expect(token_tracker.have(.seconds));
    try testing.expect(token_tracker.ge(.none));
    try testing.expect(!token_tracker.ge(.minutes));

    token_tracker.add(.minutes);
    token_tracker.add(.time_separator);
    try testing.expect(token_tracker.ge(.time_separator));

    token_tracker.add(.weeks);
    try testing.expect(token_tracker.have(.seconds));
    try testing.expect(token_tracker.have(.weeks));
    try testing.expect(token_tracker.ge(.weeks));
}

/// Relative difference in time;
/// might contain ambiguous quantities months and years.
pub const RelativeDelta = struct {
    years: u32 = 0,
    months: u32 = 0,
    weeks: u32 = 0,
    days: u32 = 0,
    hours: u32 = 0,
    minutes: u32 = 0,
    seconds: u32 = 0,
    nanoseconds: u32 = 0,
    negative: bool = false,

    /// Normalize time fields to their 'normal' modulo, e.g. hours 0-23 etc.
    /// Fields up to "days" might change; other fields stay untouched.
    pub fn normalize(this: *const RelativeDelta) RelativeDelta {
        var result: RelativeDelta = .{
            .years = this.years,
            .months = this.months,
            .weeks = this.weeks,
            .days = this.days,
            .hours = this.hours,
            .minutes = this.minutes,
            .seconds = this.seconds,
            .nanoseconds = this.nanoseconds,
            .negative = this.negative,
        };

        if (result.seconds > 59) {
            result.minutes += result.seconds / 60;
            result.seconds = result.seconds % 60;
        }
        if (result.minutes > 59) {
            result.hours += result.minutes / 60;
            result.minutes = result.minutes % 60;
        }
        if (result.hours > 23) {
            result.days += result.hours / 24;
            result.hours = result.hours % 24;
        }
        if (result.days > 6) {
            result.weeks += result.days / 7;
            result.days = result.days % 7;
        }

        return result;
    }

    /// Make a RelativeDelta from a Duration.
    pub fn fromDuration(duration: *const Duration) RelativeDelta {
        var result: RelativeDelta = .{
            .years = 0,
            .months = 0,
            .nanoseconds = duration.__nsec,
            .negative = if (duration.__sec < 0) true else false,
        };

        var secs: u128 = @abs(duration.__sec);
        result.weeks = @truncate(secs / (86400 * 7));
        secs -|= @as(u64, result.weeks) * (86400 * 7);

        result.days = @truncate(secs / 86400);
        secs -|= @as(u64, result.days) * 86400;

        result.hours = @truncate(secs / 3600);
        secs -|= @as(u64, result.hours) * 3600;

        result.minutes = @truncate(secs / 60);
        secs -|= @as(u64, result.minutes) * 60;

        result.seconds = @truncate(secs);

        return result;
    }

    /// Make a Duration from a RelativeDelta.
    pub fn toDuration(reldelta: RelativeDelta) FormatError!Duration {
        if (reldelta.years != 0 or reldelta.months != 0) return FormatError.InvalidFormat;
        const total_secs: i64 = @as(i64, reldelta.weeks) * 7 * 86400 + //
            @as(i64, reldelta.days) * 86400 + //
            @as(i64, reldelta.hours) * 3600 + //
            @as(i64, reldelta.minutes) * 60 + //
            @as(i64, reldelta.seconds);
        return .{
            .__sec = if (reldelta.negative) total_secs * -1 else total_secs,
            .__nsec = reldelta.nanoseconds,
        };
    }

    /// Convert ISO8601 duration from string to a RelativeDelta.
    ///
    /// The string might be prefixed '-' to indicate a negative duration.
    ///
    /// Restrictions / what we deliberately do NOT support:
    /// - datetime-like formats PYYYYMMDDTHHMMSS and PYYYY-MM-DDTHH-MM-SS give error
    /// - individual signed components are not allowed (no '-' *after* the P)
    /// - unicode minus ("−") is not supported
    /// - a fractional value is only allowed for seconds ('S')
    /// - comma (',') as a decimal separator is not supported
    /// - we do not make special distinctions for "wall time" (as opposed to time actually passed)
    /// - maximum values are limited to u32 (4294967295)
    pub fn fromISO8601(string: []const u8) FormatError!RelativeDelta {
        if (string.len == 0) return FormatError.InvalidFormat;
        // max characters, arbitrary
        if (string.len > max_n_digits) return FormatError.InvalidFormat;

        // must end with a character
        if (!std.ascii.isAlphabetic(string[string.len - 1])) return FormatError.InvalidFormat;

        var result: RelativeDelta = .{};
        var stop: usize = 0;

        if (string[stop] == '-') { // minus prefix
            result.negative = true;
            stop += 1;
        }

        // at least 3 characters, e.g. 'P0D' or 4, e.g. '-P1Y'
        if (string.len < (3 + @as(u8, @intFromBool(result.negative))))
            return FormatError.InvalidFormat;

        // must start with P (ignore sign)
        if (string[stop] != 'P') return FormatError.InvalidFormat;
        stop += 1;

        // 'P' can be followed by a 'T'; the 'T' must then be followed by a digit
        if (string[stop] == 'T') {
            // 'T' must be followed by a digit
            if (!(std.ascii.isDigit(string[stop + 1]))) return FormatError.InvalidFormat;
        } else {
            // no 'T', must be a digit
            if (!(std.ascii.isDigit(string[stop]))) return FormatError.InvalidFormat;
        }

        var idx: usize = string.len - 1;

        var seen = tracker{};

        while (idx >= stop) {
            switch (string[idx]) {
                'S' => {
                    // seconds come last, so no other quantity must have been parsed yet
                    if (seen.ge(.seconds)) return FormatError.InvalidFormat;
                    idx -= 1;
                    seen.add(.seconds);
                    _ = try parseAndAdvanceS(string, &idx, &result.seconds, &result.nanoseconds);
                },
                'M' => {
                    // 'M' may appear twice; it's either minutes or months;
                    //   depending on if the 'T' exists and if so, has been seen.
                    if (seen.have(.time_separator)) {
                        // 'T' seen, must be months...
                        if (seen.ge(.months)) return FormatError.InvalidFormat;
                        idx -= 1;
                        seen.add(.months);
                        const quantity = try parseAndAdvanceYmWdHM(string, &idx);
                        result.months = quantity;
                    } else {
                        // minutes come second to last, so only seconds may have been parsed yet
                        if (seen.ge(.minutes)) return FormatError.InvalidFormat;
                        // whether a 'T' exists cannot be known yet (backwards scan);
                        // enforced by the post-loop check below
                        idx -= 1;
                        seen.add(.minutes);
                        const quantity = try parseAndAdvanceYmWdHM(string, &idx);
                        result.minutes = quantity;
                    }
                },
                'H' => {
                    // hours are the third-to-last component,
                    // so only seconds and minutes may have been parsed yet
                    if (seen.ge(.hours)) return FormatError.InvalidFormat;
                    idx -= 1;
                    seen.add(.hours);
                    const quantity = try parseAndAdvanceYmWdHM(string, &idx);
                    result.hours = quantity;
                },
                'T' => {
                    if (seen.have(.time_separator)) return FormatError.InvalidFormat;
                    if (!(seen.have(.seconds) or seen.have(.minutes) or seen.have(.hours)))
                        return FormatError.InvalidFormat;
                    idx -= 1;
                    seen.add(.time_separator);
                },
                'D' => {
                    if (seen.ge(.days)) return FormatError.InvalidFormat;
                    idx -= 1;
                    seen.add(.days);
                    const quantity = try parseAndAdvanceYmWdHM(string, &idx);
                    result.days = quantity;
                },
                'W' => {
                    if (seen.ge(.weeks)) return FormatError.InvalidFormat;
                    idx -= 1;
                    seen.add(.weeks);
                    const quantity = try parseAndAdvanceYmWdHM(string, &idx);
                    result.weeks = quantity;
                },
                'Y' => {
                    if (seen.ge(.years)) return FormatError.InvalidFormat;
                    idx -= 1;
                    seen.add(.years);
                    const quantity = try parseAndAdvanceYmWdHM(string, &idx);
                    result.years = quantity;
                },
                else => return FormatError.InvalidFormat,
            }
        }

        // since we parse right to left, we might have parsed time componets although
        // there is no time separator 'T' - therefore we need to check for it:
        if ((seen.have(.seconds) or seen.have(.minutes) or seen.have(.hours)) and
            !seen.have(.time_separator)) return FormatError.InvalidFormat;

        return result;
    }
};

/// Backwards-looking parse chars from 'string' seconds and nanoseconds (sum),
/// end index is the value of 'idx_ptr' when the function is called.
/// Start index is determined automatically.
///
/// This is a procedure; it modifies input pointer 'sec' and 'nsec' values in-place.
/// This way, we can work around the fact that there are no multiple-return functions
/// and save arithmetic operations (compared to using a single return value).
fn parseAndAdvanceS(string: []const u8, idx_ptr: *usize, sec: *u32, nsec: *u32) FormatError!void {
    const end_idx = idx_ptr.*;
    var have_fraction: bool = false;
    while (idx_ptr.* > 0 and
        end_idx - idx_ptr.* < max_n_digits and
        !std.ascii.isAlphabetic(string[idx_ptr.*])) : (idx_ptr.* -= 1)
    {
        if (string[idx_ptr.*] == '.') have_fraction = true;
    }

    if (have_fraction) {
        // fractional seconds are specified. need to convert them to nanoseconds,
        // and truncate anything behind the nineth digit.
        const substr = string[idx_ptr.* + 1 .. end_idx + 1];
        const idx_dot = std.mem.indexOfScalar(u8, substr, '.');

        sec.* = try std.fmt.parseInt(u32, substr[0..idx_dot.?], 10);

        var substr_nanos = substr[idx_dot.? + 1 ..];
        if (substr_nanos.len > 9) substr_nanos = substr_nanos[0..9];
        const nanos = try std.fmt.parseInt(u32, substr_nanos, 10);

        // nanos might actually be another unit; if there are e.g. 3 digits of fractional
        // seconds, we have milliseconds (1/10^3 s) and need to multiply by 10^(9-3) to get ns.
        const missing = 9 - substr_nanos.len;
        const f: u32 = try std.math.powi(u32, 10, @as(u32, @intCast(missing)));
        nsec.* = nanos * f;
    } else { // short cut: there is no fraction
        sec.* = try std.fmt.parseInt(u32, string[idx_ptr.* + 1 .. end_idx + 1], 10);
        return;
    }
}

/// Backwards-looking parse chars from 'string' to int (base 10),
/// end index is the value of 'idx_ptr' when the function is called.
/// start index is determined automatically.
fn parseAndAdvanceYmWdHM(string: []const u8, idx_ptr: *usize) FormatError!u32 {
    const end_idx = idx_ptr.*;
    while ( //
    idx_ptr.* > 0 and
        end_idx - idx_ptr.* < max_n_digits and
        !std.ascii.isAlphabetic(string[idx_ptr.*]) and
        !(string[idx_ptr.*] == '-') //
    ) : (idx_ptr.* -= 1) {}
    return try std.fmt.parseInt(u32, string[idx_ptr.* + 1 .. end_idx + 1], 10);
}
