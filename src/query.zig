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
    if (std.mem.eql(u8, stage, "keys")) { return applyKeys(allocator, val, out); }
    if (std.mem.eql(u8, stage, "length")) { return applyLength(val, out); }
    if (std.mem.eql(u8, stage, "values")) {
        var arr = std.ArrayList(json.Value).init(allocator);
        switch (val) {
            .object => |m| { var it = m.iterator(); while (it.next()) |e| try arr.append(e.value_ptr.*); },
            .array => |a| { for (a.items) |item| try arr.append(item); },
            else => return error.NotIterable,
        }
        try out.append(json.Value{ .array = arr });
        return;
    }
    if (stage.len > 0 and stage[0] == '.') return applyPath(allocator, val, stage[1..], out);
    return applyPath(allocator, val, stage, out);
}

fn applyPath(allocator: std.mem.Allocator, val: json.Value, path: []const u8, out: *ResultList) !void {
    if (path.len == 0) { try out.append(val); return; }

    if (std.mem.startsWith(u8, path, "[]")) {
        var sub = ResultList.init(allocator);
        defer sub.deinit();
        try applyIterator(val, &sub);
        const rest = path[2..];
        const rest2 = if (rest.len > 0 and rest[0] == '.') rest[1..] else rest;
        for (sub.items) |item| try applyPath(allocator, item, rest2, out);
        return;
    }

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
    for (path, 0..) |c, i| { if (c == '.' or c == '[') { seg_end = i; break; } }
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

fn applyIterator(val: json.Value, out: *ResultList) !void {
    switch (val) {
        .array => |a| for (a.items) |item| try out.append(item),
        .object => |m| { var it = m.iterator(); while (it.next()) |e| try out.append(e.value_ptr.*); },
        else => return error.NotIterable,
    }
}

fn applyKeys(allocator: std.mem.Allocator, val: json.Value, out: *ResultList) !void {
    switch (val) {
        .object => |m| {
            var arr = std.ArrayList(json.Value).init(allocator);
            var it = m.iterator();
            while (it.next()) |e| {
                const s = try allocator.dupe(u8, e.key_ptr.*);
                try arr.append(json.Value{ .string = s });
            }
            // Sort keys
            std.sort.pdq(json.Value, arr.items, {}, struct {
                fn lt(_: void, a: json.Value, b: json.Value) bool {
                    return std.mem.lessThan(u8, a.string, b.string);
                }
            }.lt);
            try out.append(json.Value{ .array = arr });
        },
        .array => |a| {
            var arr = std.ArrayList(json.Value).init(allocator);
            for (0..a.items.len) |i| try arr.append(json.Value{ .number = @floatFromInt(i) });
            try out.append(json.Value{ .array = arr });
        },
        else => return error.NotAnObject,
    }
}

fn applyLength(val: json.Value, out: *ResultList) !void {
    const n: f64 = switch (val) {
        .array => |a| @floatFromInt(a.items.len),
        .object => |m| @floatFromInt(m.count()),
        .string => |s| @floatFromInt(s.len),
        .null_val => 0,
        else => return error.InvalidQuery,
    };
    try out.append(json.Value{ .number = n });
}
