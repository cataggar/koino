const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const pcre_source = b.dependency("pcre_source", .{});
    const pcre = @import("build/pcre.zig").create(b, pcre_source, target, optimize);
    const translated: @import("translate_c").Translator = .init(b.dependency("translate_c", .{}), .{
        .name = "pcre_c",
        .c_source_file = b.addWriteFiles().add("pcre_bindings.h",
            \\#define PCRE_STATIC 1
            \\#include <pcre.h>
            \\
        ),
        .target = target,
        .optimize = optimize,
    });
    translated.linkLibrary(pcre);
    const pcre_mod = b.createModule(.{
        .root_source_file = b.path("vendor/libpcre.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    pcre_mod.addImport("pcre_c", translated.mod);
    const genent = b.addExecutable(.{
        .name = "generate_entities",
        .root_module = b.createModule(.{
            .root_source_file = b.path("vendor/generate_entities.zig"),
            .target = b.graph.host,
            .optimize = .debug,
        }),
    });
    const entities = b.addRunArtifact(genent).addOutputFileArg("entities.zig");
    const entities_mod = b.createModule(.{
        .root_source_file = b.path("vendor/htmlentities.zig"),
        .target = target,
        .optimize = optimize,
    });
    entities_mod.addAnonymousImport("entities", .{ .root_source_file = entities });
    const uucode_pkg = b.dependency("uucode", .{
        .optimize = optimize,
        .target = target,
        .fields = @as([]const []const u8, &.{
            "general_category",
            "simple_lowercase_mapping",
        }),
    });
    const mod = b.addModule("koino", .{
        .root_source_file = b.path("src/koino.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("libpcre", pcre_mod);
    mod.addImport("uucode", uucode_pkg.module("uucode"));
    mod.addImport("htmlentities", entities_mod);
    const tests = b.addTest(.{ .root_module = mod, .use_llvm = true });
    b.step("test", "Run library tests").dependOn(&b.addRunArtifact(tests).step);
    const spec_mod = b.createModule(.{
        .root_source_file = b.path("tools/spec.zig"),
        .target = target,
        .optimize = optimize,
    });
    spec_mod.addImport("koino", mod);
    const specs = b.addRunArtifact(b.addExecutable(.{
        .name = "koino-spec",
        .root_module = spec_mod,
        .use_llvm = true,
    }));
    specs.addFileArg(b.path("vendor/cmark-gfm/test/spec.txt"));
    b.step("spec", "Run the CommonMark fixtures using Zig").dependOn(&specs.step);

    if (b.option(bool, "no-cli", "Build only the library") orelse false) return;
    const clap_pkg = b.lazyDependency("clap", .{ .optimize = optimize, .target = target }) orelse return;

    // Workaround: uucode's generated tables trigger a crash in Zig's
    // self-hosted x86_64 backend. Force LLVM until this is resolved upstream.
    const exe = b.addExecutable(.{
        .name = "koino",
        .use_llvm = true,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),

            .target = target,
            .optimize = optimize,

            .imports = &.{
                .{ .name = "koino", .module = mod },
                .{ .name = "clap", .module = clap_pkg.module("clap") },
            },
        }),
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    run_cmd.addPassthruArgs();

    const example = b.addExecutable(.{
        .name = "koino_example",
        .use_llvm = true,
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/to-html.zig"),

            .target = target,
            .optimize = optimize,

            .imports = &.{
                .{ .name = "test_koino", .module = mod },
            },
        }),
    });

    b.installArtifact(example);

    const example_run_cmd = b.addRunArtifact(example);
    example_run_cmd.step.dependOn(b.getInstallStep());
    const example_run_step = b.step("example", "Run example");
    example_run_step.dependOn(&example_run_cmd.step);
}
