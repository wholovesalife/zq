const std = @import("std");
const json = @import("json.zig");
const query_mod = @import("query.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const gpa_alloc = gpa.allocator();

    // Arena for query evaluation — bulk-free at end of query stage
    var arena = std.heap.ArenaAllocator.init(gpa_alloc);
    defer arena.deinit();
    const allocator = arena.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.next();

    var compact = false;
    var raw = false;
    var query_str: ?[]const u8 = null;
    var file_path: ?[]const u8 = null;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-c")) {
            compact = true;
        } else if (std.mem.eql(u8, arg, "-r")) {
            raw = true;
        } else if (query_str == null) {
            query_str = arg;
        } else if (file_path == null) {
            file_path = arg;
        }
    }

    const q = query_str orelse {
        std.debug.print("usage: zq [-c] [-r] <query> [file]\n", .{});
        std.process.exit(1);
    };

    const input: []const u8 = if (file_path) |path| blk: {
        const file = std.fs.cwd().openFile(path, .{}) catch |err| {
            std.debug.print("zq: cannot open '{s}': {}\n", .{ path, err });
            std.process.exit(1);
        };
        defer file.close();
        break :blk try file.readToEndAlloc(allocator, 128 * 1024 * 1024);
    } else blk: {
        break :blk try std.io.getStdIn().readToEndAlloc(allocator, 128 * 1024 * 1024);
    };
    defer allocator.free(input);

    var parser = json.Parser.init(allocator, input);
    var root = parser.parse() catch |err| {
        std.debug.print("zq: parse error: {}\n", .{err});
        std.process.exit(1);
    };
    defer root.deinit(allocator);

    var results = query_mod.query(allocator, root, q) catch |err| {
        std.debug.print("zq: query error: {}\n", .{err});
        std.process.exit(1);
    };
    defer results.deinit();

    const stdout = std.io.getStdOut().writer();
    for (results.items) |val| {
        if (raw) {
            switch (val) {
                .string => |s| { try stdout.print("{s}\n", .{s}); continue; },
                else => {},
            }
        }
        try printValue(stdout, val, compact, 0);
        try stdout.writeByte('\n');
    }
}

fn printValue(writer: anytype, val: json.Value, compact: bool, depth: usize) !void {
    switch (val) {
        .null_val => try writer.writeAll("null"),
        .boolean => |b| try writer.writeAll(if (b) "true" else "false"),
        .number => |n| {
            if (n == @trunc(n) and @abs(n) < 1e15) {
                try writer.print("{d}", .{@as(i64, @intFromFloat(n))});
            } else {
                try writer.print("{d}", .{n});
            }
        },
        .string => |s| {
            try writer.writeByte('"');
            for (s) |c| {
                switch (c) {
                    '"' => try writer.writeAll("\\\""),
                    '\\' => try writer.writeAll("\\\\"),
                    '\n' => try writer.writeAll("\\n"),
                    '\t' => try writer.writeAll("\\t"),
                    '\r' => try writer.writeAll("\\r"),
                    else => try writer.writeByte(c),
                }
            }
            try writer.writeByte('"');
        },
        .array => |a| {
            try writer.writeByte('[');
            for (a.items, 0..) |item, i| {
                if (i > 0) try writer.writeByte(',');
                if (!compact) { try writer.writeByte('\n'); try writeIndent(writer, depth + 1); }
                try printValue(writer, item, compact, depth + 1);
            }
            if (!compact and a.items.len > 0) { try writer.writeByte('\n'); try writeIndent(writer, depth); }
            try writer.writeByte(']');
        },
        .object => |m| {
            try writer.writeByte('{');
            var it = m.iterator();
            var first = true;
            while (it.next()) |e| {
                if (!first) try writer.writeByte(',');
                first = false;
                if (!compact) { try writer.writeByte('\n'); try writeIndent(writer, depth + 1); }
                try writer.writeByte('"');
                try writer.writeAll(e.key_ptr.*);
                try writer.writeAll(if (compact) "\":" else "\": ");
                try printValue(writer, e.value_ptr.*, compact, depth + 1);
            }
            if (!compact and m.count() > 0) { try writer.writeByte('\n'); try writeIndent(writer, depth); }
            try writer.writeByte('}');
        },
    }
}

fn writeIndent(writer: anytype, depth: usize) !void {
    for (0..depth) |_| try writer.writeAll("  ");
}
