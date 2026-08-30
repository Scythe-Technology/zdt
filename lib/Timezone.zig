// SPDX-FileCopyrightText: 2024-2026 Florian Obersteiner
// SPDX-FileContributor: Florian Obersteiner <f.obersteiner@posteo.de>
// SPDX-FileContributor: Michael Pollind <mpollind@gmail.com>
// SPDX-FileContributor: Ratakor <45130910+Ratakor@users.noreply.github.com>
//
// SPDX-License-Identifier: Unlicense

//! A set of rules to describe date and time somewhere on earth, relative to universal time (UTC).

const std = @import("std");
const log = std.log.scoped(.zdt__Timezone);
const builtin = @import("builtin");
const assert = std.debug.assert;
const Writer = std.Io.Writer;

const Datetime = @import("./Datetime.zig");
const FormatError = @import("./errors.zig").FormatError;
const TzError = @import("./errors.zig").TzError;
const TZifReadError = @import("./errors.zig").TZifReadError;
const ZdtError = @import("./errors.zig").ZdtError;
const tzif = @import("./tz_tzif.zig");
const psx = @import("./tz_posix.zig");
const tzwin = @import("./windows/windows_tz.zig");

const Timezone = @This();

/// embedded IANA time zone database (eggert/tz)
pub const tzdata = @import("./tzdata.zig").tzdata;
pub const sizeOfTZdata = @import("./tzdata.zig").sizeOfTZdata;
pub const tzdb_version = @import("./tzdata.zig").tzdb_version;

/// auto-generated prefix / path of the current eggert/tz database, as shipped with zdt;
// anonymous import; see `build.zig`.
pub const tzdb_prefix = @import("tzdb_prefix").tzdb_prefix;

// might not work on all Unix systems:
const tzlocal_default_ID = "/etc/localtime";

// longest tz name is 'America/Argentina/ComodRivadavia' --> 32 ASCII chars
const cap_name_data: usize = 48;

// designation of a UTC offset like 'CEST' or 'MST'
const cap_designation_data: usize = 6;

/// Offset from UTC should be in range `(-25h ... +26h)` as specified by
/// RFC9636, sect. 3.2, TZif data block.
pub const offset_range = struct {
    pub const min: i32 = -89999;
    pub const max: i32 = 93599;
};

const ruleTypes = enum {
    tzif,
    tzif_fixedsize,
    posixtz,
    utc,
};

/// rule sources for a time zone
rules: union(ruleTypes) {
    /// IANA tzdb/tzdata TZif file;
    /// use Timezone.fromTzdata or Timezone.fromSystemTzdata to set as time zone of a datetime.
    tzif: tzif.TzAlloc,
    /// IANA tzdb/tzdata TZif file in a fixed-size data structure - no allocator required!
    tzif_fixedsize: tzif.Tz,
    /// POSIX TZ string
    posixtz: psx.PosixTz,
    /// UTC placeholder;
    /// use Timezone.UTC constant to set UTC as time zone of a datetime.
    utc: struct {},
},

// 'internal' data for the name / identifier
__name_data: [cap_name_data]u8 = std.mem.zeroes([cap_name_data]u8),
__name_data_len: usize = 0,

pub const UTC: Timezone = .{
    .rules = .{ .utc = .{} },
    .__name_data = [3]u8{ 'U', 'T', 'C' } ++ std.mem.zeroes([cap_name_data - 3]u8),
    .__name_data_len = 3,
};

/// A time zone's identifier name.
/// Example: `"America/Denver"`. Not to be confused with abbreviations like "MST".
pub fn name(tz: *const Timezone) []const u8 {
    return std.mem.sliceTo(&tz.__name_data, 0);
}

/// Make a time zone from a POSIX TZ string like `"AEST-10AEDT,M10.1.0/2,M4.1.0/3"`.
pub fn fromPosixTz(posixString: []const u8) FormatError!Timezone {
    const ptz = try psx.parsePosixTzString(posixString);
    var tz = Timezone{ .rules = .{ .posixtz = ptz } };
    assert(posixString.len <= psx.max_string_len);
    tz.__name_data_len = if (posixString.len <= cap_name_data) posixString.len else cap_name_data;
    @memcpy(tz.__name_data[0..tz.__name_data_len], posixString[0..tz.__name_data_len]);
    return tz;
}

