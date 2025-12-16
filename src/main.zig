const root = @import("root.zig");
const std = root.std;

pub fn agentMain() !void {
    var buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var writer = stdout.writer(&buf);
    try root.printBanner(&writer.interface);
    try writer.interface.print("mode: agent\n", .{});
    try writer.interface.flush();
    // later: boot RPC server, load config, etc.
}

pub fn controlPlaneMain() !void {
    var buf: [4096]u8 = undefined;
    const stdout = std.fs.File.stdout();
    var writer = stdout.writer(&buf);
    try root.printBanner(&writer.interface);
    try writer.interface.print("mode: control-plane\n", .{});
    try writer.interface.flush();
    // later: start HTTP / RPC endpoints, scheduler, etc.
}
