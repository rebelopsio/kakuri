const std = @import("std");

pub const Resources = struct {
    memory_mb: u64,
    cpu_millicores: u64,
};

pub const Workload = struct {
    id: []const u8,
    image: []const u8,
    runtime_class: []const u8,
    resources: Resources,
    enabled: bool,
    description: ?[]const u8,
    ports: []u64,
};
