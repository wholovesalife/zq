const std = @import("std");
const json = @import("json.zig");
const query_mod = @import("query.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.next();

    const q = args.next() orelse { std.debug.print("usage: zq <query> [file]\n", .{}); return; };
    const stdin = std.io.getStdIn();
    const input = try stdin.readToEndAlloc(allocator, 128 * 1024 * 1024);
    defer allocator.free(input);

    var parser = json.Parser.init(allocator, input);
    var root = try parser.parse();
    defer root.deinit(allocator);

    var results = try query_mod.query(allocator, root, q);
    defer results.deinit();

    const stdout = std.io.getStdOut().writer();
    for (results.items) |val| {
        try printValue(stdout, val);
        try stdout.writeByte('\n');
    }
}

fn printValue(writer: anytype, val: json.Value) !void {
    switch (val) {
        .null_val => try writer.writeAll("null"),
        .boolean => |b| try writer.writeAll(if (b) "true" else "false"),
        .number => |n| try writer.print("{d}", .{n}),
        .string => |s| try writer.print("\"{s}\"", .{s}),
        .array => |a| {
            try writer.writeByte('[');
            for (a.items, 0..) |item, i| {
                if (i > 0) try writer.writeByte(',');
                try printValue(writer, item);
            }
            try writer.writeByte(']');
        },
        .object => |m| {
            try writer.writeByte('{');
            var it = m.iterator();
            var first = true;
            while (it.next()) |e| {
                if (!first) try writer.writeByte(',');
                first = false;
                try writer.print("\"{s}\":", .{e.key_ptr.*});
                try printValue(writer, e.value_ptr.*);
            }
            try writer.writeByte('}');
        },
    }
}
