const std = @import("std");
const Allocator = std.mem.Allocator;
const test_allocator = std.testing.allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;
const ArenaAllocator = std.heap.ArenaAllocator;
const ArrayList = std.ArrayList;
const errors = @import("errors.zig");
const TokenizeError = errors.TokenizeError;
const parseFloat = std.fmt.parseFloat;
const eql = std.mem.eql;
pub const Token = @import("types.zig").Token;

const log = std.log.scoped(.json_tokenizer);

/// Tokenize JSON source text into a slice of tokens
/// Caller owns the returned memory and must free it (typically via ArenaAllocator)
pub fn tokenize(allocator: Allocator, source: []const u8) (TokenizeError || Allocator.Error)![]Token {
    var tokens = try ArrayList(Token).initCapacity(allocator, source.len);
    var idx: usize = 0;
    while (idx < source.len) {
        const char: u8 = source[idx];
        var token: Token = undefined;
        if (isWhitespace(char)) {
            idx += 1;
            continue;
        } else if (isDigit(char) or char == '-') {
            const start_pos = idx;
            const n: f64 = try tokenizeNumber(source, &idx);
            token = .{ .number = .{ .position = start_pos, .value = n } };
        } else if (char == 't') {
            if (matchKeyword(source, idx, "true")) {
                token = .{ .true_literal = idx };
                idx += 3;
            } else {
                log.warn("Unexpected character 't' at position {} (not 'true' keyword)", .{idx});
                return error.UnexpectedCharacter;
            }
        } else if (char == 'f') {
            if (matchKeyword(source, idx, "false")) {
                token = .{ .false_literal = idx };
                idx += 4;
            } else {
                log.warn("Unexpected character 'f' at position {} (not 'true' keyword)", .{idx});
                return error.UnexpectedCharacter;
            }
        } else if (char == 'n') {
            if (matchKeyword(source, idx, "null")) {
                token = .{ .null_literal = idx };
                idx += 3;
            } else {
                log.warn("Unexpected character 'n' at position {} (not 'true' keyword)", .{idx});
                return error.UnexpectedCharacter;
            }
        } else {
            switch (char) {
                '{' => token = .{ .brace_open = idx },
                '}' => token = .{ .brace_close = idx },
                '[' => token = .{ .bracket_open = idx },
                ']' => token = .{ .bracket_close = idx },
                ':' => token = .{ .colon = idx },
                ',' => token = .{ .comma = idx },
                '"' => {
                    const start_pos = idx;
                    const s = try tokenizeString(allocator, source, &idx);
                    token = .{ .string = .{ .position = start_pos, .value = s } };
                },
                else => {
                    idx += 1;
                    continue;
                },
            }
        }
        try tokens.append(allocator, token);
        idx += 1;
    }
    return try tokens.toOwnedSlice(allocator);
}

// Helper functions
/// Tokenize string
fn tokenizeString(alllocator: Allocator, source: []const u8, pos: *usize) ![]const u8 {
    pos.* += 1;
    const start: usize = pos.*;
    while (pos.* < source.len) {
        if (source[pos.*] == '"') {
            const end = pos.*;
            const str = source[start..end];
            return alllocator.dupe(u8, str);
        }
        pos.* += 1;
    }
    log.warn("Unterminated string starting at position {}", .{start - 1});
    return error.UnterminatedString;
}

fn tokenizeNumber(source: []const u8, pos: *usize) !f64 {
    const start: usize = pos.*;

    if (pos.* < source.len and source[pos.*] == '-') {
        pos.* += 1;
    }

    while (pos.* < source.len) {
        const c = source[pos.*];

        if (isDigit(c) or c == '.' or c == 'e' or c == 'E' or c == '+' or c == '-') {
            pos.* += 1;
        } else {
            break;
        }
    }

    const number_str: []const u8 = source[start..pos.*];
    pos.* -= 1;

    return parseFloat(f64, number_str) catch {
        log.warn("Invalid number '{s}' starting at position {}", .{ number_str, start });
        return error.InvalidNumber;
    };
}

