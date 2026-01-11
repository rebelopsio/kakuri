pub const std = @import("std");

// Re‑export modules so cmd binaries can `@import("kakuri")` only.
pub const config = @import("config.zig");
pub const rpc = @import("rpc.zig");
pub const workload = @import("workload.zig");
pub const edera = @import("edera.zig");
pub const agent = @import("agent.zig");
pub const control_plane = @import("control_plane.zig");

pub const json = @import("json.zig");
pub const tcp = @import("tcp.zig");
pub const http = @import("http.zig");

// Test discovery
test {
    @import("std").testing.refAllDecls(@This());
}
