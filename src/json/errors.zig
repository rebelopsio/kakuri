const std = @import("std");
const Allocator = std.mem.Allocator;

/// Errors that can occur during tokenization
pub const TokenizeError = error{
    UnterminatedString,
    InvalidNumber,
    UnexpectedCharacter,
};

/// Errors that can occur during parsing
pub const ParseError = error{
    UnexpectedToken,
    UnexpectedEndOfTokens,
    UnknownField,
    ExpectedCommaOrBrace,
    OutOfMemory,
};

pub const SerializeError = error{
    // TODO: Implement
    };

/// Context information for tokenization errors
pub const TokenizeContext = struct {
    position: usize,
    char: ?u8,
    message: []const u8,
};

/// Context information for parsing errors
pub const ParseContext = struct {
    position: usize,
    token_position: ?usize,
    expected: ?[]const u8,
    message: []const u8,
};

pub const SerializeContext = struct {
    // TODO: Implement
};

/// Result type for tokenization
pub fn TokenizeResult(comptime T: type) type {
    return union(enum) {
        ok: T,
        err: struct {
            kind: TokenizeError,
            context: TokenizeContext,
        },
    };
}

/// Result type for parsing
pub fn ParseResult(comptime T: type) type {
    return union(enum) { ok: T, err: struct {
        kind: ParseError,
        context: ParseContext,
    } };
}

pub fn SerializeResult(comptime T: type) type {
    return union(enum) {
        ok: T,
        err: struct {
            kind: SerializeError,
            context: SerializeContext,
        },
    };
}