/// Check if a character is JSON whitespace
fn isWhitespace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r';
}

/// Check if character is a digit
fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

/// Check for delimiter
fn isDelimiter(c: u8) bool {
    return isWhitespace(c) or c == ',' or c == '}' or c == ']';
}

// Check if source[pos..] starts with the given keyword
// A valid keyword must be followed by a delimiter (whitespace, comma, brace, etc.)
fn matchKeyword(source: []const u8, pos: usize, keyword: []const u8) bool {
    if (source[pos..].len < keyword.len) {
        return false;
    }

    const slice = source[pos .. pos + keyword.len];
    if (!eql(u8, slice, keyword)) {
        return false;
    }

    const after_pos = pos + keyword.len;
    if (after_pos >= source.len) {
        return true;
    }

    return isDelimiter(source[after_pos]);
}

test "tokenize empty object" {
    const allocator = test_allocator;

    var arena = ArenaAllocator.init(allocator);
    defer arena.deinit();

    const tokens = try tokenize(arena.allocator(), "{}");

    try expectEqual(@as(usize, 2), tokens.len);
    try expect(tokens[0] == .brace_open);
    try expect(tokens[1] == .brace_close);
}

test "tokenize simple object" {
    const allocator = test_allocator;

    var arena = ArenaAllocator.init(allocator);
    defer arena.deinit();

    const tokens = try tokenize(arena.allocator(),
        \\{"id": "wl-123"}
    );

    try expectEqual(@as(usize, 5), tokens.len);
    try expect(tokens[0] == .brace_open);
    try expect(tokens[1] == .string);
    try expectEqualStrings("id", tokens[1].string.value);
    try expect(tokens[2] == .colon);
    try expect(tokens[3] == .string);
    try expectEqualStrings("wl-123", tokens[3].string.value);
    try expect(tokens[4] == .brace_close);
}

test "tokenize object with number" {
    const allocator = test_allocator;

    var arena = ArenaAllocator.init(allocator);
    defer arena.deinit();

    const tokens = try tokenize(arena.allocator(),
        \\{"memory_mb": 512}
    );

    try expectEqual(@as(usize, 5), tokens.len);
    try expect(tokens[3] == .number);
    try expectEqual(@as(f64, 512.0), tokens[3].number.value);
}

test "tokenize invalid number" {
    const allocator = test_allocator;

    var arena = ArenaAllocator.init(allocator);
    defer arena.deinit();

    const json = "{\"count\": 12.34.56}"; // invalid number

    const result = tokenize(arena.allocator(), json);
    try std.testing.expectError(error.InvalidNumber, result);
}

test "tokenize true literal" {
    const allocator = test_allocator;
    var arena = ArenaAllocator.init(allocator);
    defer arena.deinit();

    const tokens = try tokenize(arena.allocator(), "true");

    try expectEqual(@as(usize, 1), tokens.len);
    try expect(tokens[0] == .true_literal);
}

test "tokenize false literal" {
    const allocator = test_allocator;
    var arena = ArenaAllocator.init(allocator);
    defer arena.deinit();

    const tokens = try tokenize(arena.allocator(), "false");

    try expectEqual(@as(usize, 1), tokens.len);
    try expect(tokens[0] == .false_literal);
}

test "tokenize null literal" {
    const allocator = test_allocator;
    var arena = ArenaAllocator.init(allocator);
    defer arena.deinit();

    const tokens = try tokenize(arena.allocator(), "null");

    try expectEqual(@as(usize, 1), tokens.len);
    try expect(tokens[0] == .null_literal);
}

test "tokenize object with bool" {
    const allocator = test_allocator;
    var arena = ArenaAllocator.init(allocator);
    defer arena.deinit();

    const tokens = try tokenize(arena.allocator(),
        \\{"enabled": true, "disabled": false}
    );

    try expectEqual(@as(usize, 9), tokens.len);
    try expect(tokens[0] == .brace_open);
    try expect(tokens[1] == .string);
    try expect(tokens[3] == .true_literal);
    try expect(tokens[5] == .string);
    try expect(tokens[7] == .false_literal);
}
