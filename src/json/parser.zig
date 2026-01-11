const std = @import("std");
const Allocator = std.mem.Allocator;
const Tag = std.meta.Tag;
const activeTag = std.meta.activeTag;
const tokenizer = @import("tokenizer.zig");
const Token = tokenizer.Token;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;
const errors = @import("errors.zig");
const ParseError = errors.ParseError;
const ArenaAllocator = std.heap.ArenaAllocator;
const ArrayList = std.ArrayList;
const eql = std.mem.eql;
const test_allocator = std.testing.allocator;
pub const Workload = @import("../workload.zig").Workload;
pub const Resources = @import("../workload.zig").Resources;

const log = std.log.scoped(.json_parser);

/// Parse tokens into Workload struct
/// The returned Workload borrows stirng data from the tokens
pub fn parseWorkload(allocator: Allocator, tokens: []const Token) ParseError!Workload {
    var pos: usize = 0;
    var workload: Workload = undefined;

    try expectToken(tokens, &pos, .brace_open);

    while (pos < tokens.len) {
        if (activeTag(tokens[pos]) == .brace_close) {
            break;
        }
        // Parse one field: name : value
        const field_name = try expectString(tokens, &pos);
        try expectToken(tokens, &pos, .colon);

        // Branch on field name to know how to parse the value
        if (eql(u8, field_name, "id")) {
            workload.id = try expectString(tokens, &pos);
        } else if (eql(u8, field_name, "image")) {
            workload.image = try expectString(tokens, &pos);
        } else if (eql(u8, field_name, "runtime_class")) {
            workload.runtime_class = try expectString(tokens, &pos);
        } else if (eql(u8, field_name, "resources")) {
            workload.resources = try parseResources(tokens, &pos);
        } else if (eql(u8, field_name, "enabled")) {
            workload.enabled = try expectBool(tokens, &pos);
        } else if (eql(u8, field_name, "description")) {
            if (activeTag(tokens[pos]) == .null_literal) {
                workload.description = null;
                pos += 1;
            } else {
                workload.description = try expectString(tokens, &pos);
            }
        } else if (eql(u8, field_name, "ports")) {
            workload.ports = try expectNumberArray(allocator, tokens, &pos);
        } else {
            return error.UnknownField;
        }

        // After value, expect either comma (more fields) or closing brace (done)
        if (pos < tokens.len and activeTag(tokens[pos]) == .comma) {
            pos += 1;
        } else if (pos < tokens.len and activeTag(tokens[pos]) == .brace_close) {
            break;
        } else {
            return error.ExpectedCommaOrBrace;
        }
    }
    try expectToken(tokens, &pos, .brace_close);
    return workload;
}

fn parseResources(tokens: []const Token, pos: *usize) ParseError!Resources {
    var resources: Resources = undefined;

    try expectToken(tokens, pos, .brace_open);

    while (pos.* < tokens.len) {
        if (activeTag(tokens[pos.*]) == .brace_close) {
            break;
        }
        // Parse one field: name : value
        const field_name = try expectString(tokens, pos);
        try expectToken(tokens, pos, .colon);

        // Branch on field name to know how to parse the value
        if (eql(u8, field_name, "memory_mb")) {
            const num = try expectNumber(tokens, pos);
            resources.memory_mb = @intFromFloat(num);
        } else if (eql(u8, field_name, "cpu_millicores")) {
            const num = try expectNumber(tokens, pos);
            resources.cpu_millicores = @intFromFloat(num);
        } else {
            return error.UnknownField;
        }

        // After value, expect either comma (more fields) or closing brace (done)
        if (pos.* < tokens.len and activeTag(tokens[pos.*]) == .comma) {
            pos.* += 1;
        } else if (pos.* < tokens.len and activeTag(tokens[pos.*]) == .brace_close) {
            break;
        } else {
            return error.ExpectedCommaOrBrace;
        }
    }
    try expectToken(tokens, pos, .brace_close);
    return resources;
}

