const std = @import("std");
const builtin = @import("builtin");

const posix = @import("std").posix;
const windows = @import("std").os.windows;

const assert = std.testing.assert;

const ns_per_s = 1_000_000_000;
const ns_per_windowstick = 100;

// 1601-01-01 AD in seconds relative to 1970-01-01 00:00 UTC
const windows_epoch = -11644473600;

/// Get a calendar timestamp, in nanoseconds, relative to UTC 1970-01-01.
///
/// Taken from the Zig 0.15.1 standard library, modified.
///
/// Precision of timing depends on the hardware and operating system.
/// On Windows, this has a maximum granularity of 100 nanoseconds.
///
/// The return value is signed because it is possible that the system is configured
/// to use a date before the epoch.
///
/// See `posix.clock_gettime` for a POSIX timestamp.
pub fn nanoTimestamp() i128 {
    switch (builtin.os.tag) {
        .windows => {
            // RtlGetSystemTimePrecise() has a granularity of 100 nanoseconds and uses
            // the NTFS/Windows epoch, which is 1601-01-01.
            const epoch_adj = windows_epoch * ns_per_s / ns_per_windowstick;
            return @as(i128, windows.ntdll.RtlGetSystemTimePrecise() + epoch_adj) * ns_per_windowstick;
        },
        .wasi => {
            var ns: std.os.wasi.timestamp_t = undefined;
            const err = std.os.wasi.clock_time_get(.REALTIME, 1, &ns);
            assert(err == .SUCCESS);
            return ns;
        },
        .uefi => {
            const value, _ = std.os.uefi.system_table.runtime_services.getTime() catch return 0;
            return value.toEpoch();
        },
        else => {
            const ts = posix.clock_gettime(.REALTIME) catch |err| switch (err) {
                error.UnsupportedClock, error.Unexpected => return 0,
            };
            return (@as(i128, ts.sec) * ns_per_s) + ts.nsec;
        },
    }
}