/// Make a time zone from IANA tz database TZif data, taken from the embedded tzdata.
/// The caller must make sure to de-allocate memory used for storing the TZif file's content
/// by calling the deinit method of the returned TZ instance.
///
/// Note that the allocator is optional. If 'null' is provided instead of an allocator,
/// a fixed-size structure will be used to holde the timezone rules, instead of doing this
/// dynamically in heap memory. This is faster, but requires more memory overall.
///
/// If an allocator is used, the caller must make sure to de-allocate memory used for
/// storing the TZif file's content by calling the deinit method of the returned
/// `Timezone` instance.
pub fn fromTzdata(io: std.Io, identifier: []const u8, allocator: ?std.mem.Allocator) ZdtError!Timezone {
    if (!identifierValid(identifier)) return TzError.InvalidIdentifier;

    if (std.mem.eql(u8, identifier, "localtime")) return tzLocal(io, allocator);

    if (tzdata.get(identifier)) |TZifBytes| {
        var reader = std.Io.Reader.fixed(TZifBytes);
        var tz = Timezone{ .rules = .{ .utc = .{} } };

        if (allocator) |alcr| {
            const tzif_tz = try tzif.TzAlloc.parse(alcr, &reader);
            tz = Timezone{ .rules = .{ .tzif = tzif_tz } };
        } else {
            const tzif_tz = try tzif.Tz.parse(&reader);
            tz = Timezone{ .rules = .{ .tzif_fixedsize = tzif_tz } };
        }

        tz.__name_data_len = if (identifier.len <= cap_name_data) identifier.len else cap_name_data;
        @memcpy(tz.__name_data[0..tz.__name_data_len], identifier[0..tz.__name_data_len]);

        return tz;
    }
    return TzError.TzUndefined;
}

/// Make a time zone from a IANA tz database TZif file.
/// This method allows the usage of a user-supplied tzdata; the path has to be specified.
/// To use the system's tzdata, use `zdt.Timezone.tzdb_prefix`.
///
/// Note that the allocator is optional. If 'null' is provided instead of an allocator,
/// a fixed-size structure will be used to holde the timezone rules, instead of doing this
/// dynamically in heap memory. This is faster, but requires more memory overall.
///
/// If an allocator is used, the caller must make sure to de-allocate memory used for
/// storing the TZif file's content by calling the deinit method of the returned
/// `Timezone` instance.
pub fn fromSystemTzdata(io: std.Io, identifier: []const u8, db_path: []const u8, allocator: ?std.mem.Allocator) ZdtError!Timezone {
    if (!identifierValid(identifier)) return TzError.InvalidIdentifier;

    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&path_buffer);
    const fb_alloc = fba.allocator();
    var p = try std.fs.path.join(fb_alloc, &[_][]const u8{ db_path, identifier });

    var file = try std.Io.Dir.openFileAbsolute(io, p, .{ .mode = .read_only });

    defer file.close(io);

    var read_buf: [4096]u8 = undefined;
    var file_reader: std.Io.File.Reader = .init(file, io, &read_buf);

    var tz = UTC;
    if (allocator) |alcr| {
        const tzif_tz = try tzif.TzAlloc.parse(alcr, &file_reader.interface);
        tz = Timezone{ .rules = .{ .tzif = tzif_tz } };
    } else {
        const tzif_tz = try tzif.Tz.parse(&file_reader.interface);
        tz = Timezone{ .rules = .{ .tzif_fixedsize = tzif_tz } };
    }

    // if db_path is empty: assume `identifier` is a path,
    // and look for 'zoneinfo' substring in identifier, remove if found
    if (std.mem.eql(u8, db_path, "")) {
        // if `identifier` is a symlink, resolve it to get a proper name,
        // exit this block on error
        blk: {
            const d = std.Io.Dir.openDirAbsolute(io, "/", .{}) catch break :blk;
            defer d.close(io);
            const st = d.statFile(io, identifier, .{ .follow_symlinks = false }) catch break :blk;
            switch (st.kind) {
                .sym_link => {
                    var path_buffer2: [std.Io.Dir.max_path_bytes]u8 = std.mem.zeroes([std.Io.Dir.max_path_bytes]u8);
                    _ = std.Io.File.realPath(file, io, &path_buffer2) catch break :blk;
                    p = std.mem.sliceTo(&path_buffer2, 0);
                },
                else => {},
            }
        }
        var pathname_iterator = std.mem.splitSequence(u8, p, "zoneinfo" ++ std.fs.path.sep_str);
        const part = pathname_iterator.next() orelse identifier;
        if (!std.mem.eql(u8, identifier, part)) {
            const tmp_name = pathname_iterator.next() orelse "?";
            assert(tmp_name.len <= cap_name_data);
            // we might need to overwrite pre-defined data with zeros:
            var name_data = std.mem.zeroes([cap_name_data]u8);
            const len: usize = if (tmp_name.len <= cap_name_data) tmp_name.len else cap_name_data;
            @memcpy(name_data[0..len], tmp_name[0..len]);
            tz.__name_data_len = len;
            tz.__name_data = name_data;
        }
    } else {
        // default: use identifier as name
        tz.__name_data_len = if (identifier.len <= cap_name_data) identifier.len else cap_name_data;
        @memcpy(tz.__name_data[0..tz.__name_data_len], identifier[0..tz.__name_data_len]);
    }

    return tz;
}

