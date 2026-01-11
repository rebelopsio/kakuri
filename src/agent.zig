const std = @import("std");
const printBanner = @import("config.zig").printBanner;

pub fn agentMain() !void {
    var buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var writer = stdout.writer(&buf);
    try printBanner(&writer.interface);
    try writer.interface.print("mode: agent\n", .{});
    try writer.interface.flush();
    // later: boot RPC server, load config, etc.
}