fn parse(comptime T: type, allocator: Allocator, tokens: []const Token, pos: *usize) !T {
    var result: T = undefined;

    try expectToken(tokens, pos, .brace_open);

    while (pos.* < tokens.len and activeTag(tokens[pos.*]) != .brace_close) {
        const field_name = try expectString(tokens, pos);
        try expectToken(tokens, pos, .colon);

        // Magic: iterate over T's fields at compile time
        const fields = @typeInfo(T).@"struct".fields;
        var field_found = false;

        inline for (fields) |field| {
            if (eql(u8, field_name, field.name)) {
                field_found = true;
                const field_type_info = @typeInfo(field.type);

                if (field.type == []const u8) {
                    @field(result, field.name) = try expectString(tokens, pos);
                } else if (field_type_info == .pointer and field_type_info.pointer.size == .slice) {
                    const child = field_type_info.pointer.child;

                    try expectToken(tokens, pos, .bracket_open);

                    var items = try ArrayList(child).initCapacity(allocator, 10);

                    while (pos.* < tokens.len and activeTag(tokens[pos.*]) != .bracket_close) {
                        if (@typeInfo(child) == .int) {
                            try items.append(allocator, @intFromFloat(try expectNumber(tokens, pos)));
                        } else if (@typeInfo(child) == .float) {
                            try items.append(allocator, try expectNumber(tokens, pos));
                        } else if (child == []const u8) {
                            try items.append(allocator, try expectString(tokens, pos));
                        }
                        if (activeTag(tokens[pos.*]) == .comma) {
                            pos.* += 1;
                        }
                    }

                    try expectToken(tokens, pos, .bracket_close);
                    @field(result, field.name) = try items.toOwnedSlice(allocator);
                } else if (field_type_info == .optional) {
                    if (activeTag(tokens[pos.*]) == .null_literal) {
                        @field(result, field.name) = null;
                        pos.* += 1;
                    } else {
                        const child = field_type_info.optional.child;
                        if (child == []const u8) {
                            @field(result, field.name) = try expectString(tokens, pos);
                        } else if (@typeInfo(child) == .int) {
                            @field(result, field.name) = @intFromFloat(try expectNumber(tokens, pos));
                        } else if (@typeInfo(child) == .float) {
                            @field(result, field.name) = try expectNumber(tokens, pos);
                        } else if (child == bool) {
                            @field(result, field.name) = try expectBool(tokens, pos);
                        } else if (@typeInfo(field.type) == .@"struct") {
                            // Recursively parse
                            @field(result, field.name) = try parse(field.type, allocator, tokens, pos);
                        }
                    }
                } else if (field_type_info == .int) {
                    @field(result, field.name) = @intFromFloat(try expectNumber(tokens, pos));
                } else if (field_type_info == .float) {
                    @field(result, field.name) = try expectNumber(tokens, pos);
                } else if (field.type == bool) {
                    @field(result, field.name) = try expectBool(tokens, pos);
                } else if (@typeInfo(field.type) == .@"struct") {
                    // Recursively parse
                    @field(result, field.name) = try parse(field.type, allocator, tokens, pos);
                }
            }
        }

        if (!field_found) {
            log.warn("Unknown field '{s}' at position {}", .{ field_name, pos.* });
            return error.UnknownField;
        }

        // After value, expect either comma (more fields) or closing brace (done)
        if (pos.* < tokens.len and activeTag(tokens[pos.*]) == .comma) {
            pos.* += 1;
        } else if (pos.* < tokens.len and activeTag(tokens[pos.*]) == .brace_close) {
            break;
        } else {
            return error.ExpectedCommaOrBrace;
        }
    }
    try expectToken(tokens, pos, .brace_close);
    return result;
}

// Helper functions
/// Expect a specific token type at the current position, then advance
fn expectToken(tokens: []const Token, pos: *usize, expected: Tag(Token)) !void {
    if (pos.* >= tokens.len) {
        log.warn("Unexpected end of tokens at position {}, expected {s}", .{ pos.*, @tagName(expected) });
        return error.UnexpectedEndOfTokens;
    }
    if (activeTag(tokens[pos.*]) != expected) {
        log.warn("Unexpected token at position {}: expected {s}, found {s}", .{ pos.*, @tagName(expected), @tagName(activeTag(tokens[pos.*])) });
        return error.UnexpectedToken;
    }
    pos.* += 1;
}

/// Expect a string token and return its value
fn expectString(tokens: []const Token, pos: *usize) ![]const u8 {
    if (pos.* >= tokens.len) {
        log.warn("Unexpected end of tokens at position {}, expected string", .{pos.*});
        return error.UnexpectedEndOfTokens;
    }
    if (activeTag(tokens[pos.*]) != .string) {
        log.warn("Expected string at position {}, found {s}", .{
            pos.*,
            @tagName(activeTag(tokens[pos.*])),
        });
        return error.UnexpectedToken;
    }
    const value = tokens[pos.*].string.value;
    pos.* += 1;
    return value;
}

/// Expect a number token and retun its value
fn expectNumber(tokens: []const Token, pos: *usize) !f64 {
    if (pos.* >= tokens.len) {
        log.warn("Unexpected end of tokens at position {}, expected number", .{pos.*});
        return error.UnexpectedEndOfTokens;
    }
    if (activeTag(tokens[pos.*]) != .number) {
        log.warn("Expected number at position {}, found {s}", .{
            pos.*,
            @tagName(activeTag(tokens[pos.*])),
        });
        return error.UnexpectedToken;
    }
    const value = tokens[pos.*].number.value;
    pos.* += 1;
    return value;
}

