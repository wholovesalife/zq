const std = @import("std");

pub const TokenType = enum {
    lbrace,
    rbrace,
    lbracket,
    rbracket,
    colon,
    comma,
    string,
    number,
    true_lit,
    false_lit,
    null_lit,
    eof,
};

pub const Token = struct {
    typ: TokenType,
    value: []const u8,
    pos: usize,
};

pub const Tokenizer = struct {
    src: []const u8,
    pos: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, src: []const u8) Tokenizer {
        return .{ .src = src, .pos = 0, .allocator = allocator };
    }

    fn skipWhitespace(self: *Tokenizer) void {
        while (self.pos < self.src.len and
            (self.src[self.pos] == ' ' or self.src[self.pos] == '\t' or
            self.src[self.pos] == '\n' or self.src[self.pos] == '\r'))
        {
            self.pos += 1;
        }
    }

    fn readString(self: *Tokenizer) ![]const u8 {
        self.pos += 1; // skip opening quote
        var buf = std.ArrayList(u8).init(self.allocator);
        defer buf.deinit();

        while (self.pos < self.src.len) {
            const c = self.src[self.pos];
            if (c == '"') {
                self.pos += 1;
                return try buf.toOwnedSlice();
            } else if (c == '\\') {
                self.pos += 1;
                if (self.pos >= self.src.len) return error.UnexpectedEof;
                const esc = self.src[self.pos];
                switch (esc) {
                    '"' => try buf.append('"'),
                    '\\' => try buf.append('\\'),
                    '/' => try buf.append('/'),
                    'n' => try buf.append('\n'),
                    't' => try buf.append('\t'),
                    'r' => try buf.append('\r'),
                    'b' => try buf.append(8),
                    'f' => try buf.append(12),
                    'u' => {
                        if (self.pos + 4 >= self.src.len) return error.InvalidUnicodeEscape;
                        const hex = self.src[self.pos + 1 .. self.pos + 5];
                        const codepoint = try std.fmt.parseInt(u21, hex, 16);
                        var encoded: [4]u8 = undefined;
                        const len = try std.unicode.utf8Encode(codepoint, &encoded);
                        try buf.appendSlice(encoded[0..len]);
                        self.pos += 4;
                    },
                    else => return error.InvalidEscape,
                }
                self.pos += 1;
            } else {
                try buf.append(c);
                self.pos += 1;
            }
        }
        return error.UnterminatedString;
    }

    fn readNumber(self: *Tokenizer) []const u8 {
        const start = self.pos;
        if (self.pos < self.src.len and self.src[self.pos] == '-') self.pos += 1;
        while (self.pos < self.src.len and self.src[self.pos] >= '0' and self.src[self.pos] <= '9') {
            self.pos += 1;
        }
        if (self.pos < self.src.len and self.src[self.pos] == '.') {
            self.pos += 1;
            while (self.pos < self.src.len and self.src[self.pos] >= '0' and self.src[self.pos] <= '9') {
                self.pos += 1;
            }
        }
        if (self.pos < self.src.len and (self.src[self.pos] == 'e' or self.src[self.pos] == 'E')) {
            self.pos += 1;
            if (self.pos < self.src.len and (self.src[self.pos] == '+' or self.src[self.pos] == '-')) {
                self.pos += 1;
            }
            while (self.pos < self.src.len and self.src[self.pos] >= '0' and self.src[self.pos] <= '9') {
                self.pos += 1;
            }
        }
        return self.src[start..self.pos];
    }

    pub fn next(self: *Tokenizer) !Token {
        self.skipWhitespace();
        if (self.pos >= self.src.len) {
            return Token{ .typ = .eof, .value = "", .pos = self.pos };
        }
        const c = self.src[self.pos];
        const p = self.pos;
        switch (c) {
            '{' => { self.pos += 1; return Token{ .typ = .lbrace, .value = "{", .pos = p }; },
            '}' => { self.pos += 1; return Token{ .typ = .rbrace, .value = "}", .pos = p }; },
            '[' => { self.pos += 1; return Token{ .typ = .lbracket, .value = "[", .pos = p }; },
            ']' => { self.pos += 1; return Token{ .typ = .rbracket, .value = "]", .pos = p }; },
            ':' => { self.pos += 1; return Token{ .typ = .colon, .value = ":", .pos = p }; },
            ',' => { self.pos += 1; return Token{ .typ = .comma, .value = ",", .pos = p }; },
            '"' => {
                const s = try self.readString();
                return Token{ .typ = .string, .value = s, .pos = p };
            },
            't' => {
                if (self.pos + 4 <= self.src.len and std.mem.eql(u8, self.src[self.pos .. self.pos + 4], "true")) {
                    self.pos += 4;
                    return Token{ .typ = .true_lit, .value = "true", .pos = p };
                }
                return error.UnexpectedChar;
            },
            'f' => {
                if (self.pos + 5 <= self.src.len and std.mem.eql(u8, self.src[self.pos .. self.pos + 5], "false")) {
                    self.pos += 5;
                    return Token{ .typ = .false_lit, .value = "false", .pos = p };
                }
                return error.UnexpectedChar;
            },
            'n' => {
                if (self.pos + 4 <= self.src.len and std.mem.eql(u8, self.src[self.pos .. self.pos + 4], "null")) {
                    self.pos += 4;
                    return Token{ .typ = .null_lit, .value = "null", .pos = p };
                }
                return error.UnexpectedChar;
            },
            '-', '0'...'9' => {
                const num = self.readNumber();
                return Token{ .typ = .number, .value = num, .pos = p };
            },
            else => return error.UnexpectedChar,
        }
    }
};

