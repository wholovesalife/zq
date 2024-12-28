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
        {
            self.pos += 1;
        }
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
            '"' => {
                self.pos += 1;
                const start = self.pos;
                while (self.pos < self.src.len and self.src[self.pos] != '"') self.pos += 1;
                const s = self.src[start..self.pos];
                self.pos += 1;
                return Token{ .typ = .string, .value = s, .pos = p };
            },
            '-', '0'...'9' => {
                const start = self.pos;
                while (self.pos < self.src.len and ((self.src[self.pos] >= '0' and self.src[self.pos] <= '9') or self.src[self.pos] == '-' or self.src[self.pos] == '.')) self.pos += 1;
                return Token{ .typ = .number, .value = self.src[start..self.pos], .pos = p };
            },
            't' => { self.pos += 4; return Token{ .typ = .true_lit, .value = "true", .pos = p }; },
            'f' => { self.pos += 5; return Token{ .typ = .false_lit, .value = "false", .pos = p }; },
            'n' => { self.pos += 4; return Token{ .typ = .null_lit, .value = "null", .pos = p }; },
            else => return error.UnexpectedChar,
        }
    }
};
