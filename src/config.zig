const std = @import("std");

pub const KAKURI_NAME = "kakuri";
pub const KAKURI_VERSION = "0.0.1-dev";

// For now, simple shared entry helpers.
pub fn printBanner(writer: *std.Io.Writer) !void {
    try writer.print("{s} {s} - secure runtime orchestrator (Zig + Edera)\n", .{ KAKURI_NAME, KAKURI_VERSION });
}
