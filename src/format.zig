const std = @import("std");

/// Pretty-print a JSON value with optional indentation.
pub fn prettyPrint(writer: anytype, value: []const u8, indent: usize) !void {
    var depth: usize = 0;
    var in_string = false;
    var i: usize = 0;
    while (i < value.len) : (i += 1) {
        const c = value[i];
        if (in_string) {
            try writer.writeByte(c);
            if (c == '\\') { i += 1; if (i < value.len) try writer.writeByte(value[i]); }
            else if (c == '"') in_string = false;
        } else switch (c) {
            '{', '[' => {
                depth += 1;
                try writer.writeByte(c);
                try writer.writeByte('\n');
                try writeIndent(writer, depth * indent);
            },
            '}', ']' => {
                depth -= 1;
                try writer.writeByte('\n');
                try writeIndent(writer, depth * indent);
                try writer.writeByte(c);
            },
            ',' => {
                try writer.writeByte(c);
                try writer.writeByte('\n');
                try writeIndent(writer, depth * indent);
            },
            ':' => try writer.writeAll(": "),
            '"' => { in_string = true; try writer.writeByte(c); },
            ' ', '\t', '\n', '\r' => {},
            else => try writer.writeByte(c),
        }
    }
    try writer.writeByte('\n');
}

fn writeIndent(writer: anytype, n: usize) !void {
    var i: usize = 0;
    while (i < n) : (i += 1) try writer.writeByte(' ');
}
// indent width: 2 spaces per depth level (matches jq default pretty-print)
