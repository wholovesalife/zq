const std = @import("std");
const json = @import("json.zig");

pub const QueryError = error{
    KeyNotFound,
    IndexOutOfBounds,
    NotAnObject,
    NotAnArray,
    NotIterable,
    InvalidQuery,
    OutOfMemory,
    InvalidFilter,
};

pub const ResultList = std.ArrayList(json.Value);

pub fn query(allocator: std.mem.Allocator, root: json.Value, q: []const u8) !ResultList {
    var results = ResultList.init(allocator);
    errdefer results.deinit();

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

    for (current.items) |v| {
        try results.append(v);
    }
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
            '|' => {
                if (depth == 0) {
                    try out.append(q[start..i]);
                    start = i + 1;
                }
            },
            else => {},
        }
    }
    try out.append(q[start..]);
}

fn applyStage(allocator: std.mem.Allocator, val: json.Value, stage: []const u8, out: *ResultList) !void {
    if (std.mem.eql(u8, stage, ".")) {
        try out.append(val);
        return;
    }

    if (std.mem.eql(u8, stage, "keys")) {
        return applyKeys(allocator, val, out);
    }

    if (std.mem.eql(u8, stage, "length")) {
        return applyLength(val, out);
    }

    if (std.mem.eql(u8, stage, "values")) {
        return applyValues(val, out);
    }

    if (std.mem.eql(u8, stage, "type")) {
        return applyType(allocator, val, out);
    }

    if (std.mem.eql(u8, stage, "not")) {
        return applyNot(val, out);
    }

    if (std.mem.eql(u8, stage, ".[]")) {
        return applyIterator(val, out);
    }

    if (std.mem.eql(u8, stage, "..")) {
        try recurseAll(val, out);
        return;
    }

    if (std.mem.startsWith(u8, stage, "select(") and std.mem.endsWith(u8, stage, ")")) {
        const inner = stage[7 .. stage.len - 1];
        return applySelect(allocator, val, inner, out);
    }

    if (std.mem.startsWith(u8, stage, "has(") and std.mem.endsWith(u8, stage, ")")) {
        const inner = stage[4 .. stage.len - 1];
        return applyHas(allocator, val, inner, out);
    }

    if (std.mem.eql(u8, stage, "to_entries")) {
        return applyToEntries(allocator, val, out);
    }

    if (stage.len > 0 and stage[0] == '.') {
        return applyPath(allocator, val, stage[1..], out);
    }

    return applyPath(allocator, val, stage, out);
}

fn applyPath(allocator: std.mem.Allocator, val: json.Value, path: []const u8, out: *ResultList) !void {
    if (path.len == 0) {
        try out.append(val);
        return;
    }

    if (std.mem.startsWith(u8, path, "[]")) {
        var sub = ResultList.init(allocator);
        defer sub.deinit();
        try applyIterator(val, &sub);
        const rest = path[2..];
        const rest2 = if (rest.len > 0 and rest[0] == '.') rest[1..] else rest;
        for (sub.items) |item| {
            try applyPath(allocator, item, rest2, out);
        }
        return;
    }

    if (std.mem.startsWith(u8, path, "[\"")) {
        const end = std.mem.indexOf(u8, path, "\"]") orelse return error.InvalidQuery;
        const key = path[2..end];
        const rest = path[end + 2 ..];
        const child = try fieldAccess(val, key);
        const rest2 = if (rest.len > 0 and rest[0] == '.') rest[1..] else rest;
        try applyPath(allocator, child, rest2, out);
        return;
    }

    if (path[0] == '[') {
        const close = std.mem.indexOf(u8, path, "]") orelse return error.InvalidQuery;
        const idx_str = path[1..close];
        const rest = path[close + 1 ..];
        const idx = try std.fmt.parseInt(isize, idx_str, 10);
        const child = try indexAccess(val, idx);
        const rest2 = if (rest.len > 0 and rest[0] == '.') rest[1..] else rest;
        try applyPath(allocator, child, rest2, out);
        return;
    }

    var seg_end = path.len;
    for (path, 0..) |c, i| {
        if (c == '.' or c == '[') {
            seg_end = i;
            break;
        }
    }

    const seg = path[0..seg_end];
    const rest = path[seg_end..];

    if (seg.len == 0) {
        try applyPath(allocator, val, rest[1..], out);
        return;
    }

    const child = try fieldAccess(val, seg);
    const rest2 = if (rest.len > 0 and rest[0] == '.') rest[1..] else rest;
    try applyPath(allocator, child, rest2, out);
}

