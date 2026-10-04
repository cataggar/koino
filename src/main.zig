const std = @import("std");

const clap = @import("clap");
const koino = @import("koino");

const Parser = koino.parser.Parser;
const Options = koino.Options;
const html = koino.html;

const MAX_BUFFER_SIZE = 64 * 1024;
const MAX_CONTENT_SIZE = 1024 * 1024 * 1024;

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const allocator = arena.allocator();
    var options: Options = undefined;
    var args = try parseArgs(init, &options, allocator);
    defer args.deinit();
    var parser = try Parser.init(allocator, options);
    defer parser.deinit();

    if (args.positionals[0]) |pos| {
        const markdown = try std.Io.Dir.cwd().readFileAlloc(init.io, pos, allocator, .limited(MAX_CONTENT_SIZE));
        defer allocator.free(markdown);
        try parser.feed(markdown);
    } else {
        var stdin_buf: [MAX_BUFFER_SIZE]u8 = undefined;
        var stdin_reader = std.Io.File.stdin().readerStreaming(init.io, &stdin_buf);

        var alloc_writer = std.Io.Writer.Allocating.init(allocator);
        defer alloc_writer.deinit();

        _ = try stdin_reader.interface.streamRemaining(&alloc_writer.writer);
        const markdown = alloc_writer.written();
        try parser.feed(markdown);
    }

    const doc = try parser.finish();
    defer doc.deinit();
    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();
    try html.print(&output.writer, allocator, options, doc);

    var buf: [MAX_BUFFER_SIZE]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &buf);
    try stdout_writer.interface.writeAll(output.written());
    try stdout_writer.interface.flush();
}

const params = clap.parseParamsComptime("-h, --help                 Display this help and exit\n" ++
    "-u, --unsafe               Render raw HTML and dangerous URLs\n" ++
    "-e, --extension <str>...   Enable an extension (" ++ extensionsFriendly ++ ")\n" ++
    "    --header-anchors       Generate anchors for headers\n" ++
    "    --smart                Use smart punctuation\n" ++
    "<str>");

const ClapResult = clap.Result(clap.Help, &params, clap.parsers.default);

fn parseArgs(init: std.process.Init, options: *Options, allocator: std.mem.Allocator) !ClapResult {
    var stderr_buf: [MAX_BUFFER_SIZE]u8 = undefined;
    var stderr = std.Io.File.stderr().writer(init.io, &stderr_buf);

    var diagnostic: clap.Diagnostic = .{};
    const res = clap.parse(clap.Help, &params, clap.parsers.default, init.minimal.args, .{
        .allocator = allocator,
        .diagnostic = &diagnostic,
    }) catch |err| {
        try diagnostic.reportToFile(init.io, .stderr(), err);
        return err;
    };

    if (res.args.help != 0) {
        try stderr.interface.writeAll("Usage: koino ");
        try clap.usage(&stderr.interface, clap.Help, &params);
        try stderr.interface.writeAll("\n\nOptions:\n");
        try clap.help(&stderr.interface, clap.Help, &params, .{});
        try stderr.interface.flush();
        std.process.exit(0);
    }

    options.* = .{};
    if (res.args.unsafe != 0)
        options.render.unsafe = true;
    if (res.args.smart != 0)
        options.parse.smart = true;
    if (res.args.@"header-anchors" != 0)
        options.render.header_anchors = true;

    for (res.args.extension) |extension|
        try enableExtension(extension, options);

    return res;
}

const extensions = std.meta.fieldNames(Options.Extensions);

const extensionsFriendly = blk: {
    var extsFriendly: []const u8 = &[_]u8{};
    var first = true;
    for (extensions) |extension| {
        if (first) {
            first = false;
        } else {
            extsFriendly = extsFriendly ++ ",";
        }
        extsFriendly = extsFriendly ++ extension;
    }
    break :blk extsFriendly;
};

fn enableExtension(extension: []const u8, options: *Options) !void {
    inline for (extensions) |valid_extension| {
        if (std.mem.eql(u8, valid_extension, extension)) {
            @field(options.extensions, valid_extension) = true;
            return;
        }
    }
    std.log.err("unknown extension: {s}\n", .{extension});
    std.process.exit(1);
}
