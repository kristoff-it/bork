const std = @import("std");

const Version = std.builtin.Version;

pub const log = std.log.scoped(.hzzp);

pub const supported_versions = Version.Range{
    .min = .{
        .major = 1,
        .minor = 0,
    },
    .max = .{
        .major = 1,
        .minor = 1,
    },
};

pub const TransferEncoding = enum {
    content_length,
    chunked,
    unknown,
};

// zig fmt: off
pub const StatusCode = enum(u10) {
    // as per RFC 7231

    info_continue            = 100,
    info_switching_protocols = 101,

    success_ok                = 200,
    success_created           = 201,
    success_accepted          = 202,
    success_non_authoritative = 203,
    success_no_content        = 204,
    success_reset_content     = 205,
    success_partial_content   = 206,

    redirect_choices   = 300,
    redirect_permanent = 301,
    redirect_found     = 302,
    redirect_see_other = 303,
    redirect_use_proxy = 305,
    redirect_temporary = 307,

    client_bad_request        = 400,
    client_payment_required   = 402,
    client_forbidden          = 403,
    client_not_found          = 404,
    client_method_not_allowed = 405,
    client_not_acceptable     = 406,
    client_request_timeout    = 408,
    client_conflict           = 409,
    client_gone               = 410,
    client_length_required    = 411,
    client_payload_too_large  = 413,
    client_uri_too_long       = 414,
    client_unsupported_media  = 415,
    client_expectation_failed = 417,
    client_upgrade_required   = 426,

    server_internal_error           = 500,
    server_not_implemented          = 501,
    server_bad_gateway              = 502,
    server_service_unavailable      = 503,
    server_gateway_timeout          = 504,
    server_http_version_unsupported = 505,
    
    _,

    pub fn code(self: StatusCode) @TagType(StatusCode) {
        return @enumToInt(self);
    }

    pub fn isValid(self: StatusCode) bool {
        return @enumToInt(self) >= 100 and @enumToInt(self) < 600;
    }
};
// zig fmt: on

pub const Header = struct {
    name: []const u8,
    value: []const u8,
};

pub const HeadersSlice = []const Header;
