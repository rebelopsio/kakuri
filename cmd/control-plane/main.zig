const std = @import("std");
const kakuri = @import("kakuri");

pub fn main() !void {
    try kakuri.control_plane.controlPlaneMain();
}
