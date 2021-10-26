const std = @import("std");

pub fn sense(word: []const u8) bool {
    return std.mem.startsWith(u8, word, "http") or
        std.mem.startsWith(u8, word, "(http");
}

pub fn clean(url: []const u8) []const u8 {
    if (url[0] == '(') {
        if (url[url.len - 1] == ')') {
            return url[1..(url.len - 1)];
        }
        return url[1..];
    }
    return url;
}
