const std = @import("std");

pub const parser = @import("parser.zig");
pub const Options = @import("options.zig").Options;
pub const nodes = @import("nodes.zig");
pub const html = @import("html.zig");

/// Performs work using internalAllocator, and writes the result to a Writer.
fn markdownToHtmlInternal(writer: anytype, internalAllocator: std.mem.Allocator, markdown: []const u8, options: Options) !void {
    var doc = try parse(internalAllocator, markdown, options);
    defer doc.deinit();

    try html.print(writer, internalAllocator, options, doc);
}

/// Parses Markdown into an AST.  Use `deinit()' on the returned document to free memory.
pub fn parse(internalAllocator: std.mem.Allocator, markdown: []const u8, options: Options) !*nodes.AstNode {
    var p = try parser.Parser.init(internalAllocator, options);
    defer p.deinit();
    try p.feed(markdown);
    return try p.finish();
}

/// Performs work with an ArenaAllocator backed by the page allocator, and allocates the result HTML with resultAllocator.
pub fn markdownToHtml(resultAllocator: std.mem.Allocator, markdown: []const u8, options: Options) ![]u8 {
    var result: std.Io.Writer.Allocating = .init(resultAllocator);
    errdefer result.deinit();
    try markdownToHtmlWriter(&result.writer, markdown, options);
    return result.toOwnedSlice();
}

/// Performs work with an ArenaAllocator backed by the page allocator, and writes the result to a Writer.
pub fn markdownToHtmlWriter(writer: anytype, markdown: []const u8, options: Options) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    try markdownToHtmlInternal(writer, arena.allocator(), markdown, options);
}

pub fn testMarkdownToHtml(options: Options, markdown: []const u8) ![]u8 {
    var scratch: std.heap.SafeAllocator = .init(std.heap.page_allocator, .{});
    defer std.debug.assert(scratch.deinit() == 0);
    var result: std.Io.Writer.Allocating = .init(std.testing.allocator);
    errdefer result.deinit();
    try markdownToHtmlInternal(&result.writer, scratch.allocator(), markdown, options);
    return result.toOwnedSlice();
}

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(parser);
    std.testing.refAllDecls(nodes);
    std.testing.refAllDecls(html);
    std.testing.refAllDecls(@import("ast.zig"));
    std.testing.refAllDecls(@import("strings.zig"));
    std.testing.refAllDecls(@import("scanners.zig"));
    std.testing.refAllDecls(@import("inlines.zig"));
    std.testing.refAllDecls(@import("table.zig"));
    std.testing.refAllDecls(@import("autolink.zig"));
}
