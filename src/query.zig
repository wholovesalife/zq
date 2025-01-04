const std = @import("std");
const json = @import("json.zig");

pub const QueryError = error{
    KeyNotFound, IndexOutOfBounds, NotAnObject, NotAnArray, InvalidQuery, OutOfMemory,
};

pub const ResultList = std.ArrayList(json.Value);

pub fn query(allocator: std.mem.Allocator, root: json.Value, q: []const u8) !ResultList {
    var results = ResultList.init(allocator);
    var current = ResultList.init(allocator);
    defer current.deinit();
    try current.append(root);

    for (current.items) |val| {
        try applyStage(allocator, val, q, &results);
    }
    return results;
}

fn applyStage(allocator: std.mem.Allocator, val: json.Value, stage: []const u8, out: *ResultList) !void {
    const s = std.mem.trim(u8, stage, " \t");
    if (std.mem.eql(u8, s, ".")) { try out.append(val); return; }
    if (s.len > 0 and s[0] == '.') return applyPath(allocator, val, s[1..], out);
}

fn applyPath(allocator: std.mem.Allocator, val: json.Value, path: []const u8, out: *ResultList) !void {
    _ = allocator;
    if (path.len == 0) { try out.append(val); return; }

    if (path[0] == '[') {
        const close = std.mem.indexOf(u8, path, "]") orelse return error.InvalidQuery;
        const idx = try std.fmt.parseInt(isize, path[1..close], 10);
        const rest = path[close + 1 ..];
        const child = try indexAccess(val, idx);
        const rest2 = if (rest.len > 0 and rest[0] == '.') rest[1..] else rest;
        try applyPath(allocator, child, rest2, out);
        return;
    }

    var seg_end = path.len;
    for (path, 0..) |c, i| {
        if (c == '.' or c == '[') { seg_end = i; break; }
    }
    const seg = path[0..seg_end];
    const rest = path[seg_end..];
    const child = try fieldAccess(val, seg);
    const rest2 = if (rest.len > 0 and rest[0] == '.') rest[1..] else rest;
    try applyPath(allocator, child, rest2, out);
}

fn fieldAccess(val: json.Value, key: []const u8) !json.Value {
    switch (val) {
        .object => |m| return m.get(key) orelse error.KeyNotFound,
        else => return error.NotAnObject,
    }
}

fn indexAccess(val: json.Value, idx: isize) !json.Value {
    switch (val) {
        .array => |a| {
            const len = @as(isize, @intCast(a.items.len));
            const i: isize = if (idx < 0) len + idx else idx;
            if (i < 0 or i >= len) return error.IndexOutOfBounds;
            return a.items[@intCast(i)];
        },
        else => return error.NotAnArray,
    }
}