/// Clear a TZ instance and free potentially used memory
pub fn deinit(tz: *Timezone) void {
    tz.__name_data = std.mem.zeroes([cap_name_data]u8);
    tz.__name_data_len = 0;

    switch (tz.rules) {
        .tzif => |*_tzif| _tzif.deinit(),
        .tzif_fixedsize => return,
        .posixtz => return,
        .utc => return,
    }
}

/// Try to obtain the system's local time zone.
///
/// Note: Windows does not use the IANA time zone database;
/// a mapping from Windows db to IANA db exists but is prone to errors.
/// Use with caution.
pub fn tzLocal(io: std.Io, allocator: ?std.mem.Allocator) ZdtError!Timezone {
    switch (builtin.os.tag) {
        .linux, .macos => {
            return try Timezone.fromSystemTzdata(io, tzlocal_default_ID, "", allocator);
        },
        .windows => {
            const win_name = try tzwin.getTzName();
            return try Timezone.fromTzdata(io, win_name, allocator);
        },
        else => return TzError.NotImplemented,
    }
}

pub fn format(
    tz: *const Timezone,
    writer: *Writer,
) Writer.Error!void {
    try writer.print("Time zone, name: {s}. ", .{tz.name()});
    switch (tz.rules) {
        .tzif => try writer.print("Source: TZif. Memory: dynamic.", .{}),
        .tzif_fixedsize => try writer.print("Source: TZif. Memory: static.", .{}),
        .posixtz => try writer.print("Source: POSIX string.", .{}),
        .utc => try writer.print("(UTC)", .{}),
    }
}

/// Time zone identifiers must only contain alpha-numeric characters
/// as well as '+', '-', '_' and '/' (path separator).
pub fn identifierValid(id: []const u8) bool {
    for (id, 0..) |c, i| {
        switch (c) {
            // OK cases:
            'A'...'Z',
            'a'...'z',
            '0'...'9',
            '+',
            '-',
            '_',
            '/',
            => continue,
            // period char is special: only OK if
            // - not last char
            // - next char is not a period
            '.' => {
                if (i == id.len - 1) return false;
                if (id[i + 1] == '.') return false;
                continue;
            },
            else => return false,
        }
    }
    return true;
}

test "validate name" {
    var result = identifierValid("asdf");
    try std.testing.expectEqual(true, result);
    result = identifierValid("as/df");
    try std.testing.expectEqual(true, result);
    result = identifierValid("as.df");
    try std.testing.expectEqual(true, result);

    result = identifierValid("../asdf");
    try std.testing.expectEqual(false, result);
    result = identifierValid(".");
    try std.testing.expectEqual(false, result);
    result = identifierValid("as*df");
    try std.testing.expectEqual(false, result);
    result = identifierValid("?!");
    try std.testing.expectEqual(false, result);
}

