const std = @import("std");

const hzzp = @import("../main.zig");
const util = @import("../util.zig");

const ascii = std.ascii;
const math = std.math;
const fmt = std.fmt;
const mem = std.mem;

const Version = std.builtin.Version;
const assert = std.debug.assert;

pub const StatusEvent = struct {
    version: Version,
    code: u16,
    reason: []const u8,
};

pub const PayloadEvent = struct {
    data: []const u8,
    final: bool = false,
};

pub const Event = union(enum) {
    status: StatusEvent,
    header: hzzp.Header,
    payload: PayloadEvent,

    head_done: void,
    skip: void,
    end: void,
};

// TODO: properly implement chunked encoding
//   - Chunk Extensions
// TODO: Parsing options?
//   - Accept malformed uri (so that it can be properly handled)?

// Supports HTTP/1.0 and HTTP/1.1

pub fn create(buffer: []u8, reader: anytype) ResponseParser(@TypeOf(reader)) {
    // Any buffer smaller than 16 cannot read the most simple status line (1xx A HTTP/1.1\r\n)
    assert(buffer.len >= 16);

    return ResponseParser(@TypeOf(reader)).init(buffer, reader);
}

pub fn ResponseParser(comptime Reader: type) type {
    return struct {
        const Self = @This();

        read_buffer: []u8,
        encoding: util.TransferEncoding = .unknown,
        has_chunked_trailer: bool = false,

        response_version: ?Version = null,
        read_needed: usize = 0,
        read_current: usize = 0,

        reader: Reader,

        trailer_state: bool = false,
        state: util.ParserState = .start_line,
        done: bool = false,

        pub fn init(buffer: []u8, reader: Reader) Self {
            return .{
                .read_buffer = buffer,
                .reader = reader,
            };
        }

        pub fn reset(self: *Self) void {
            self.encoding = .unknown;

            self.response_version = null;
            self.read_needed = 0;
            self.read_current = 0;

            self.state = .start_line;
            self.done = false;
        }

        pub const NextError = error{
            StreamTooLong, // std.io.reader.readUntilDelimiterOrEof
            EndOfStream,
            InvalidStatusLine,
            UnsupportedVersion,
            InvalidHeader,
            InvalidEncodingHeader,
            InvalidChunkedPayload,
        } || std.fmt.ParseIntError || Reader.Error;
        pub fn next(self: *Self) NextError!?Event {
            if (self.done) return null;

            switch (self.state) {
                .start_line => {
                    const line = util.normalizeLineEnding((try self.reader.readUntilDelimiterOrEof(self.read_buffer, '\n')) orelse return error.EndOfStream);
                    if (line.len == 0) return Event.skip; // RFC 7230 Section 3.5

                    var line_it = mem.split(u8, line, " ");

                    const http_version_buffer = line_it.next() orelse return error.InvalidStatusLine;
                    const code_buffer = line_it.next() orelse return error.InvalidStatusLine;
                    const reason_buffer = line_it.rest();

                    var version_it = mem.split(u8, http_version_buffer, "/");

                    const http = version_it.next() orelse return error.InvalidStatusLine;
                    const version_buffer = version_it.next() orelse return error.InvalidStatusLine;

                    // There should not be anything left
                    if (version_it.index) |_| return error.InvalidStatusLine;

                    if (!mem.eql(u8, http, "HTTP")) return error.InvalidStatusLine;
                    const version = Version.parse(version_buffer) catch return error.InvalidStatusLine;

                    if (!hzzp.supported_versions.includesVersion(version)) return error.UnsupportedVersion;

                    self.response_version = version;
                    self.state = .header;

                    return Event{
                        .status = .{
                            .version = version,
                            .code = try fmt.parseUnsigned(u16, code_buffer, 10),
                            .reason = reason_buffer,
                        },
                    };
                },
                .header => {
                    const line = util.normalizeLineEnding((try self.reader.readUntilDelimiterOrEof(self.read_buffer, '\n')) orelse return error.EndOfStream);
                    if (line.len == 0) {
                        if (self.trailer_state) {
                            self.encoding = .unknown;
                            self.done = true;

                            return Event.end;
                        } else {
                            self.state = .body;

                            return Event.head_done;
                        }
                    }

                    const index_separator = mem.indexOf(u8, line, ":") orelse 0;
                    if (index_separator == 0) return error.InvalidHeader;

                    const name = line[0..index_separator];
                    const value = mem.trim(u8, line[index_separator + 1 ..], &[_]u8{ ' ', '\t' });

                    if (ascii.eqlIgnoreCase(name, "content-length")) {
                        if (self.encoding != .unknown) return error.InvalidEncodingHeader;

                        self.encoding = .content_length;
                        self.read_needed = fmt.parseUnsigned(usize, value, 10) catch return error.InvalidEncodingHeader;
                    } else if (ascii.eqlIgnoreCase(name, "transfer-encoding")) {
                        if (self.encoding != .unknown) return error.InvalidEncodingHeader;

                        // We can only decode chunked messages, not compressed messages
                        if (ascii.indexOfIgnoreCase(value, "chunked") orelse 1 == 0) {
                            self.encoding = .chunked;
                        }
                    } else if (ascii.eqlIgnoreCase(name, "trailer")) {
                        // TODO: The TE header also needs to be set to "trailer" to allow trailer fields (according to spec)
                        self.has_chunked_trailer = true;
                    }

                    return Event{
                        .header = .{
                            .name = name,
                            .value = value,
                        },
                    };
                },
                .body => {
                    switch (self.encoding) {
                        .unknown => {
                            self.done = true;

                            return Event.end;
                        },
                        .content_length => {
                            const left = math.min(self.read_needed - self.read_current, self.read_buffer.len);
                            const read = try self.reader.read(self.read_buffer[0..left]);

                            self.read_current += read;

                            // Is it even possible for read_current to be > read_needed?
                            if (self.read_current >= self.read_needed) {
                                self.encoding = .unknown;
                            }

                            return Event{
                                .payload = .{
                                    .data = self.read_buffer[0..read],
                                    .final = self.read_current >= self.read_needed,
                                },
                            };
                        },
                        .chunked => {
                            if (self.read_needed == 0) {
                                const line = util.normalizeLineEnding((try self.reader.readUntilDelimiterOrEof(self.read_buffer, '\n')) orelse return error.EndOfStream);
                                const chunk_len = fmt.parseUnsigned(usize, line, 16) catch return error.InvalidChunkedPayload;

                                if (chunk_len == 0) {
                                    if (self.has_chunked_trailer) {
                                        self.state = .header;
                                        self.trailer_state = true;

                                        return Event.skip;
                                    } else {
                                        self.encoding = .unknown;
                                        self.done = true;

                                        return Event.end;
                                    }
                                } else {
                                    self.read_needed = chunk_len;
                                    self.read_current = 0;
                                }
                            }

                            const left = math.min(self.read_needed - self.read_current, self.read_buffer.len);
                            const read = try self.reader.read(self.read_buffer[0..left]);

                            self.read_current += read;

                            // Is it even possible for read_current to be > read_needed?
                            if (self.read_current >= self.read_needed) {
                                var crlf: [2]u8 = undefined;
                                const lfread = try self.reader.readAll(&crlf);

                                if (lfread < 2) return error.EndOfStream;
                                if (crlf[0] != '\r' or crlf[1] != '\n') return error.InvalidChunkedPayload;

                                self.read_needed = 0;
                            }

                            return Event{
                                .payload = .{
                                    .data = self.read_buffer[0..read],
                                    .final = self.read_needed == 0,
                                },
                            };
                        },
                    }
                },
            }
        }
    };
}

