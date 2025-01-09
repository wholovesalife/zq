const std = @import("std");
const json = @import("json.zig");

pub const QueryError = error{
    KeyNotFound, IndexOutOfBounds, NotAnObject, NotAnArray, NotIterable, InvalidQuery, OutOfMemory,
};

pub const ResultList = std.ArrayList(json.Value);

pub fn query(allocator: std.mem.Allocator, root: json.Value, q: []const u8) !ResultList {
    var stages = std.ArrayList([]const u8).init(allocator);
    defer stages.deinit();
    try splitPipe(q, &stages);

    var current = ResultList.init(allocator);
    defer current.deinit();
    try current.append(root);

    for (stages.items) |stage| {
        const trimmed = std.mem.trim(u8, stage, " \t");
        var next = ResultList.init(allocator);
        errdefer next.deinit();
        for (current.items) |val| {
            try applyStage(allocator, val, trimmed, &next);
        }
        current.deinit();
        current = next;
    }

    var results = ResultList.init(allocator);
    for (current.items) |v| try results.append(v);
    return results;
}

fn splitPipe(q: []const u8, out: *std.ArrayList([]const u8)) !void {
    var start: usize = 0;
    var depth: usize = 0;
    var i: usize = 0;
    while (i < q.len) : (i += 1) {
        switch (q[i]) {
            '[' => depth += 1,
            ']' => if (depth > 0) { depth -= 1; },
            '|' => if (depth == 0) { try out.append(q[start..i]); start = i + 1; },
            else => {},
        }
    }
    try out.append(q[start..]);
}

fn applyStage(allocator: std.mem.Allocator, val: json.Value, stage: []const u8, out: *ResultList) !void {
    if (std.mem.eql(u8, stage, ".")) { try out.append(val); return; }
    if (std.mem.eql(u8, stage, ".[]")) { return applyIterator(val, out); }
    if (stage.len > 0 and stage[0] == '.') return applyPath(allocator, val, stage[1..], out);
    return applyPath(allocator, val, stage, out);
}

fn applyPath(allocator: std.mem.Allocator, val: json.Value, path: []const u8, out: *ResultList) !void {
    _ = allocator;
    if (path.len == 0) { try out.append(val); return; }

    if (std.mem.startsWith(u8, path, "[]")) {
        var sub = ResultList.init(out.allocator);
        defer sub.deinit();
        try applyIterator(val, &sub);
        const rest = path[2..];
        const rest2 = if (rest.len > 0 and rest[0] == '.') rest[1..] else rest;
        for (sub.items) |item| try applyPath(out.allocator, item, rest2, out);
        return;
    }

    if (path[0] == '[') {
        const close = std.mem.indexOf(u8, path, "]") orelse return error.InvalidQuery;
        const idx = try std.fmt.parseInt(isize, path[1..close], 10);
        const rest = path[close + 1 ..];
        const child = try indexAccess(val, idx);
        const rest2 = if (rest.len > 0 and rest[0] == '.') rest[1..] else rest;
        try applyPath(out.allocator, child, rest2, out);
        return;
    }

    var seg_end = path.len;
    for (path, 0..) |c, i| { if (c == '.' or c == '[') { seg_end = i; break; } }
    const seg = path[0..seg_end];
    const rest = path[seg_end..];
    const child = try fieldAccess(val, seg);
    const rest2 = if (rest.len > 0 and rest[0] == '.') rest[1..] else rest;
    try applyPath(out.allocator, child, rest2, out);
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

fn applyIterator(val: json.Value, out: *ResultList) !void {
    switch (val) {
        .array => |a| for (a.items) |item| try out.append(item),
        .object => |m| { var it = m.iterator(); while (it.next()) |e| try out.append(e.value_ptr.*); },
        else => return error.NotIterable,
    }
}
