const std = @import("std");

pub fn create(b: *std.Build, source: *std.Build.Dependency, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Step.Compile {
    const headers = b.addWriteFiles();
    _ = headers.addCopyFile(source.path("pcre-8.45/config.h.generic"), "config.h");
    _ = headers.addCopyFile(source.path("pcre-8.45/pcre.h.generic"), "pcre.h");
    const tables = headers.addCopyFile(source.path("pcre-8.45/pcre_chartables.c.dist"), "pcre_chartables.c");
    const lib = b.addLibrary(.{
        .name = "pcre",
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    lib.root_module.addIncludePath(headers.getDirectory());
    lib.root_module.addIncludePath(source.path("pcre-8.45"));
    lib.installHeader(headers.getDirectory().path(b, "pcre.h"), "pcre.h");
    const flags: []const []const u8 = &.{
        "-DHAVE_CONFIG_H",
        "-DHAVE_STDLIB_H=1",
        "-DHAVE_STRING_H=1",
        "-DHAVE_MEMMOVE=1",
        "-DSUPPORT_PCRE8=1",
        "-DSUPPORT_UTF=1",
        "-DSUPPORT_UCP=1",
        "-DPCRE_STATIC=1",
    };
    lib.root_module.addCSourceFile(.{ .file = tables, .flags = flags });
    lib.root_module.addCSourceFiles(.{
        .root = source.path("pcre-8.45"),
        .flags = flags,
        .files = &.{
            "pcre_byte_order.c", "pcre_compile.c",  "pcre_config.c",
            "pcre_dfa_exec.c",   "pcre_exec.c",     "pcre_fullinfo.c",
            "pcre_get.c",        "pcre_globals.c",  "pcre_jit_compile.c",
            "pcre_maketables.c", "pcre_newline.c",  "pcre_ord2utf8.c",
            "pcre_printint.c",   "pcre_refcount.c", "pcre_string_utils.c",
            "pcre_study.c",      "pcre_tables.c",   "pcre_ucd.c",
            "pcre_valid_utf8.c", "pcre_version.c",  "pcre_xclass.c",
        },
    });
    return lib;
}
