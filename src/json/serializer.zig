const std = @import("std");
const Workload = @import("../workload.zig").Workload;
const ArenaAllocator = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const log = std.log.scoped(.json_serializer);

const workload = Workload{
    .id = "wl-123",
    .image = "nginx:latest",
    .runtime_class = "edera-zone",
    .resources = .{
        .memory_mb = 512,
        .cpu_millicores = 500,
    },
};

fn stringify(comptime T: type, allocator: Allocator, value: T) ![]u8 {
    var buffer = try ArrayList(u8).initCapacity(allocator, 256);
    try stringifyInto(T, allocator, &buffer, value);
    return buffer.toOwnedSlice(allocator);
}

fn stringifyInto(comptime T: type, allocator: Allocator, buffer: *ArrayList(u8), value: T) !void {
    try buffer.append(allocator, '{');

    const fields = @typeInfo(T).@"struct".fields;
    inline for (fields, 0..) |field, i| {
        // Write field name
        try buffer.append(allocator, '"');
        try buffer.appendSlice(allocator, field.name);
        try buffer.append(allocator, '"');
        try buffer.append(allocator, ':');

        // Write field value based on type
        const field_value = @field(value, field.name);
        try writeValue(@TypeOf(field_value), allocator, buffer, field_value);

        // Add comma if not the last field
        if (i < fields.len - 1) {
            try buffer.append(allocator, ',');
        }
    }

    try buffer.append(allocator, '}');
}

/// Helper functions
fn writeValue(comptime T: type, allocator: Allocator, buffer: *ArrayList(u8), value: T) !void {
    const type_info = @typeInfo(T);

    if (T == []const u8) {
        // String: add quotes
        try buffer.append(allocator, '"');
        try buffer.appendSlice(allocator, value);
        try buffer.append(allocator, '"');
    } else if (type_info == .int) {
        var num_buf: [32]u8 = undefined;
        const num_str = std.fmt.bufPrint(&num_buf, "{}", .{value}) catch unreachable;
        try buffer.appendSlice(allocator, num_str);
    } else if (type_info == .float) {
        var num_buf: [64]u8 = undefined;
        const num_str = std.fmt.bufPrint(&num_buf, "{d}", .{value}) catch unreachable;
        try buffer.appendSlice(allocator, num_str);
    } else if (T == bool) {
        // Boolean
        if (value) {
            try buffer.appendSlice(allocator, "true");
        } else {
            try buffer.appendSlice(allocator, "false");
        }
    } else if (type_info == .optional) {
        // Optional
        if (value) |v| {
            try writeValue(@TypeOf(v), allocator, buffer, v);
        } else {
            try buffer.appendSlice(allocator, "null");
        }
    } else if (type_info == .@"struct") {
        // Struct
        try stringifyInto(T, allocator, buffer, value);
    } else if (type_info == .pointer and type_info.pointer.size == .slice) {
        // Array
        try buffer.append(allocator, '[');
        for (value, 0..) |elem, i| {
            try writeValue(@TypeOf(elem), allocator, buffer, elem);
            if (i < value.len - 1) {
                try buffer.append(allocator, ',');
            }
        }
        try buffer.append(allocator, ']');
    }
}

// Tests
test "stringify simple struct" {
    const allocator = std.testing.allocator;

    var arena = ArenaAllocator.init(allocator);
    defer arena.deinit();

    const Simple = struct {
        name: []const u8,
        count: u64,
    };

    const value = Simple{
        .name = "test",
        .count = 42,
    };

    const json = try stringify(Simple, arena.allocator(), value);

    try std.testing.expectEqualStrings(
        \\{"name":"test","count":42}
    , json);
}

test "stringify complex struct" {
    const allocator = std.testing.allocator;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const Inner = struct {
        value: u64,
    };

    const Complex = struct {
        name: []const u8,
        count: i32,
        ratio: f64,
        active: bool,
        description: ?[]const u8,
        inner: Inner,
        ports: []const u64,
    };

    const value = Complex{
        .name = "test",
        .count = -5,
        .ratio = 3.14,
        .active = true,
        .description = null,
        .inner = .{ .value = 42 },
        .ports = &[_]u64{ 8080, 443 },
    };

    const json = try stringify(Complex, arena.allocator(), value);

    // Print it to see what you get!
    std.debug.print("\n{s}\n", .{json});
}
