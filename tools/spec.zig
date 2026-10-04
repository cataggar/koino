const std = @import("std");
const koino = @import("koino");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.gpa);
    defer init.gpa.free(args);
    if (args.len != 2) return error.ExpectedSpecFile;
    const spec = try std.Io.Dir.cwd().readFileAlloc(init.io, args[1], init.gpa, .limited(4 * 1024 * 1024));
    defer init.gpa.free(spec);
    const fence = "````````````````````````````````";
    var lines = std.mem.splitScalar(u8, spec, '\n');
    var offset: usize = 0;
    var markdown_start: ?usize = null;
    var markdown_end: ?usize = null;
    var html_start: usize = 0;
    var options: koino.Options = .{};
    var disabled = false;
    var total: usize = 0;
    var failures: usize = 0;
    while (lines.next()) |line| {
        const start = offset;
        offset += line.len + 1;
        if (std.mem.startsWith(u8, line, fence ++ " example")) {
            markdown_start = offset;
            markdown_end = null;
            options = .{ .render = .{ .unsafe = true } };
            disabled = false;
            var extensions = std.mem.tokenizeAny(u8, line[(fence ++ " example").len..], " \r\t");
            while (extensions.next()) |extension| {
                if (std.mem.eql(u8, extension, "disabled")) {
                    disabled = true;
                } else {
                    var found = false;
                    inline for (comptime std.meta.fieldNames(koino.Options.Extensions)) |name| {
                        if (std.mem.eql(u8, extension, name)) {
                            @field(options.extensions, name) = true;
                            found = true;
                        }
                    }
                    if (!found) return error.UnknownSpecExtension;
                }
            }
        } else if (markdown_start != null and std.mem.eql(u8, line, ".")) {
            markdown_end = start;
            html_start = offset;
        } else if (markdown_start != null and std.mem.eql(u8, line, fence)) {
            defer markdown_start = null;
            if (disabled) continue;
            const end = markdown_end orelse return error.MalformedSpecExample;
            const markdown = try std.mem.replaceOwned(u8, init.gpa, spec[markdown_start.?..end], "\xe2\x86\x92", "\t");
            defer init.gpa.free(markdown);
            const expected = try std.mem.replaceOwned(u8, init.gpa, spec[html_start..start], "\xe2\x86\x92", "\t");
            defer init.gpa.free(expected);
            const actual = try koino.markdownToHtml(init.gpa, markdown, options);
            defer init.gpa.free(actual);
            const actual_normalized = try normalizeHtml(init.gpa, actual);
            defer init.gpa.free(actual_normalized);
            const expected_normalized = try normalizeHtml(init.gpa, expected);
            defer init.gpa.free(expected_normalized);
            total += 1;
            if (!std.mem.eql(u8, actual_normalized, expected_normalized) and !std.mem.eql(u8, std.mem.trim(u8, expected, " \n\r"), "<IGNORE>")) {
                failures += 1;
                if (failures <= 5) std.debug.print("Example {d} mismatch\nMarkdown:\n{s}\nExpected: \"{f}\"\nActual: \"{f}\"\n", .{ total, markdown, std.zig.fmtString(expected), std.zig.fmtString(actual) });
            }
        }
    }
    if (markdown_start != null or total == 0) return error.MalformedSpec;
    std.debug.print("CommonMark: {d}/{d} examples passed\n", .{ total - failures, total });
    if (failures != 0) return error.CommonMarkSpecFailed;
}

fn normalizeHtml(allocator: std.mem.Allocator, html: []const u8) ![]u8 {
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(allocator);
    var i: usize = 0;
    var in_pre = false;
    var after_block = true;
    while (i < html.len) {
        if (html[i] == '<') {
            const end = std.mem.findScalarPos(u8, html, i, '>') orelse {
                try output.appendSlice(allocator, html[i..]);
                break;
            };
            const tag = html[i .. end + 1];
            const closing = std.mem.startsWith(u8, tag, "</");
            const name_start: usize = if (closing) 2 else 1;
            const name_end = std.mem.findAnyPos(u8, tag, name_start, " \r\n\t/>") orelse tag.len;
            const name = tag[name_start..name_end];
            var block = false;
            for ([_][]const u8{ "article", "header", "aside", "hgroup", "blockquote", "hr", "iframe", "body", "li", "map", "button", "object", "canvas", "ol", "caption", "output", "col", "p", "colgroup", "pre", "dd", "progress", "div", "section", "dl", "table", "td", "dt", "tbody", "embed", "textarea", "fieldset", "tfoot", "figcaption", "th", "figure", "thead", "footer", "tr", "form", "ul", "h1", "h2", "h3", "h4", "h5", "h6", "video", "script", "style" }) |block_name| {
                if (std.ascii.eqlIgnoreCase(name, block_name)) block = true;
            }
            if (block and !in_pre) output.items.len = std.mem.trimEnd(u8, output.items, " \t\r\n").len;
            try output.appendSlice(allocator, tag);
            if (std.ascii.eqlIgnoreCase(name, "pre")) in_pre = !closing;
            after_block = block;
            i = end + 1;
        } else {
            const byte = html[i];
            i += 1;
            if (!in_pre and std.ascii.isWhitespace(byte)) {
                if (!after_block and (output.items.len == 0 or output.items[output.items.len - 1] != ' ')) try output.append(allocator, ' ');
            } else {
                try output.append(allocator, byte);
                after_block = false;
            }
        }
    }
    output.items.len = std.mem.trimEnd(u8, output.items, " \t\r\n").len;
    return output.toOwnedSlice(allocator);
}
