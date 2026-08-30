// SPDX-FileCopyrightText: 2025-2026 Florian Obersteiner
// SPDX-FileContributor: Florian Obersteiner <f.obersteiner@posteo.de>
//
// SPDX-License-Identifier: Unlicense

const std = @import("std");
const log = std.log.scoped(.zdt__root);

pub const Datetime = @import("Datetime.zig");
pub const Duration = @import("Duration.zig");
pub const Formats = @import("Formats.zig");
pub const Timezone = @import("Timezone.zig");
pub const UTCoffset = Timezone.UTCoffset;

pub const ZdtError = @import("errors.zig").ZdtError;

// make sure 'internal' tests are also executed:
const calendar = @import("calendar.zig");
const psx = @import("tz_posix.zig");
const tzif = @import("tz_tzif.zig");
const str = @import("string.zig");

test {
    _ = Datetime;
    _ = Duration;
    _ = Formats;
    _ = Timezone;
    _ = calendar;
    _ = psx;
    _ = str;
    _ = tzif;
}