/// Expect a boolean token and return it's value
fn expectBool(tokens: []const Token, pos: *usize) ParseError!bool {
    if (pos.* >= tokens.len) {
        log.warn("Unexpected end of tokens at position {}, expected boolean", .{pos.*});
        return error.UnexpectedEndOfTokens;
    }

    const tag = activeTag(tokens[pos.*]);
    const result = switch (tag) {
        .true_literal => true,
        .false_literal => false,
        else => {
            log.warn("Expected boolean at position {}, found {s}", .{
                pos.*,
                @tagName(tag),
            });
            return error.UnexpectedToken;
        },
    };

    pos.* += 1;
    return result;
}

fn expectNumberArray(allocator: Allocator, tokens: []const Token, pos: *usize) (ParseError || Allocator.Error)![]u64 {
    if (pos.* >= tokens.len) {
        log.warn("Unexpected end of tokens at position {}, expected number array", .{pos.*});
        return error.UnexpectedEndOfTokens;
    }

    var results = try ArrayList(u64).initCapacity(allocator, 10);

    while (activeTag(tokens[pos.*]) != .bracket_close and pos.* < tokens.len) {
        if (activeTag(tokens[pos.*]) == .number) {
            try results.append(allocator, @intFromFloat(tokens[pos.*].number.value));
            pos.* += 1;
        } else if (activeTag(tokens[pos.*]) == .bracket_open or activeTag(tokens[pos.*]) == .comma) {
            pos.* += 1;
            continue;
        } else {
            log.warn("Expected number array token at position {}, found {s}", .{
                pos.*,
                @tagName(activeTag(tokens[pos.*])),
            });
            return error.UnexpectedToken;
        }
    }

    if (pos.* >= tokens.len) {
        return error.UnexpectedEndOfTokens;
    }

    pos.* += 1;
    return try results.toOwnedSlice(allocator);
}

// Expect either string or null, return optional string
// fn expectOptionalString(tokens: []const Token, pos: *usize) ParseError!?[]const u8 {
//     // TODO: Implement
// }

// Tests
test "parse workload" {
    const allocator = std.testing.allocator;
    const tokenize = @import("tokenizer.zig").tokenize;

    var arena = ArenaAllocator.init(allocator);
    defer arena.deinit();

    const json =
        \\{"id": "wl-123", "image": "nginx:latest", "runtime_class": "edera-zone", "resources": {"memory_mb": 512, "cpu_millicores": 500}}
    ;

    const tokens = try tokenize(arena.allocator(), json);
    var pos: usize = 0;
    const workload = try parse(Workload, allocator, tokens, &pos);

    try expectEqualStrings("wl-123", workload.id);
    try expectEqualStrings("nginx:latest", workload.image);
    try expectEqualStrings("edera-zone", workload.runtime_class);
    try expectEqual(@as(u64, 512), workload.resources.memory_mb);
    try expectEqual(@as(u64, 500), workload.resources.cpu_millicores);
}

test "parse unexpected token" {
    const allocator = test_allocator;
    var arena = ArenaAllocator.init(allocator);
    defer arena.deinit();

    const tokens = &[_]Token{
        .{ .brace_open = 0 },
        .{ .number = .{ .value = 42, .position = 1 } },
    };

    const result = parseWorkload(allocator, tokens);
    try std.testing.expectError(error.UnexpectedToken, result);
}

test "parse workload with bool" {
    const allocator = std.testing.allocator;
    const tokenize = @import("tokenizer.zig").tokenize;

    var arena = ArenaAllocator.init(allocator);
    defer arena.deinit();

    const json =
        \\{"id": "wl-123", "image": "nginx:latest", "runtime_class": "edera-zone", "resources": {"memory_mb": 512, "cpu_millicores": 500}, "enabled": true}
    ;

    const tokens = try tokenize(arena.allocator(), json);
    const workload = try parseWorkload(allocator, tokens);

    try expectEqual(true, workload.enabled);
}

test "parse workload description with null" {
    const allocator = std.testing.allocator;
    const tokenize = @import("tokenizer.zig").tokenize;

    var arena = ArenaAllocator.init(allocator);
    defer arena.deinit();

    const json =
        \\{"id": "wl-123", "image": "nginx:latest", "runtime_class": "edera-zone", "resources": {"memory_mb": 512, "cpu_millicores": 500}, "enabled": true, "description": null}
    ;

    const tokens = try tokenize(arena.allocator(), json);
    const workload = try parseWorkload(allocator, tokens);

    try expectEqual(null, workload.description);
}