pub const UTCoffset = struct {
    /// Seconds East of Greenwich.
    seconds_east: i32 = 0,

    /// DST indicator - can only be determined if the UTC offset is derived
    /// from a tz rule (POSIX, TZif) for given datetime.
    is_dst: bool = false,

    // 'internal'; data for the offset designation.
    __designation_data: [6:0]u8 = [6:0]u8{ 0, 0, 0, 0, 0, 0 },

    // 'internal'; TZif transitions index; < 0 means invalid.
    __transition_index: i32 = -1,

    /// UTC is constant. Presumably.
    ///
    /// Note that when working with time zones (not just offsets),
    /// preferably use Timezone.UTC.
    pub const _UTC = UTCoffset{
        .__designation_data = [6:0]u8{ 'U', 'T', 'C', 0, 0, 0 },
    };

    /// Designation / abbreviated time zone name such as "CET" for
    /// Central European Time in Europe/Berlin, winter.
    ///
    /// Note that multiple time zones can share the same abbreviated name;
    /// the abbreviations are therefore ambiguous.
    pub fn designation(offset: *const UTCoffset) []const u8 {
        return std.mem.sliceTo(&offset.__designation_data, 0);
    }

    /// Make a UTC offset from a given number of seconds East of Greenwich.
    pub fn fromSeconds(offset_sec_East: i32, desgnator: []const u8, is_dst: bool) TzError!UTCoffset {
        if (offset_sec_East < offset_range.min or offset_sec_East > offset_range.max) {
            return TzError.InvalidOffset;
        }
        if (std.mem.eql(u8, desgnator, "UTC") and offset_sec_East == 0 and is_dst == false) {
            return _UTC;
        }

        var name_data = std.mem.zeroes([cap_designation_data:0]u8);
        const len: usize = if (desgnator.len <= cap_designation_data) desgnator.len else cap_designation_data;
        std.mem.copyForwards(u8, name_data[0..len], desgnator[0..len]);

        return .{
            .seconds_east = offset_sec_East,
            .__designation_data = name_data,
            .is_dst = is_dst,
        };
    }

    /// Given time zone rules, get the UTC offset at a certain Unix time.
    pub fn atUnixtime(tz: *const Timezone, unixtime: i64) TzError!UTCoffset {
        switch (tz.rules) {
            .tzif => {
                // If the tz only has one timetype (offset spec.): use this.
                // Otherwise try to determine it from the defined transitions.
                const idx = if (tz.rules.tzif.timetypes.len == 1) -1 else findTransitionIdx(&tz.rules.tzif.transitions, unixtime);

                const timet = switch (idx) {
                    -1 => blk: {
                        assert(tz.rules.tzif.timetypes.len == 1);
                        break :blk tz.rules.tzif.timetypes[0];
                    },

                    // Unix time exceeds defined range of transitions => use POSIX from TZif footer
                    -2 => blk: {
                        // check the POSIX TZ from the footer.
                        const psxtz = psx.parsePosixTzString(tz.rules.tzif.footer.?) catch return TzError.InvalidPosixTz;
                        // If it has DST, make a UTC offset directly
                        if (psxtz.dst_offset) |_| return psxtz.utcOffsetAt(unixtime);
                        // ...otherwise use existing timetype
                        break :blk tz.rules.tzif.timetypes[tz.rules.tzif.transitions[tz.rules.tzif.transitions.len - 1].timetype_idx];
                    },

                    // Unix time precedes defined range of transitions => use first entry in timetypes (likely a LMT)
                    -3 => tz.rules.tzif.timetypes[0],

                    else => tz.rules.tzif.timetypes[tz.rules.tzif.transitions[@intCast(idx)].timetype_idx],
                };

                return .{
                    .seconds_east = @intCast(timet.offset),
                    .is_dst = timet.isDst(),
                    .__designation_data = timet.name_data,
                    .__transition_index = idx,
                };
            },
            .tzif_fixedsize => { // same as .tzif but for the fixed-size structure
                const idx: i32 = if (tz.rules.tzif_fixedsize.n_timetypes == 1)
                    -1
                else
                    findTransitionIdx(
                        &tz.rules.tzif_fixedsize.__transitions_data[0..tz.rules.tzif_fixedsize.n_transitions],
                        unixtime,
                    );

                const timet = switch (idx) {
                    -1 => blk: {
                        assert(tz.rules.tzif_fixedsize.n_timetypes == 1); // tested via .tzif
                        break :blk tz.rules.tzif_fixedsize.__timetypes_data[0]; // tested via .tzif
                    },

                    -2 => blk: {
                        const psxtz = psx.parsePosixTzString(std.mem.sliceTo(
                            tz.rules.tzif_fixedsize.__footer_data[0..],
                            '\n',
                        )) catch
                            return TzError.InvalidPosixTz;
                        if (psxtz.dst_offset) |_| return psxtz.utcOffsetAt(unixtime);
                        break :blk tz.rules.tzif_fixedsize.__timetypes_data[
                            tz.rules.tzif_fixedsize.__transitions_data[
                                tz.rules.tzif_fixedsize.n_transitions - 1
                            ].timetype_idx
                        ];
                    },

                    -3 => tz.rules.tzif_fixedsize.__timetypes_data[0], // tested via .tzif

                    else => tz.rules.tzif_fixedsize.__timetypes_data[
                        tz.rules.tzif_fixedsize.__transitions_data[
                            @intCast(idx)
                        ].timetype_idx
                    ],
                };

                return .{
                    .seconds_east = @intCast(timet.offset),
                    .is_dst = timet.isDst(),
                    .__designation_data = timet.name_data,
                    .__transition_index = idx,
                };
            },
            .posixtz => return tz.rules.posixtz.utcOffsetAt(unixtime),
            .utc => return _UTC,
        }
    }

    /// Default format for the Offset struct, gives [+|-][hh]:[mm] format
    /// or 'Z' if UTC.
    ///
    /// Notes:
    /// - seconds are shown if non-zero; [+|-][hh]:[mm]:[ss]
    pub fn format(
        offset: UTCoffset,
        writer: *Writer,
    ) Writer.Error!void {
        if (std.meta.eql(offset, _UTC)) {
            try writer.print("Z", .{});
            return;
        }
        const off = offset.seconds_east;
        const absoff: u32 = if (off < 0) @intCast(off * -1) else @intCast(off);
        const sign = if (off < 0) "-" else "+";
        const hours = absoff / 3600;
        const minutes = (absoff % 3600) / 60;
        const seconds = (absoff % 3600) % 60;
        try writer.print("{s}{d:0>2}:{d:0>2}", .{ sign, hours, minutes });
        if (seconds != 0) try writer.print(":{d:0>2}", .{seconds});
    }

    /// Custom formatter used by the %z directive.
    pub fn formatB(
        offset: UTCoffset,
        options: std.fmt.Options,
        writer: *Writer,
    ) Writer.Error!void {
        const off = offset.seconds_east;
        const absoff: u32 = if (off < 0) @intCast(off * -1) else @intCast(off);
        const sign = if (off < 0) "-" else "+";
        const hours = absoff / 3600;
        const minutes = (absoff % 3600) / 60;
        const seconds = (absoff % 3600) % 60;

        // precision: 0 - hours, 1 - hours:minutes, 2 - hours:minutes:seconds
        const precision = if (options.precision) |p| p else 1;

        if (options.fill != 0) {
            try writer.print("{s}{d:0>2}", .{ sign, hours });
            if (precision > 0)
                try writer.print("{u}{d:0>2}", .{ options.fill, minutes });
            if (precision > 1)
                try writer.print("{u}{d:0>2}", .{ options.fill, seconds });
        } else {
            try writer.print("{s}{d:0>2}{d:0>2}", .{ sign, hours, minutes });
        }
    }

    /// Get the index of the UTC offset transition equal to or less than the given target.
    ///
    /// Invalid value indicators:
    /// ```
    /// -1 : transition array has no elements (single offset tz)
    /// -2 : target is larger than last transition element
    /// -3 : target is smaller than first transition element
    /// ```
    fn findTransitionIdx(transitions_ptr: *const []const tzif.Transition, target: i64) i32 {
        if (transitions_ptr.*.len == 0) return -1;
        // we know that transitions in 'array' are sorted, so we can check first and last indices.
        // if 'target' is out of range, caller should fall back to using tz.timetype[0]
        // or tz.timetype[-1] resp.
        if (target > transitions_ptr.*[transitions_ptr.*.len - 1].ts) return -2;
        if (target < transitions_ptr.*[0].ts) return -3;

        // now do a binary search:
        var left: usize = 0;
        var right: usize = transitions_ptr.*.len - 1;
        while (left <= right) {
            const middle = left + @divFloor(right - left, 2);
            if (transitions_ptr.*[middle].ts < target) {
                left = middle + 1;
            } else if (transitions_ptr.*[middle].ts > target) {
                right = middle - 1;
            } else {
                return @as(i32, @intCast(middle));
            }
        }
        return @as(i32, @intCast(left - 1));
    }
};
