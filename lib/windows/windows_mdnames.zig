// SPDX-FileCopyrightText: 2024-2026 Florian Obersteiner
// SPDX-FileContributor: Florian Obersteiner <f.obersteiner@posteo.de>
// SPDX-FileComment: assisted-by Claude Sonnet 4.6
//
// SPDX-License-Identifier: Unlicense

const std = @import("std");
const windows = std.os.windows;
const unicode = std.unicode;
const log = std.log.scoped(.zdt__string_windows);

extern "kernel32" fn GetLocaleInfoEx(
    lpLocaleName: ?[*:0]const u16, // LPCWSTR
    LCType: windows.DWORD, // LCTYPE
    lpLCData: ?[*:0]u16, // LPWSTR
    cchData: c_int, // int
) callconv(std.os.windows.WINAPI) c_int;

const default_locale_ptr = null; // LOCALE_NAME_USER_DEFAULT;
const sz_abbr: usize = 32;
const sz_normal: usize = 64;

pub fn getDayNameAbbr_(n: u8) [sz_abbr]u8 {
    var result: [sz_abbr]u8 = std.mem.zeroes([sz_abbr]u8);
    result[0] = '?';

    var buf: [sz_abbr]c_ushort = undefined; // u16
    const code = GetLocaleInfoEx(
        default_locale_ptr,
        day_names_abbr[n],
        &buf,
        sz_abbr,
    );
    if (code <= 0) return result;

    // Windows UTF-16 LE ("WTF") to UTF-8:
    var utf8: [sz_abbr]u8 = undefined;
    const n_bytes = unicode.utf16LeToUtf8(&utf8, std.mem.sliceTo(&buf, 0)) catch 0;

    if (n_bytes == 0) return result; // data started with null byte...
    std.mem.copyForwards(u8, result[0..n_bytes], utf8[0..n_bytes]);

    return result;
}

pub fn getDayName_(n: u8) [sz_normal]u8 {
    var result: [sz_normal]u8 = std.mem.zeroes([sz_normal]u8);
    result[0] = '?';

    var buf: [sz_normal]c_ushort = undefined; // u16
    const code = GetLocaleInfoEx(
        default_locale_ptr,
        day_names[n],
        &buf,
        sz_normal,
    );
    if (code <= 0) return result;

    var utf8: [sz_abbr]u8 = undefined;
    const n_bytes = unicode.utf16LeToUtf8(&utf8, std.mem.sliceTo(&buf, 0)) catch 0;

    if (n_bytes == 0) return result;
    std.mem.copyForwards(u8, result[0..n_bytes], utf8[0..n_bytes]);

    return result;
}

pub fn getMonthNameAbbr_(n: u8) [sz_abbr]u8 {
    var result: [sz_abbr]u8 = std.mem.zeroes([sz_abbr]u8);
    result[0] = '?';

    var buf: [sz_abbr]c_ushort = undefined; // u16
    const code = GetLocaleInfoEx(
        default_locale_ptr,
        month_names_abbr[n],
        &buf,
        sz_abbr,
    );
    if (code <= 0) return result;

    var utf8: [sz_abbr]u8 = undefined;
    const n_bytes = unicode.utf16LeToUtf8(&utf8, std.mem.sliceTo(&buf, 0)) catch 0;

    if (n_bytes == 0) return result;
    std.mem.copyForwards(u8, result[0..n_bytes], utf8[0..n_bytes]);

    return result;
}

pub fn getMonthName_(n: u8) [sz_normal]u8 {
    var result: [sz_normal]u8 = std.mem.zeroes([sz_normal]u8);
    result[0] = '?';

    var buf: [sz_normal]c_ushort = undefined; // u16
    const code = GetLocaleInfoEx(
        default_locale_ptr,
        month_names[n],
        &buf,
        sz_normal,
    );
    if (code <= 0) return result;

    var utf8: [sz_abbr]u8 = undefined;
    const n_bytes = unicode.utf16LeToUtf8(&utf8, std.mem.sliceTo(&buf, 0)) catch 0;

    if (n_bytes == 0) return result;
    std.mem.copyForwards(u8, result[0..n_bytes], utf8[0..n_bytes]);

    return result;
}

// abbreviated day name; for %a
const day_names_abbr = [7]c_ulong{
    0x00000037,
    0x00000031, // Windows uses Mon as first day of week
    0x00000032,
    0x00000033,
    0x00000034,
    0x00000035,
    0x00000036,
};

// day name; for %A
const day_names = [7]c_ulong{
    0x00000030,
    0x0000002a, // Windows uses Mon as first day of week
    0x0000002b,
    0x0000002c,
    0x0000002d,
    0x0000002e,
    0x0000002f,
};

// abbreviated month name; for %b
const month_names_abbr = [13]c_ulong{
    0x00000044,
    0x00000045,
    0x00000046,
    0x00000047,
    0x00000048,
    0x00000049,
    0x0000004a,
    0x0000004b,
    0x0000004c,
    0x0000004d,
    0x0000004e,
    0x0000004f,
    0x0000100f,
};

// abbreviated month name; for %B
const month_names = [13]c_ulong{
    0x00000038,
    0x00000039,
    0x0000003a,
    0x0000003b,
    0x0000003c,
    0x0000003d,
    0x0000003e,
    0x0000003f,
    0x00000040,
    0x00000041,
    0x00000042,
    0x00000043,
    0x0000100e,
};
