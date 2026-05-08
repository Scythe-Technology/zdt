# Roadmap

- extend range of datetimes that can be represented; 5-digit signed year

- host/run docs and CI on codeberg (<https://codeberg.org/FObersteiner/zdt/issues/15>, <https://codeberg.org/FObersteiner/zdt/issues/7>)

- experiment with comptime-generation of timezone database

- iso-caledar parsing and formatting with `%G %V %u` directives

- improve parser flagging?

- Windows: handle tz with DST disabled (<https://codeberg.org/FObersteiner/zdt/issues/1>)

- locale-specific parsing (`%a, %A, %b, %B`) on Windows (<https://codeberg.org/FObersteiner/zdt/issues/3>)

- parser: consider day name if supplied
  - check if a day-of-month or day-of-year is supplied as well
  - allow to create a date if a week-of-year is supplied as well
