// SPDX-FileCopyrightText: 2024-2026 Florian Obersteiner
// SPDX-FileContributor: Florian Obersteiner <f.obersteiner@posteo.de>
//
// SPDX-License-Identifier: Unlicense

const std = @import("std");
const log = std.log.scoped(.zdt__string_windows);

const nl_item = c_int;
extern fn nl_langinfo(__item: nl_item) [*c]u8;

const sz_abbr: usize = 32;
const sz_normal: usize = 64;

pub fn getDayNameAbbr_(n: u8) [sz_abbr]u8 {
    const str = std.mem.span(nl_langinfo(day_names_abbr[n]));
    var result: [sz_abbr]u8 = std.mem.zeroes([sz_abbr]u8);
    result[0] = '?';
    if (str.len > sz_abbr) return result;
    std.mem.copyForwards(u8, result[0..str.len], str);
    return result;
}

pub fn getDayName_(n: u8) [sz_normal]u8 {
    const str = std.mem.span(nl_langinfo(day_names[n]));
    var result: [sz_normal]u8 = std.mem.zeroes([sz_normal]u8);
    result[0] = '?';
    if (str.len > sz_normal) return result;
    std.mem.copyForwards(u8, result[0..str.len], str);
    return result;
}

pub fn getMonthNameAbbr_(n: u8) [sz_abbr]u8 {
    const str = std.mem.span(nl_langinfo(month_names_abbr[n]));
    var result: [sz_abbr]u8 = std.mem.zeroes([sz_abbr]u8);
    result[0] = '?';
    if (str.len > sz_abbr) return result;
    std.mem.copyForwards(u8, result[0..str.len], str);
    return result;
}

pub fn getMonthName_(n: u8) [sz_normal]u8 {
    const str = std.mem.span(nl_langinfo(month_names[n]));
    var result: [sz_normal]u8 = std.mem.zeroes([sz_normal]u8);
    result[0] = '?';
    if (str.len > sz_normal) return result;
    std.mem.copyForwards(u8, result[0..str.len], str);
    return result;
}

// abbreviated day name; for %a
const day_names_abbr = [7]c_int{
    131072,
    131073,
    131074,
    131075,
    131076,
    131077,
    131078,
};

// day name; for %A
const day_names = [7]c_int{
    131079,
    131080,
    131081,
    131082,
    131083,
    131084,
    131085,
};

// abbreviated month name; for %b
const month_names_abbr = [12]c_int{
    131086,
    131087,
    131088,
    131089,
    131090,
    131091,
    131092,
    131093,
    131094,
    131095,
    131096,
    131097,
};

// abbreviated month name; for %B
const month_names = [12]c_int{
    131098,
    131099,
    131100,
    131101,
    131102,
    131103,
    131104,
    131105,
    131106,
    131107,
    131108,
    131109,
};
