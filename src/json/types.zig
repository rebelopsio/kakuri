const std = @import("std");

/// Token type with positon tracker
pub const Token: type = union(enum) {
    brace_open: usize,
    brace_close: usize,
    bracket_open: usize,
    bracket_close: usize,
    colon: usize,
    comma: usize,
    string: struct {
        value: []const u8,
        position: usize,
    },
    number: struct {
        value: f64,
        position: usize,
    },
    true_literal: usize,
    false_literal: usize,
    null_literal: usize,
};