fn fieldAccess(val: json.Value, key: []const u8) !json.Value {
    switch (val) {
        .object => |m| {
            return m.get(key) orelse error.KeyNotFound;
        },
        else => return error.NotAnObject,
    }
}

fn indexAccess(val: json.Value, idx: isize) !json.Value {
    switch (val) {
        .array => |a| {
            const len = @as(isize, @intCast(a.items.len));
            const i: isize = if (idx < 0) len + idx else idx;
            if (i < 0 or i >= len) {
            return error.IndexOutOfBounds;
        }
            return a.items[@intCast(i)];
        },
        else => return error.NotAnArray,
    }
}

fn applyIterator(val: json.Value, out: *ResultList) !void {
    switch (val) {
        .array => |a| {
            for (a.items) |item| try out.append(item);
        },
        .object => |m| {
            var it = m.iterator();
            while (it.next()) |entry| try out.append(entry.value_ptr.*);
        },
        else => return error.NotIterable,
    }
}

fn applyKeys(allocator: std.mem.Allocator, val: json.Value, out: *ResultList) !void {
    switch (val) {
        .object => |m| {
            var arr = std.ArrayList(json.Value).init(allocator);
            var it = m.iterator();
            while (it.next()) |entry| {
                const s = try allocator.dupe(u8, entry.key_ptr.*);
                try arr.append(json.Value{ .string = s });
            }
            std.sort.pdq(json.Value, arr.items, {}, struct {
                fn lt(_: void, a: json.Value, b: json.Value) bool {
                    return std.mem.lessThan(u8, a.string, b.string);
                }
            }.lt);
            try out.append(json.Value{ .array = arr });
        },
        .array => |a| {
            var arr = std.ArrayList(json.Value).init(allocator);
            for (0..a.items.len) |i| {
                try arr.append(json.Value{ .number = @floatFromInt(i) });
            }
            try out.append(json.Value{ .array = arr });
        },
        else => return error.NotAnObject,
    }
}

