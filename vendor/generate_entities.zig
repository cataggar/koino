const std = @import("std");
const embedded_json = @embedFile("entities.json");

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const args = try init.minimal.args.toSlice(alloc);
    if (args.len != 2) std.debug.panic("wrong number of arguments", .{});

    const out_file_path = args[1];

    const tree = try std.json.parseFromSlice(
        std.json.Value,
        alloc,
        embedded_json,
        .{},
    );

    var buffer: std.Io.Writer.Allocating = .init(alloc);
    const writer = &buffer.writer;

    try writer.writeAll(
        \\pub const Entity = struct {
        \\    entity: []const u8,
        \\    codepoints: Codepoints,
        \\    characters: []const u8,
        \\};
        \\
        \\pub const Codepoints = union(enum) {
        \\    Single: u32,
        \\    Double: [2]u32,
        \\};
        \\
        \\pub const ENTITIES = [_]Entity{
        \\
    );

    var keys = try std.array_list.Managed([]const u8).initCapacity(
        alloc,
        tree.value.object.count(),
    );

    var entries_it = tree.value.object.iterator();
    while (entries_it.next()) |entry| {
        keys.appendAssumeCapacity(entry.key_ptr.*);
    }

    std.mem.sortUnstable([]const u8, keys.items, {}, strLessThan);

    for (keys.items) |key| {
        const value = tree.value.object.get(key).?.object;

        try writer.print(".{{ .entity = \"{f}\", .codepoints = ", .{std.zig.fmtString(key)});

        const codepoints_array = value.get("codepoints").?.array;
        if (codepoints_array.items.len == 1) {
            try writer.print(
                ".{{ .Single = {} }}, ",
                .{codepoints_array.items[0].integer},
            );
        } else {
            try writer.print(
                ".{{ .Double = [2]u32{{ {}, {} }} }}, ",
                .{
                    codepoints_array.items[0].integer,
                    codepoints_array.items[1].integer,
                },
            );
        }

        try writer.print(".characters = \"{f}\" }},\n", .{std.zig.fmtString(value.get("characters").?.string)});
    }

    try writer.writeAll("};\n");

    const out_file = try std.Io.Dir.cwd().createFile(init.io, out_file_path, .{});
    defer out_file.close(init.io);
    try out_file.writePositionalAll(init.io, buffer.written(), 0);
}

fn strLessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.lessThan(u8, lhs, rhs);
}