pub const ValueType = enum {
    object,
    array,
    string,
    number,
    boolean,
    null_val,
};

pub const Value = union(ValueType) {
    object: std.StringArrayHashMap(Value),
    array: std.ArrayList(Value),
    string: []const u8,
    number: f64,
    boolean: bool,
    null_val: void,

    pub fn deinit(self: *Value, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .object => |*m| {
                var it = m.iterator();
                while (it.next()) |entry| {
                    allocator.free(entry.key_ptr.*);
                    var v = entry.value_ptr.*;
                    v.deinit(allocator);
                }
                m.deinit();
            },
            .array => |*a| {
                for (a.items) |*item| {
                    item.deinit(allocator);
                }
                a.deinit();
            },
            .string => |s| allocator.free(s),
            else => {},
        }
    }
};

pub const Parser = struct {
    tokenizer: Tokenizer,
    allocator: std.mem.Allocator,
    peeked: ?Token,

    pub fn init(allocator: std.mem.Allocator, src: []const u8) Parser {
        return .{
            .tokenizer = Tokenizer.init(allocator, src),
            .allocator = allocator,
            .peeked = null,
        };
    }

    fn peek(self: *Parser) !Token {
        if (self.peeked) |t| return t;
        const t = try self.tokenizer.next();
        self.peeked = t;
        return t;
    }

    fn consume(self: *Parser) !Token {
        if (self.peeked) |t| {
            self.peeked = null;
            return t;
        }
        return self.tokenizer.next();
    }

    fn expect(self: *Parser, typ: TokenType) !Token {
        const t = try self.consume();
        if (t.typ != typ) return error.UnexpectedToken;
        return t;
    }

    pub fn parse(self: *Parser) !Value {
        const val = try self.parseValue();
        const end = try self.peek();
        if (end.typ != .eof) return error.TrailingData;
        return val;
    }

    fn parseValue(self: *Parser) !Value {
        const t = try self.peek();
        return switch (t.typ) {
            .lbrace => self.parseObject(),
            .lbracket => self.parseArray(),
            .string => {
                _ = try self.consume();
                const copy = try self.allocator.dupe(u8, t.value);
                return Value{ .string = copy };
            },
            .number => {
                _ = try self.consume();
                const n = try std.fmt.parseFloat(f64, t.value);
                return Value{ .number = n };
            },
            .true_lit => { _ = try self.consume(); return Value{ .boolean = true }; },
            .false_lit => { _ = try self.consume(); return Value{ .boolean = false }; },
            .null_lit => { _ = try self.consume(); return Value{ .null_val = {} }; },
            else => error.UnexpectedToken,
        };
    }

    fn parseObject(self: *Parser) !Value {
        _ = try self.expect(.lbrace);
        var map = std.StringArrayHashMap(Value).init(self.allocator);
        errdefer {
            var it = map.iterator();
            while (it.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
                var v = entry.value_ptr.*;
                v.deinit(self.allocator);
            }
            map.deinit();
        }

        const first = try self.peek();
        if (first.typ == .rbrace) {
            _ = try self.consume();
            return Value{ .object = map };
        }

        while (true) {
            const key_tok = try self.expect(.string);
            const key = try self.allocator.dupe(u8, key_tok.value);
            errdefer self.allocator.free(key);
            _ = try self.expect(.colon);
            const val = try self.parseValue();
            try map.put(key, val);

            const sep = try self.peek();
            if (sep.typ == .rbrace) {
                _ = try self.consume();
                break;
            }
            _ = try self.expect(.comma);
        }
        return Value{ .object = map };
    }

    fn parseArray(self: *Parser) !Value {
        _ = try self.expect(.lbracket);
        var arr = std.ArrayList(Value).init(self.allocator);
        errdefer {
            for (arr.items) |*item| item.deinit(self.allocator);
            arr.deinit();
        }

        const first = try self.peek();
        if (first.typ == .rbracket) {
            _ = try self.consume();
            return Value{ .array = arr };
        }

        while (true) {
            const val = try self.parseValue();
            try arr.append(val);

            const sep = try self.peek();
            if (sep.typ == .rbracket) {
                _ = try self.consume();
                break;
            }
            _ = try self.expect(.comma);
        }
        return Value{ .array = arr };
    }
};
// null literal support
// error on unexpected eof
// number precision
// BOM (\xEF\xBB\xBF) at offset 0 is silently skipped before tokenization begins
// readNumber: leading zeros (e.g. 007) are accepted; callers validate if strict mode needed
// readString returns an allocator-owned slice; caller is responsible for freeing
// \uXXXX: surrogate pairs (0xD800-0xDFFF) are not combined; each half encoded as-is
// readNumber returns a slice into src (not a copy); valid as long as src is alive
// parseObject: errdefer iterates partial map and frees all keys and values on parse failure
// eof token: value is empty string "", pos is src.len; never call value on eof token
// peek: stores token in self.peeked (optional) so consume can return it without re-lexing
// parse(): TrailingData is returned when tokens remain after a complete value is parsed
// \u escape: only BMP codepoints (U+0000..U+FFFF) are handled; emoji require surrogate pairs
// true/false: consumed by advancing pos 4 or 5 bytes; no heap allocation needed
// skipWhitespace: handles both \r\n (CRLF) and \n (LF) so Windows-formatted JSON is accepted
// readString: escape sequences are decoded into an ArrayList(u8) then moved to owned slice
// peeked: uses ?Token (optional) rather than a sentinel token; avoids allocating a dummy eof
