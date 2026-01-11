const std = @import("std");
const kakuri = @import("kakuri");

pub fn main() !void {
    try kakuri.agent.agentMain();
}
