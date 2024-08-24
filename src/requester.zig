const std = @import("std");

pub var enable_nsfw = false;
// pub const base_url = "https://nekos.moe/api/v1/random/image?nsfw=false";

const ImageId = struct {
    id: []const u8,
};

pub const Response = struct {
    images: []ImageId,
};

pub fn parseJsonResponse(allocator: std.mem.Allocator, response: []u8) !std.json.Parsed(Response) {
    const parsed = try std.json.parseFromSlice(Response, allocator, response, .{
        .ignore_unknown_fields = true,
    });

    return parsed;
}

pub fn createRequest(alloc: std.mem.Allocator, target_url: []const u8) anyerror!std.http.Client.Request {
    var client = std.http.Client{
        .allocator = alloc,
    };

    var buf: [4096]u8 = undefined;
    const req_url = try std.Uri.parse(target_url);
    var req = try client.open(.GET, req_url, .{
        .server_header_buffer = &buf,
    });

    try req.send();
    try req.finish();
    try req.wait();

    return req;
}

pub fn loadImage(alloc: std.mem.Allocator) ![]u8 {
    const url = switch (enable_nsfw) {
        true => "https://nekos.moe/api/v1/random/image?nsfw=true",
        false => "https://nekos.moe/api/v1/random/image?nsfw=false",
    };
    std.debug.print("using url: {s}\n", .{url});
    const mib = 1024 * 1024 * 1024;

    var request = try createRequest(alloc, url);
    var response_buffer = std.ArrayList(u8).init(alloc);
    defer response_buffer.deinit();
    try request.reader().readAllArrayList(&response_buffer, mib);

    const payload = try parseJsonResponse(alloc, response_buffer.items);
    defer payload.deinit();
    const image_id = payload.value.images[0].id;

    var image_id_s: [9]u8 = undefined;
    @memcpy(&image_id_s, image_id[0..9]);

    const url_template = "https://nekos.moe/image/{s}";
    const url_buffer = try std.fmt.allocPrint(alloc, url_template, .{image_id});
    response_buffer.clearAndFree();

    var image_request = try createRequest(alloc, url_buffer);
    try image_request.reader().readAllArrayList(&response_buffer, 10 * mib);

    const result = try alloc.alloc(u8, response_buffer.items.len);
    @memcpy(result, response_buffer.items);

    const file_path = try std.fmt.allocPrint(alloc, "/tmp/catgrildownloader/{s}.png", .{image_id_s[0..8]});
    //std.debug.print("file path is {s}\n", .{file_path});
    const file = try std.fs.createFileAbsolute(file_path, .{ .read = true });
    try file.writeAll(result);

    return file_path;
}
