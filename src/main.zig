const std = @import("std");

pub fn main() !void {
    //
    // Set up allocator
    //

    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const allocator = gpa.allocator();

    //
    // Read UnicodeData.txt and normalize newlines
    //

    const file = try std.fs.cwd().openFile("UnicodeData.txt", .{});
    defer file.close();

    const contents = try file.readToEndAlloc(allocator, 3 * 1024 * 1024);
    const normalized = try std.mem.replaceOwned(u8, allocator, contents, "\r\n", "\n");

    allocator.free(contents);
    defer allocator.free(normalized);

    //
    // Set up CCC map
    //

    var ccc_map = std.AutoHashMap(u32, u8).init(allocator);
    defer ccc_map.deinit();

    //
    // Iterate over lines and find combining classes
    //

    var line_iter = std.mem.splitScalar(u8, normalized, '\n');

    while (line_iter.next()) |line| {
        if (line.len == 0) continue;

        var fields = std.ArrayList([]const u8).init(allocator);
        defer fields.deinit();

        var field_iter = std.mem.splitScalar(u8, line, ';');
        while (field_iter.next()) |field| {
            try fields.append(field);
        }

        const code_point = try std.fmt.parseInt(u32, fields.items[0], 16);

        if ((0x3400 <= code_point and code_point <= 0x4DBF) // CJK ext A
        or (0x4E00 <= code_point and code_point <= 0x9FFF) // CJK
        or (0xAC00 <= code_point and code_point <= 0xD7A3) // Hangul
        or (0xD800 <= code_point and code_point <= 0xDFFF) // Surrogates
        or (0xE000 <= code_point and code_point <= 0xF8FF) // Private use
        or (0x17000 <= code_point and code_point <= 0x187F7) // Tangut
        or (0x18D00 <= code_point and code_point <= 0x18D08) // Tangut suppl
        or (0x20000 <= code_point and code_point <= 0x2A6DF) // CJK ext B
        or (0x2A700 <= code_point and code_point <= 0x2B738) // CJK ext C
        or (0x2B740 <= code_point and code_point <= 0x2B81D) // CJK ext D
        or (0x2B820 <= code_point and code_point <= 0x2CEA1) // CJK ext E
        or (0x2CEB0 <= code_point and code_point <= 0x2EBE0) // CJK ext F
        or (0x30000 <= code_point and code_point <= 0x3134A) // CJK ext G
        or (0xF0000 <= code_point and code_point <= 0xFFFFD) // Plane 15 private use
        or (0x10_0000 <= code_point and code_point <= 0x10_FFFD) // Plane 16 private use
        ) {
            continue;
        }

        const ccc_column = fields.items[3];
        std.debug.assert(1 <= ccc_column.len and ccc_column.len <= 3);

        const ccc = try std.fmt.parseInt(u8, ccc_column, 10);
        if (ccc == 0) continue;

        //
        // Add CCC to map
        //

        try ccc_map.put(code_point, ccc);
    }

    //
    // Write CCC map to a JSON file
    //

    const output_file = try std.fs.cwd().createFile("ccc.json", .{ .truncate = true });
    defer output_file.close();

    var ws = std.json.writeStream(output_file.writer(), .{ .whitespace = .indent_2 });
    try ws.beginObject();

    var map_iter = ccc_map.iterator();
    while (map_iter.next()) |entry| {
        const key_str = try std.fmt.allocPrint(allocator, "{}", .{entry.key_ptr.*});
        try ws.objectField(key_str);
        try ws.write(entry.value_ptr.*);

        allocator.free(key_str);
    }

    try ws.endObject();
}
