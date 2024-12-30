const std = @import("std");

pub const TokenType = enum {
    lbrace, rbrace, lbracket, rbracket,
    colon, comma, string, number,
    true_lit, false_lit, null_lit, eof,
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
        { self.pos += 1; }
    }

    fn readString(self: *Tokenizer) []const u8 {
        self.pos += 1;
        const start = self.pos;
        while (self.pos < self.src.len and self.src[self.pos] != '"') self.pos += 1;
        const s = self.src[start..self.pos];
        self.pos += 1;
        return s;
    }

    fn readNumber(self: *Tokenizer) []const u8 {
        const start = self.pos;
        if (self.pos < self.src.len and self.src[self.pos] == '-') self.pos += 1;
        while (self.pos < self.src.len and self.src[self.pos] >= '0' and self.src[self.pos] <= '9') self.pos += 1;
        if (self.pos < self.src.len and self.src[self.pos] == '.') {
            self.pos += 1;
            while (self.pos < self.src.len and self.src[self.pos] >= '0' and self.src[self.pos] <= '9') self.pos += 1;
        }
        return self.src[start..self.pos];
    }

    pub fn next(self: *Tokenizer) !Token {
        self.skipWhitespace();
        if (self.pos >= self.src.len) return Token{ .typ = .eof, .value = "", .pos = self.pos };
        const c = self.src[self.pos];
        const p = self.pos;
        switch (c) {
            '{' => { self.pos += 1; return Token{ .typ = .lbrace, .value = "{", .pos = p }; },
            '}' => { self.pos += 1; return Token{ .typ = .rbrace, .value = "}", .pos = p }; },
            '[' => { self.pos += 1; return Token{ .typ = .lbracket, .value = "[", .pos = p }; },
            ']' => { self.pos += 1; return Token{ .typ = .rbracket, .value = "]", .pos = p }; },
            ':' => { self.pos += 1; return Token{ .typ = .colon, .value = ":", .pos = p }; },
            ',' => { self.pos += 1; return Token{ .typ = .comma, .value = ",", .pos = p }; },
            '"' => return Token{ .typ = .string, .value = self.readString(), .pos = p },
            '-', '0'...'9' => return Token{ .typ = .number, .value = self.readNumber(), .pos = p },
            't' => { self.pos += 4; return Token{ .typ = .true_lit, .value = "true", .pos = p }; },
            'f' => { self.pos += 5; return Token{ .typ = .false_lit, .value = "false", .pos = p }; },
            'n' => { self.pos += 4; return Token{ .typ = .null_lit, .value = "null", .pos = p }; },
            else => return error.UnexpectedChar,
        }
    }
};

pub const ValueType = enum { object, array, string, number, boolean, null_val };

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
                while (it.next()) |e| { var v = e.value_ptr.*; v.deinit(allocator); }
                m.deinit();
            },
            .array => |*a| { for (a.items) |*i| i.deinit(allocator); a.deinit(); },
            else => {},
        }
    }
};

pub const Parser = struct {
    tokenizer: Tokenizer,
    allocator: std.mem.Allocator,
    peeked: ?Token,

    pub fn init(allocator: std.mem.Allocator, src: []const u8) Parser {
        return .{ .tokenizer = Tokenizer.init(allocator, src), .allocator = allocator, .peeked = null };
    }

    fn peek(self: *Parser) !Token {
        if (self.peeked) |t| return t;
        const t = try self.tokenizer.next();
        self.peeked = t;
        return t;
    }

    fn consume(self: *Parser) !Token {
        if (self.peeked) |t| { self.peeked = null; return t; }
        return self.tokenizer.next();
    }

    fn expect(self: *Parser, typ: TokenType) !Token {
        const t = try self.consume();
        if (t.typ != typ) return error.UnexpectedToken;
        return t;
    }

    pub fn parse(self: *Parser) !Value {
        const val = try self.parseValue();
        return val;
    }

    fn parseValue(self: *Parser) !Value {
        const t = try self.peek();
        return switch (t.typ) {
            .lbrace => self.parseObject(),
            .lbracket => self.parseArray(),
            .string => { _ = try self.consume(); return Value{ .string = t.value }; },
            .number => { _ = try self.consume(); return Value{ .number = try std.fmt.parseFloat(f64, t.value) }; },
            .true_lit => { _ = try self.consume(); return Value{ .boolean = true }; },
            .false_lit => { _ = try self.consume(); return Value{ .boolean = false }; },
            .null_lit => { _ = try self.consume(); return Value{ .null_val = {} }; },
            else => error.UnexpectedToken,
        };
    }

    fn parseObject(self: *Parser) !Value {
        _ = try self.expect(.lbrace);
        var map = std.StringArrayHashMap(Value).init(self.allocator);
        const first = try self.peek();
        if (first.typ == .rbrace) { _ = try self.consume(); return Value{ .object = map }; }
        while (true) {
            const key_tok = try self.expect(.string);
            _ = try self.expect(.colon);
            const val = try self.parseValue();
            try map.put(key_tok.value, val);
            const sep = try self.peek();
            if (sep.typ == .rbrace) { _ = try self.consume(); break; }
            _ = try self.expect(.comma);
        }
        return Value{ .object = map };
    }

    fn parseArray(self: *Parser) !Value {
        _ = try self.expect(.lbracket);
        var arr = std.ArrayList(Value).init(self.allocator);
        const first = try self.peek();
        if (first.typ == .rbracket) { _ = try self.consume(); return Value{ .array = arr }; }
        while (true) {
            const val = try self.parseValue();
            try arr.append(val);
            const sep = try self.peek();
            if (sep.typ == .rbracket) { _ = try self.consume(); break; }
            _ = try self.expect(.comma);
        }
        return Value{ .array = arr };
    }
};
