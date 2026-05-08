// SPDX-FileCopyrightText: 2024-2026 Florian Obersteiner
// SPDX-FileContributor: Florian Obersteiner <f.obersteiner@posteo.de>
//
// SPDX-License-Identifier: Unlicense

//! errors

pub const ZdtError = FormatError || RangeError || TzError || TZifReadError || WinTzError;

pub const FormatError = error{
    EmptyString,
    InvalidCharacter,
    InvalidDirective,
    InvalidFormat,
    InvalidFraction,
    OutOfMemory,
    Overflow,
    ParseIntError,
    Underflow,
    UnsupportedOS,
    WriteFailed,
};

pub const RangeError = error{
    DayOutOfRange,
    HourOutOfRange,
    MinuteOutOfRange,
    MonthOutOfRange,
    NanosecondOutOfRange,
    SecondOutOfRange,
    UnixOutOfRange,
    YearOutOfRange,
};

pub const TzError = error{
    AllTZRulesUndefined,
    AmbiguousDatetime,
    BadTZifVersion,
    CompareNaiveAware,
    InvalidIdentifier,
    InvalidOffset,
    InvalidPosixTz,
    InvalidTz,
    NonexistentDatetime,
    NotImplemented,
    TZifUnreadable,
    TzAlreadyDefined,
    TzUndefined,
};

pub const TZifReadError = error{
    AccessDenied,
    AntivirusInterference,
    BadHeader,
    BadPathName,
    BadVersion,
    BrokenPipe,
    Canceled,
    ConnectionResetByPeer,
    ConnectionTimedOut,
    DeviceBusy,
    EndOfStream,
    FileBusy,
    FileLocksUnsupported,
    FileNotFound,
    FileSystem,
    FileTooBig,
    InputOutput,
    InvalidUtf8,
    InvalidWtf8,
    IsDir,
    LockViolation,
    Malformed,
    NameTooLong,
    NetworkNotFound,
    NoDevice,
    NoSpaceLeft,
    NotDir,
    NotOpenForReading,
    NotSupported,
    OperationAborted,
    OutOfMemory,
    PathAlreadyExists,
    PermissionDenied,
    PipeBusy,
    ProcessFdQuotaExceeded,
    ProcessNotFound,
    ReadFailed,
    ReadOnlyFileSystem,
    SharingViolation,
    SocketNotConnected,
    StreamTooLong,
    SymLinkLoop,
    SystemFdQuotaExceeded,
    SystemResources,
    Unexpected,
    UnrecognizedVolume,
    WouldBlock,
};

pub const WinTzError = error{
    ReadRegistryFailed,
    TzNotFound,
    TzUtilFailed,
};
