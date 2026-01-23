const std = @import("std");

// tcp sub-module
pub const buffered_reader = @import("tcp/buffered_reader.zig");
pub const client = @import("tcp/client.zig");
pub const server = @import("tcp/server.zig");

// Test discovery
test {
    @import("std").testing.refAllDecls(@This());
}
