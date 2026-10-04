const std = @import("std");
const debug = std.debug;
const assert = debug.assert;

const koino = @import("test_koino");

const input_file_name = "cc-&-gfm.md";
const markdown = @embedFile("./" ++ input_file_name);

pub fn main(init: std.process.Init) !void {
    debug.print("Converting './examples/{s}' to HTML.\n", .{input_file_name});

    const allocator = init.gpa;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const options = koino.Options{
        .extensions = .{
            .table = true,
            .autolink = true,
            .strikethrough = true,
        },
    };

    var parser = try koino.parser.Parser.init(arena.allocator(), options);
    defer parser.deinit();
    try parser.feed(markdown);

    const doc = try parser.finish();
    defer doc.deinit();

    var buffer: std.Io.Writer.Allocating = .init(allocator);
    defer buffer.deinit();
    try koino.html.print(&buffer.writer, allocator, parser.options, doc);

    const output_file_path = "./examples/output-to-html.html";
    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(init.io, .{ .data = buffer.written(), .sub_path = output_file_path });

    debug.print("Done! Output has been saved in '{s}'.\n", .{output_file_path});
}