fn applyValues(val: json.Value, out: *ResultList) !void {
    switch (val) {
        .object => |m| {
            var arr = std.ArrayList(json.Value).init(out.allocator);
            var it = m.iterator();
            while (it.next()) |entry| try arr.append(entry.value_ptr.*);
            try out.append(json.Value{ .array = arr });
        },
        .array => |a| {
            var arr = std.ArrayList(json.Value).init(out.allocator);
            for (a.items) |item| try arr.append(item);
            try out.append(json.Value{ .array = arr });
        },
        else => return error.NotIterable,
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

fn applyType(allocator: std.mem.Allocator, val: json.Value, out: *ResultList) !void {
    const t = switch (val) {
        .object => "object",
        .array => "array",
        .string => "string",
        .number => "number",
        .boolean => "boolean",
        .null_val => "null",
    };
    const s = try allocator.dupe(u8, t);
    try out.append(json.Value{ .string = s });
}

fn applyNot(val: json.Value, out: *ResultList) !void {
    const b = switch (val) {
        .boolean => |b| b,
        .null_val => false,
        else => true,
    };
    try out.append(json.Value{ .boolean = !b });
}

fn recurseAll(val: json.Value, out: *ResultList) !void {
    try out.append(val);
    switch (val) {
        .object => |m| {
            var it = m.iterator();
            while (it.next()) |entry| {
                try recurseAll(entry.value_ptr.*, out);
            }
        },
        .array => |a| {
            for (a.items) |item| {
                try recurseAll(item, out);
            }
        },
        else => {},
    }
}

// select(expr) keeps values where expr evaluates to truthy
fn applySelect(allocator: std.mem.Allocator, val: json.Value, expr: []const u8, out: *ResultList) !void {
    var sub = ResultList.init(allocator);
    defer sub.deinit();
    try applyStage(allocator, val, expr, &sub);

    if (sub.items.len == 0) return;
    const result = sub.items[0];
    const keep = switch (result) {
        .boolean => |b| b,
        .null_val => false,
        else => true,
    };
    if (keep) try out.append(val);
}

fn applyHas(allocator: std.mem.Allocator, val: json.Value, inner: []const u8, out: *ResultList) !void {
    _ = allocator;
    const trimmed = std.mem.trim(u8, inner, " \t\"");
    const found = switch (val) {
        .object => |m| m.contains(trimmed),
        .array => |a| blk: {
            const idx = std.fmt.parseInt(usize, trimmed, 10) catch break :blk false;
            break :blk idx < a.items.len;
        },
        else => false,
    };
    try out.append(json.Value{ .boolean = found });
}

fn applyToEntries(allocator: std.mem.Allocator, val: json.Value, out: *ResultList) !void {
    var arr = std.ArrayList(json.Value).init(allocator);
    switch (val) {
        .object => |m| {
            var it = m.iterator();
            while (it.next()) |entry| {
                var obj = std.StringArrayHashMap(json.Value).init(allocator);
                const k = try allocator.dupe(u8, entry.key_ptr.*);
                const kk = try allocator.dupe(u8, "key");
                const vk = try allocator.dupe(u8, "value");
                try obj.put(kk, json.Value{ .string = k });
                try obj.put(vk, entry.value_ptr.*);
                try arr.append(json.Value{ .object = obj });
            }
        },
        .array => |a| {
            for (a.items, 0..) |item, i| {
                var obj = std.StringArrayHashMap(json.Value).init(allocator);
                const kk = try allocator.dupe(u8, "key");
                const vk = try allocator.dupe(u8, "value");
                try obj.put(kk, json.Value{ .number = @floatFromInt(i) });
                try obj.put(vk, item);
                try arr.append(json.Value{ .object = obj });
            }
        },
        else => return error.NotIterable,
    }
    try out.append(json.Value{ .array = arr });
}
// type coercion query
// has() builtin
// not filter
// stage "." is the identity filter — it forwards the input value unchanged
// splitPipe: empty string produces a single empty stage which applyStage handles as identity
// recurseAll emits nodes in pre-order DFS: parent before children, arrays left-to-right
// applyKeys: object keys are sorted with pdq sort before emitting the array
// applyNot: only .boolean and .null_val are falsy; all other types are truthy
// applyLength: null_val returns 0, matching jq behavior
// applyHas: trims surrounding whitespace and quotes from the key before lookup
// splitPipe: depth counter ensures | inside [..] is not treated as a pipe separator
// applyToEntries: each entry is {key: string|number, value: any}; mirrors jq to_entries
// fieldAccess: missing key returns error.KeyNotFound, not null; callers handle this explicitly
// applyType: returns JSON type names ("object", "array", etc.), not Zig ValueType enum names
// applySelect: sub.items.len == 0 is treated as falsy (no output), matching jq select behavior
// applyValues: both object and array variants produce a new ArrayList wrapping the values
// indexAccess: negative idx wraps from end (idx < 0: effective = len + idx)
// applyIterator: scalar values (.string, .number, .boolean, .null_val) return NotIterable
// applyKeys on an array yields numeric indices [0, 1, ..., n-1] as .number values
// applyStage: unrecognised bare names fall through to applyPath, treating them as field names
// applyStage receives a trimmed slice; leading and trailing spaces are stripped in the loop
// applyPath: stage[0] == '.' is stripped before dispatch so .foo and foo are both valid
