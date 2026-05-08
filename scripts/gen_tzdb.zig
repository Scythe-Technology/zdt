// SPDX-FileCopyrightText: 2024-2026 Florian Obersteiner
// SPDX-FileContributor: Florian Obersteiner <f.obersteiner@posteo.de>
//
// SPDX-License-Identifier: Unlicense

//! Update eggert/tz submodule, build the time zone database and move
//! its 'zoneinfo' directory to /lib/tzdata. Remove all other build artifacts.
//
// to add the submodule, run `git submodule add -f https://github.com/eggert/tz ./tz`
const std = @import("std");
const log = std.log.scoped(.zdt__gen_tzdb);

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const io = init.io;

    var args_iter = try init.minimal.args.iterateAllocator(allocator);
    defer args_iter.deinit();
    if (!args_iter.skip()) @panic("expected self arg");

    // tag to check out
    const tzdbtag = args_iter.next();

    // 1) update git submodule, eggert/tz
    //
    const argv_update = [_][]const u8{
        "git",
        "submodule",
        "update",
        "--init", // --init and
        "--recursive", // --recursive flags used here to work around a pyenv bug
        "--remote",
        "./tz",
    };
    const proc_update = try std.process.run(allocator, io, .{
        .argv = &argv_update,
    });

    if (proc_update.stderr.len > 0) {
        log.err("update command failed : {s} ({d})", .{ proc_update.stderr, proc_update.stderr.len });
        allocator.free(proc_update.stdout);
        allocator.free(proc_update.stderr);
        return;
    }

    if (proc_update.stdout.len > 0) {
        log.info("submodule update stdout: {s}", .{proc_update.stdout});
    } else {
        log.info("submodule update: no updates available", .{});
    }
    allocator.free(proc_update.stdout);
    allocator.free(proc_update.stderr);

    // 2) checkout specific tag of tzdata
    //
    log.info("tz database tag: {s}", .{tzdbtag.?});
    const argv_tagcheckout = [_][]const u8{
        "git",
        "-C",
        "./tz",
        "checkout",
        tzdbtag.?,
    };
    const proc_tag = try std.process.run(allocator, io, .{
        .argv = &argv_tagcheckout,
    });

    if (proc_tag.stderr.len > 0) {
        log.warn("tag checkout command : {s} ({d})", .{ proc_tag.stderr, proc_tag.stderr.len });
    }
    if (proc_tag.stdout.len > 0) {
        log.info("submodule update stdout: {s}", .{proc_update.stdout});
    }
    allocator.free(proc_tag.stdout);
    allocator.free(proc_tag.stderr);

    // where to run makefile
    const tz_dir = args_iter.next();

    // where to put tzdata
    const target_dir = args_iter.next();

    // 3) compile tzdata
    //
    var path_buffer: [std.Io.Dir.max_path_bytes + 8]u8 = undefined;
    const target_dir_cmd = try std.fmt.bufPrint(&path_buffer, "DESTDIR={s}", .{target_dir.?});

    const argv_compile = [_][]const u8{ "make", target_dir_cmd, "ZFLAGS=-b fat", "POSIXRULES=", "install" };

    const proc_compile = try std.process.run(allocator, io, .{
        .cwd = .{ .path = tz_dir.? },
        .argv = &argv_compile,
    });
    if (proc_compile.stdout.len > 0) {
        log.info("tzdb compile step, stdout: {s}", .{proc_compile.stdout});
    }
    if (proc_compile.stderr.len > 0) {
        log.warn("tzdb compile step, stderr: {s}", .{proc_compile.stderr});
        log.info("note: localtime error can be ignored.", .{});
    }
    allocator.free(proc_compile.stdout);
    allocator.free(proc_compile.stderr);

    const tzdata_src_str = try std.fmt.bufPrint(&path_buffer, "{s}/{s}/usr/share/zoneinfo", .{ tz_dir.?, target_dir.? });
    var tzdata_src_Dir = try std.Io.Dir.cwd().openDir(io, tzdata_src_str, .{ .iterate = true });

    // 4) copy only the usr/share/zoneinfo directory into ./lib
    //
    _ = try std.Io.Dir.cwd().createDirPath(io, target_dir.?);
    var target_Dir = try std.Io.Dir.cwd().openDir(io, target_dir.?, .{});

    // 4.1) clean target directory so that there are no residuals from older versions
    //
    _ = target_Dir.deleteTree(io, "") catch |err| {
        log.warn("clean target dir error : {}", .{err});
    };

    var walker = try tzdata_src_Dir.walk(allocator);
    errdefer walker.deinit();

    while (try walker.next(io)) |entry| {
        switch (entry.kind) {
            .file => {
                entry.dir.copyFile(entry.basename, target_Dir, entry.path, io, .{}) catch |err| {
                    log.warn("copy file: {}", .{err});
                };
            },
            .directory => {
                target_Dir.createDir(io, entry.path, .default_dir) catch |err| {
                    log.warn("make dir: {}, path: {s}", .{ err, entry.path });
                };
            },
            else => {
                log.warn("unexpected entry kind {any} for {s}", .{ entry.kind, entry.basename });
            },
        }
    }

    target_Dir.close(io);
    walker.deinit();

    // 5) delete tzdata source directory
    //
    _ = tzdata_src_Dir.deleteTree(io, "") catch |err| {
        log.warn("delete src dir error : {}", .{err});
    };
    tzdata_src_Dir.close(io);

    // 6) make Windows tz mapping
    //
    const proc_wintzmapping = try std.process.run(allocator, io, .{
        .cwd = .{ .path = "." },
        .argv = &[_][]const u8{
            "python3",
            "scripts/gen_wintz_mapping.py",
        },
    });
    if (proc_wintzmapping.stdout.len > 0) {
        log.info("tzdb make win tz mappeing step, stdout: {s}", .{proc_wintzmapping.stdout});
    }
    if (proc_wintzmapping.stderr.len > 0) {
        log.warn("tzdb make win tz mappeing step, stderr: {s}", .{proc_wintzmapping.stderr});
    }
    allocator.free(proc_wintzmapping.stdout);
    allocator.free(proc_wintzmapping.stderr);

    // 6) make tzdata embedding
    //
    const proc_tzembed = try std.process.run(allocator, io, .{
        .cwd = .{ .path = "." },
        .argv = &[_][]const u8{
            "python3",
            "scripts/gen_tzdb_embedding.py",
            tzdbtag.?,
        },
    });
    if (proc_tzembed.stdout.len > 0) {
        log.info("tzdb embedding mappeing step, stdout: {s}", .{proc_tzembed.stdout});
    }
    if (proc_tzembed.stderr.len > 0) {
        log.warn("tzdb embedding step, stderr: {s}", .{proc_tzembed.stderr});
    }
    allocator.free(proc_tzembed.stdout);
    allocator.free(proc_tzembed.stderr);

    return std.process.cleanExit(io);
}
