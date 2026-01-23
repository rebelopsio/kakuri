const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // kakuri module
    const kakuri_mod = b.createModule(.{
        .root_source_file = b.path("src/kakuri.zig"),
        .target = target,
        .optimize = optimize,
    });

    // json module
    // const json_mod = b.createModule(.{
    //     .root_source_file = b.path("src/json.zig"),
    //     .target = target,
    //     .optimize = optimize,
    // });

    // http module
    // const http_mod = b.createModule(.{
    //     .root_source_file = b.path("src/http.zig"),
    //     .target = target,
    //     .optimize = optimize,
    // });

    // tcp module
    // const tcp_mod = b.createModule(.{
    //     .root_source_file = b.path("src/tcp.zig"),
    //     .target = target,
    //     .optimize = optimize,
    // });

    // const agent_mod = b.createModule(.{
    //     .root_source_file = b.path("src/agent.zig"),
    //     .target = target,
    //     .optimize = optimize,
    // });

    // kakuri-agent
    const agent_exe = b.addExecutable(.{
        .name = "kakuri-agent",
        .root_module = b.createModule(.{
            .root_source_file = b.path("cmd/agent/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "kakuri", .module = kakuri_mod },
            },
        }),
    });
    b.installArtifact(agent_exe);

    // kakuri-control-plane
    const cp_exe = b.addExecutable(.{
        .name = "kakuri-control-plane",
        .root_module = b.createModule(.{
            .root_source_file = b.path("cmd/control-plane/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "kakuri", .module = kakuri_mod },
            },
        }),
    });
    b.installArtifact(cp_exe);

    const kakuri_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/kakuri.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_kakuri_tests = b.addRunArtifact(kakuri_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_kakuri_tests.step);

    // Optional convenience run steps
    const run_agent = b.addRunArtifact(agent_exe);
    if (b.args) |args| run_agent.addArgs(args);
    const run_agent_step = b.step("run-agent", "Run kakuri agent");
    run_agent_step.dependOn(&run_agent.step);

    const run_cp = b.addRunArtifact(cp_exe);
    if (b.args) |args| run_cp.addArgs(args);
    const run_cp_step = b.step("run-control-plane", "Run kakuri control plane");
    run_cp_step.dependOn(&run_cp.step);
}
