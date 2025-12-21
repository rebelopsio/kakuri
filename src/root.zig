pub const std = @import("std");
pub const main = @import("main.zig");

pub const KAKURI_NAME = "kakuri";
pub const KAKURI_VERSION = "0.0.1-dev";

// Re‑export modules so cmd binaries can `@import("root")` only.
pub const config = @import("config.zig");
pub const rpc = @import("rpc.zig");
pub const workload = @import("workload.zig");
pub const edera = @import("edera.zig");

// http sub-module
pub const http = struct {
    pub const headers = @import("http/headers.zig");
    pub const request = @import("http/request.zig");
    pub const response = @import("http/response.zig");
    pub const router = @import("http/router.zig");
    pub const server = @import("http/server.zig");
};

// json sub-module
pub const json = struct {
    pub const parser = @import("json/parser.zig");
    pub const serializer = @import("json/serializer.zig");
    pub const types = @import("json/types.zig");
};

// tcp sub-module
pub const tcp = struct {
    pub const buffered_reader = @import("tcp/buffered_reader.zig");
    pub const client = @import("tcp/client.zig");
    pub const server = @import("tcp/server.zig");
};

// For now, simple shared entry helpers.
pub fn printBanner(writer: *std.Io.Writer) !void {
    try writer.print("{s} {s} - secure runtime orchestrator (Zig + Edera)\n", .{ KAKURI_NAME, KAKURI_VERSION });
}