const testing = std.testing;
const io = std.io;

fn testNextField(parser: anytype, expected: ?Event) !void {
    const actual = try parser.next();

    try testing.expect(util.reworkedMetaEql(actual, expected));
}

test "decodes a simple response" {
    var read_buffer: [32]u8 = undefined;
    var response = "HTTP/1.1 404 Not Found\r\nHost: localhost\r\nContent-Length: 4\r\n\r\ngood";

    var reader = io.fixedBufferStream(response).reader();
    var parser = create(&read_buffer, reader);

    try testNextField(&parser, .{
        .status = .{
            .version = .{
                .major = 1,
                .minor = 1,
            },
            .code = 404,
            .reason = "Not Found",
        },
    });

    try testNextField(&parser, .{
        .header = .{
            .name = "Host",
            .value = "localhost",
        },
    });

    try testNextField(&parser, .{
        .header = .{
            .name = "Content-Length",
            .value = "4",
        },
    });

    try testNextField(&parser, Event.head_done);

    try testNextField(&parser, .{
        .payload = .{
            .data = "good",
            .final = true,
        },
    });

    try testNextField(&parser, Event.end);
    try testNextField(&parser, null);
}

test "decodes a simple chunked response" {
    var read_buffer: [32]u8 = undefined;
    var response = "HTTP/1.1 200 Ok\r\nHost: localhost\r\nTransfer-Encoding: chunked\r\n\r\n4\r\ngood\r\n0\r\n";

    var reader = io.fixedBufferStream(response).reader();
    var parser = create(&read_buffer, reader);

    try testNextField(&parser, .{
        .status = .{
            .version = .{
                .major = 1,
                .minor = 1,
            },
            .code = 200,
            .reason = "Ok",
        },
    });

    try testNextField(&parser, .{
        .header = .{
            .name = "Host",
            .value = "localhost",
        },
    });

    try testNextField(&parser, .{
        .header = .{
            .name = "Transfer-Encoding",
            .value = "chunked",
        },
    });

    try testNextField(&parser, Event.head_done);

    try testNextField(&parser, .{
        .payload = .{
            .data = "good",
            .final = true,
        },
    });

    try testNextField(&parser, Event.end);
    try testNextField(&parser, null);
}

test "decodes a simple chunked response with trailer" {
    var read_buffer: [32]u8 = undefined;
    var response = "HTTP/1.1 200 Ok\r\nHost: localhost\r\nTrailer: Expires\r\nTransfer-Encoding: chunked\r\n\r\n4\r\ngood\r\n0\r\nExpires: now\r\n\r\n";

    var reader = io.fixedBufferStream(response).reader();
    var parser = create(&read_buffer, reader);

    try testNextField(&parser, .{
        .status = .{
            .version = .{
                .major = 1,
                .minor = 1,
            },
            .code = 200,
            .reason = "Ok",
        },
    });

    try testNextField(&parser, .{
        .header = .{
            .name = "Host",
            .value = "localhost",
        },
    });

    try testNextField(&parser, .{
        .header = .{
            .name = "Trailer",
            .value = "Expires",
        },
    });

    try testNextField(&parser, .{
        .header = .{
            .name = "Transfer-Encoding",
            .value = "chunked",
        },
    });

    try testNextField(&parser, Event.head_done);

    try testNextField(&parser, .{
        .payload = .{
            .data = "good",
            .final = true,
        },
    });

    try testNextField(&parser, Event.skip);

    try testNextField(&parser, .{
        .header = .{
            .name = "Expires",
            .value = "now",
        },
    });

    try testNextField(&parser, Event.end);
    try testNextField(&parser, null);
}

comptime {
    std.testing.refAllDecls(@This());
}