test "test workload description with optional string" {
    const allocator = std.testing.allocator;
    const tokenize = @import("tokenizer.zig").tokenize;

    var arena = ArenaAllocator.init(allocator);
    defer arena.deinit();

    const json =
        \\{"id": "wl-123", "image": "nginx:latest", "runtime_class": "edera-zone", "resources": {"memory_mb": 512, "cpu_millicores": 500}, "enabled": true, "description": "production webserver"}
    ;

    const tokens = try tokenize(arena.allocator(), json);
    const workload = try parseWorkload(allocator, tokens);

    try expectEqualStrings("production webserver", workload.description.?);
}

test "parse number array" {
    const allocator = std.testing.allocator;
    const tokenize = @import("tokenizer.zig").tokenize;

    var arena = ArenaAllocator.init(allocator);
    defer arena.deinit();

    const json =
        \\{"id": "wl-123", "image": "nginx:latest", "runtime_class": "edera-zone", "resources": {"memory_mb": 512, "cpu_millicores": 500}, "enabled": true, "description": "production webserver", "ports": [ 9091, 3000, 8080]}
    ;

    const tokens = try tokenize(arena.allocator(), json);
    const workload = try parseWorkload(arena.allocator(), tokens);

    const test_array = [_]u64{ 9091, 3000, 8080 };

    try expectEqualSlices(u64, &test_array, workload.ports);
}

test "generic parse" {
    const allocator = test_allocator;
    const tokenize = @import("tokenizer.zig").tokenize;

    var arena = ArenaAllocator.init(allocator);
    defer arena.deinit();

    const SimpleStruct = struct {
        name: []const u8,
        count: u64,
        active: bool,
    };

    const json =
        \\{"name": "test", "count": 42, "active": true}
    ;

    const tokens = try tokenize(arena.allocator(), json);
    var pos: usize = 0;
    const result = try parse(SimpleStruct, allocator, tokens, &pos);

    try expectEqualStrings("test", result.name);
    try expectEqual(@as(u64, 42), result.count);
    try expectEqual(true, result.active);
}

test "generic parse with optional" {
    const allocator = std.testing.allocator;
    const tokenize = @import("tokenizer.zig").tokenize;

    var arena = ArenaAllocator.init(allocator);
    defer arena.deinit();

    const TestStruct = struct {
        name: []const u8,
        description: ?[]const u8,
    };

    // Test with null
    const json_null =
        \\{"name": "test", "description": null}
    ;
    const tokens_null = try tokenize(arena.allocator(), json_null);
    var pos: usize = 0;
    const result_null = try parse(TestStruct, allocator, tokens_null, &pos);

    try expectEqualStrings("test", result_null.name);
    try expectEqual(@as(?[]const u8, null), result_null.description);

    // Test with value
    const json_value =
        \\{"name": "test", "description": "hello world"}
    ;
    const tokens_value = try tokenize(arena.allocator(), json_value);
    pos = 0;
    const result_value = try parse(TestStruct, allocator, tokens_value, &pos);

    try expectEqualStrings("test", result_value.name);
    try expectEqualStrings("hello world", result_value.description.?);
}

test "generic parse with array" {
    const allocator = std.testing.allocator;
    const tokenize = @import("tokenizer.zig").tokenize;

    var arena = ArenaAllocator.init(allocator);
    defer arena.deinit();

    const TestStruct = struct {
        name: []const u8,
        ports: []u64,
    };

    const json =
        \\{"name": "server", "ports": [8080, 443, 9000]}
    ;

    const tokens = try tokenize(arena.allocator(), json);
    var pos: usize = 0;
    const result = try parse(TestStruct, arena.allocator(), tokens, &pos);

    try expectEqualStrings("server", result.name);
    try expectEqual(@as(usize, 3), result.ports.len);
    try expectEqual(@as(u64, 8080), result.ports[0]);
    try expectEqual(@as(u64, 443), result.ports[1]);
    try expectEqual(@as(u64, 9000), result.ports[2]);
}

test "generic parse with various number types" {
    const allocator = std.testing.allocator;
    const tokenize = @import("tokenizer.zig").tokenize;

    var arena = ArenaAllocator.init(allocator);
    defer arena.deinit();

    const TestStruct = struct {
        count: u32,
        offset: i64,
        ratio: f64,
    };

    const json =
        \\{"count": 42, "offset": -100, "ratio": 3.14}
    ;

    const tokens = try tokenize(arena.allocator(), json);
    var pos: usize = 0;
    const result = try parse(TestStruct, arena.allocator(), tokens, &pos);

    try expectEqual(@as(u32, 42), result.count);
    try expectEqual(@as(i64, -100), result.offset);
    try expectEqual(@as(f64, 3.14), result.ratio);
}
