const std = @import("std");

const Workload = struct {
    id: []u8,
    image: []u8,
    runtime_class: []u8,
    memory_mb: i64,
    cpu_milicores: i64,
};
