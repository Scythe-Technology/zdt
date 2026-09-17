# API Overview

## Datetime

### _Input:_ Make a Datetime

#### Now

- [`zdt.Datetime.now`](https://fobersteiner.codeberg.page/#zdt.Datetime.now) - with an optional time zone or UTC offset (see [`tz_options`](https://fobersteiner.codeberg.page/#zdt.Datetime.tz_options)).
- [`zdt.Datetime.nowUTC`](https://fobersteiner.codeberg.page/#zdt.Datetime.nowUTC) - a fail-safe shortcut to get UTC datetime.

#### From fields

- [`zdt.Datetime.fromFields`](https://fobersteiner.codeberg.page/#zdt.Datetime.fromFields) - year, month, day etc.; see also [`zdt.Datetime.Fields`](https://fobersteiner.codeberg.page/#zdt.Datetime.Fields) struct.

#### From a string

- [`zdt.Datetime.fromString`](https://fobersteiner.codeberg.page/#zdt.Datetime.fromString) - see [parsing directives](https://github.com/FObersteiner/zdt/wiki/String-parsing-and-formatting-directives).
- [`zdt.Datetime.fromISO8601`](https://fobersteiner.codeberg.page/#zdt.Datetime.fromISO8601) - shortcut to parse [ISO8601](https://en.wikipedia.org/wiki/ISO_8601)-compatible input formats.

#### From Unix time

- [`zdt.Datetime.fromUnix`](https://fobersteiner.codeberg.page/#zdt.Datetime.fromUnix) - must specify a resolution (seconds, microseconds etc.) for the input quantity; see also [`zdt.Duration.Resolution`](https://fobersteiner.codeberg.page/#zdt.Duration.Resolution). Optional  time zone or UTC offset.

### _Output:_ Datetime to something else

#### To string

- [`zdt.Datetime.toString`](https://fobersteiner.codeberg.page/#zdt.Datetime.toString) - see [formatting directives](https://github.com/FObersteiner/zdt/wiki/String-parsing-and-formatting-directives). Can either be called as a library function (`zdt.Datetime.toString`) or as a method of a datetime instance `dt`; `dt.toString`.
- [`zdt.Datetime.format`](https://fobersteiner.codeberg.page/#zdt.Datetime.format) - default ISO8601 representation including nanoseconds; this is used when printing a datetime with `{f}`.

#### To Unix time

- [`zdt.Datetime.toUnix`](https://fobersteiner.codeberg.page/#zdt.Datetime.toUnix) - a resolution must be specified, see `fromUnix`. Also to be called either as a library function or instance method.

#### To another time zone

- [`zdt.Datetime.tzConvert`](https://fobersteiner.codeberg.page/#zdt.Datetime.tzConvert) - convert an aware datetime to another time zone or UTC offset; the instant in time is preserved.
- [`zdt.Datetime.tzLocalize`](https://fobersteiner.codeberg.page/#zdt.Datetime.tzLocalize) - attach a time zone or UTC offset to a datetime; `null` makes an aware datetime naive again.

#### To ISO calendar

- [`zdt.Datetime.toISOCalendar`](https://fobersteiner.codeberg.page/#zdt.Datetime.toISOCalendar)

### Datetime arithmetic

#### Difference

- [`zdt.Datetime.diff`](https://fobersteiner.codeberg.page/#zdt.Datetime.diff) - absolute (physical) time difference between two datetimes. The inputs must be comparable: naive with naive, aware with aware.
- [`zdt.Datetime.diffWall`](https://fobersteiner.codeberg.page/#zdt.Datetime.diffWall) - wall-clock time difference, i.e. what a wall clock at the according locations would show.

#### Relative arithmetic

- [`zdt.Datetime.addRelative`](https://fobersteiner.codeberg.page/#zdt.Datetime.addRelative) - add a relative timespan which may include the ambiguous quantities years and months; see [`zdt.Duration.RelativeDelta`](https://fobersteiner.codeberg.page/#zdt.Duration.RelativeDelta).

## Duration

### _Input:_ Make a Duration

#### From an [ISO8601 duration](https://en.wikipedia.org/wiki/ISO_8601#Durations) string, absolute

- [`zdt.Duration.fromISO8601`](https://fobersteiner.codeberg.page/#zdt.Duration.fromISO8601) - note: since the Duration type represents an absolute difference in time, years and months are not allowed (see `RelativeDelta`).

#### From an ISO8601 duration string, relative timespan ("wall-time")

- [`zdt.Duration.RelativeDelta.fromISO8601`](https://fobersteiner.codeberg.page/#zdt.Duration.RelativeDelta.fromISO8601) - the RelativeDelta sub-type might include the ambiguous quantities years and months.

#### From multiples of a timespan

- [`zdt.Duration.fromTimespanMultiple`](https://fobersteiner.codeberg.page/#zdt.Duration.fromTimespanMultiple)

### _Output:_ Duration to something else

#### To multiple of a timespan

- [`zdt.Duration.toTimespanMultiple`](https://fobersteiner.codeberg.page/#zdt.Duration.toTimespanMultiple)

#### Total seconds

- [`zdt.Duration.totalSeconds`](https://fobersteiner.codeberg.page/#zdt.Duration.totalSeconds) - there are equivalent methods for total minutes, hours etc.

## Timezone

#### Constants

- [`zdt.Timezone.UTC`](https://fobersteiner.codeberg.page/#zdt.Timezone.UTC) - the built-in UTC time zone (no rules file required).
- [`zdt.UTCoffset`](https://fobersteiner.codeberg.page/#zdt.UTCoffset) - a bare UTC offset without time zone rules, e.g. from `zdt.UTCoffset.fromSeconds`.

#### From embedded tz database

- [`zdt.Timezone.fromTzdata`](https://fobersteiner.codeberg.page/#zdt.Timezone.fromTzdata)

#### From system tz database

- [`zdt.Timezone.fromSystemTzdata`](https://fobersteiner.codeberg.page/#zdt.Timezone.fromSystemTzdata). See also: `prefix_tzdb` option from build.zig - `Timezone.tzdb_prefix` can be used as db_path.
- [`zdt.Timezone.tzLocal`](https://fobersteiner.codeberg.page/#zdt.Timezone.tzLocal) - try to obtain the local time zone from the system.

#### From a POSIX TZ string

- [`zdt.Timezone.fromPosixTz`](https://fobersteiner.codeberg.page/#zdt.Timezone.fromPosixTz)

## Errors

- [`zdt.ZdtError`](https://fobersteiner.codeberg.page/#zdt.ZdtError) - the union error set returned by the fallible API functions (string parsing, range validation, time zone handling).

## Formats

- [`zdt.Formats`](https://fobersteiner.codeberg.page/#zdt.Formats) - a collection of common format strings (e.g. RFC3339, ANSI C) to use with `zdt.Datetime.toString` and `zdt.Datetime.fromString`.
