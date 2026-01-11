const std = @import("std");
const printBanner = @import("config.zig").printBanner;

pub fn controlPlaneMain() !void {
    var buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var writer = stdout.writer(&buf);
    try printBanner(&writer.interface);
    try writer.interface.print("mode: control-plane\n", .{});
    try writer.interface.flush();
    // later: start HTTP / RPC endpoints, scheduler, etc.
}
