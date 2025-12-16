pub const std = @import("std");
pub const main = @import("main.zig");

pub const KAKURI_NAME = "kakuri";
pub const KAKURI_VERSION = "0.0.1-dev";

// Re‑export modules so cmd binaries can `@import("root")` only.
pub const config = @import("config.zig");
pub const rpc = @import("rpc.zig");
pub const workload = @import("workload.zig");
pub const edera = @import("edera.zig");

// For now, simple shared entry helpers.
pub fn printBanner(writer: *std.Io.Writer) !void {
    try writer.print("{s} {s} - secure runtime orchestrator (Zig + Edera)\n", .{ KAKURI_NAME, KAKURI_VERSION });
}
