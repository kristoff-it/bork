const std = @import("std");

/// Adds all BearSSL sources to the exeobj step
/// Allows simple linking from build scripts.
pub fn linkBearSSL(comptime path_prefix: []const u8, module: *std.build.LibExeObjStep, target: std.zig.CrossTarget) void {
    module.linkLibC();

    module.addIncludeDir(path_prefix ++ "/BearSSL/inc");
    module.addIncludeDir(path_prefix ++ "/BearSSL/src");

    inline for (bearssl_sources) |srcfile| {
        module.addCSourceFile(path_prefix ++ srcfile, &[_][]const u8{
            "-Wall",
            "-DBR_LE_UNALIGNED=0", // this prevent BearSSL from using undefined behaviour when doing potential unaligned access
        });
    }

    if (target.isWindows()) {
        module.linkSystemLibrary("advapi32");
    }
}

// Export C for advanced interfacing
pub const c = @cImport({
    @cInclude("bearssl.h");
});

pub const BearError = error{
    BAD_PARAM,
    BAD_STATE,
    UNSUPPORTED_VERSION,
    BAD_VERSION,
    BAD_LENGTH,
    TOO_LARGE,
    BAD_MAC,
    NO_RANDOM,
    UNKNOWN_TYPE,
    UNEXPECTED,
    BAD_CCS,
    BAD_ALERT,
    BAD_HANDSHAKE,
    OVERSIZED_ID,
    BAD_CIPHER_SUITE,
    BAD_COMPRESSION,
    BAD_FRAGLEN,
    BAD_SECRENEG,
    EXTRA_EXTENSION,
    BAD_SNI,
    BAD_HELLO_DONE,
    LIMIT_EXCEEDED,
    BAD_FINISHED,
    RESUME_MISMATCH,
    INVALID_ALGORITHM,
    BAD_SIGNATURE,
    WRONG_KEY_USAGE,
    NO_CLIENT_AUTH,
    IO,
    X509_INVALID_VALUE,
    X509_TRUNCATED,
    X509_EMPTY_CHAIN,
    X509_INNER_TRUNC,
    X509_BAD_TAG_CLASS,
    X509_BAD_TAG_VALUE,
    X509_INDEFINITE_LENGTH,
    X509_EXTRA_ELEMENT,
    X509_UNEXPECTED,
    X509_NOT_CONSTRUCTED,
    X509_NOT_PRIMITIVE,
    X509_PARTIAL_BYTE,
    X509_BAD_BOOLEAN,
    X509_OVERFLOW,
    X509_BAD_DN,
    X509_BAD_TIME,
    X509_UNSUPPORTED,
    X509_LIMIT_EXCEEDED,
    X509_WRONG_KEY_TYPE,
    X509_BAD_SIGNATURE,
    X509_TIME_UNKNOWN,
    X509_EXPIRED,
    X509_DN_MISMATCH,
    X509_BAD_SERVER_NAME,
    X509_CRITICAL_EXTENSION,
    X509_NOT_CA,
    X509_FORBIDDEN_KEY_USAGE,
    X509_WEAK_PUBLIC_KEY,
    X509_NOT_TRUSTED,
};
fn convertError(err: c_int) BearError {
    return switch (err) {
        c.BR_ERR_BAD_PARAM => error.BAD_PARAM,
        c.BR_ERR_BAD_STATE => error.BAD_STATE,
        c.BR_ERR_UNSUPPORTED_VERSION => error.UNSUPPORTED_VERSION,
        c.BR_ERR_BAD_VERSION => error.BAD_VERSION,
        c.BR_ERR_BAD_LENGTH => error.BAD_LENGTH,
        c.BR_ERR_TOO_LARGE => error.TOO_LARGE,
        c.BR_ERR_BAD_MAC => error.BAD_MAC,
        c.BR_ERR_NO_RANDOM => error.NO_RANDOM,
        c.BR_ERR_UNKNOWN_TYPE => error.UNKNOWN_TYPE,
        c.BR_ERR_UNEXPECTED => error.UNEXPECTED,
        c.BR_ERR_BAD_CCS => error.BAD_CCS,
        c.BR_ERR_BAD_ALERT => error.BAD_ALERT,
        c.BR_ERR_BAD_HANDSHAKE => error.BAD_HANDSHAKE,
        c.BR_ERR_OVERSIZED_ID => error.OVERSIZED_ID,
        c.BR_ERR_BAD_CIPHER_SUITE => error.BAD_CIPHER_SUITE,
        c.BR_ERR_BAD_COMPRESSION => error.BAD_COMPRESSION,
        c.BR_ERR_BAD_FRAGLEN => error.BAD_FRAGLEN,
        c.BR_ERR_BAD_SECRENEG => error.BAD_SECRENEG,
        c.BR_ERR_EXTRA_EXTENSION => error.EXTRA_EXTENSION,
        c.BR_ERR_BAD_SNI => error.BAD_SNI,
        c.BR_ERR_BAD_HELLO_DONE => error.BAD_HELLO_DONE,
        c.BR_ERR_LIMIT_EXCEEDED => error.LIMIT_EXCEEDED,
        c.BR_ERR_BAD_FINISHED => error.BAD_FINISHED,
        c.BR_ERR_RESUME_MISMATCH => error.RESUME_MISMATCH,
        c.BR_ERR_INVALID_ALGORITHM => error.INVALID_ALGORITHM,
        c.BR_ERR_BAD_SIGNATURE => error.BAD_SIGNATURE,
        c.BR_ERR_WRONG_KEY_USAGE => error.WRONG_KEY_USAGE,
        c.BR_ERR_NO_CLIENT_AUTH => error.NO_CLIENT_AUTH,
        c.BR_ERR_IO => error.IO,
        c.BR_ERR_X509_INVALID_VALUE => error.X509_INVALID_VALUE,
        c.BR_ERR_X509_TRUNCATED => error.X509_TRUNCATED,
        c.BR_ERR_X509_EMPTY_CHAIN => error.X509_EMPTY_CHAIN,
        c.BR_ERR_X509_INNER_TRUNC => error.X509_INNER_TRUNC,
        c.BR_ERR_X509_BAD_TAG_CLASS => error.X509_BAD_TAG_CLASS,
        c.BR_ERR_X509_BAD_TAG_VALUE => error.X509_BAD_TAG_VALUE,
        c.BR_ERR_X509_INDEFINITE_LENGTH => error.X509_INDEFINITE_LENGTH,
        c.BR_ERR_X509_EXTRA_ELEMENT => error.X509_EXTRA_ELEMENT,
        c.BR_ERR_X509_UNEXPECTED => error.X509_UNEXPECTED,
        c.BR_ERR_X509_NOT_CONSTRUCTED => error.X509_NOT_CONSTRUCTED,
        c.BR_ERR_X509_NOT_PRIMITIVE => error.X509_NOT_PRIMITIVE,
        c.BR_ERR_X509_PARTIAL_BYTE => error.X509_PARTIAL_BYTE,
        c.BR_ERR_X509_BAD_BOOLEAN => error.X509_BAD_BOOLEAN,
        c.BR_ERR_X509_OVERFLOW => error.X509_OVERFLOW,
        c.BR_ERR_X509_BAD_DN => error.X509_BAD_DN,
        c.BR_ERR_X509_BAD_TIME => error.X509_BAD_TIME,
        c.BR_ERR_X509_UNSUPPORTED => error.X509_UNSUPPORTED,
        c.BR_ERR_X509_LIMIT_EXCEEDED => error.X509_LIMIT_EXCEEDED,
        c.BR_ERR_X509_WRONG_KEY_TYPE => error.X509_WRONG_KEY_TYPE,
        c.BR_ERR_X509_BAD_SIGNATURE => error.X509_BAD_SIGNATURE,
        c.BR_ERR_X509_TIME_UNKNOWN => error.X509_TIME_UNKNOWN,
        c.BR_ERR_X509_EXPIRED => error.X509_EXPIRED,
        c.BR_ERR_X509_DN_MISMATCH => error.X509_DN_MISMATCH,
        c.BR_ERR_X509_BAD_SERVER_NAME => error.X509_BAD_SERVER_NAME,
        c.BR_ERR_X509_CRITICAL_EXTENSION => error.X509_CRITICAL_EXTENSION,
        c.BR_ERR_X509_NOT_CA => error.X509_NOT_CA,
        c.BR_ERR_X509_FORBIDDEN_KEY_USAGE => error.X509_FORBIDDEN_KEY_USAGE,
        c.BR_ERR_X509_WEAK_PUBLIC_KEY => error.X509_WEAK_PUBLIC_KEY,
        c.BR_ERR_X509_NOT_TRUSTED => error.X509_NOT_TRUSTED,

        else => std.debug.panic("missing error code: {}", .{err}),
    };
}

pub const PublicKey = struct {
    const Self = @This();

    arena: std.heap.ArenaAllocator,
    key: KeyStore,
    usages: ?c_uint,

    pub fn fromX509(allocator: *std.mem.Allocator, inkey: c.br_x509_pkey) !Self {
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();

        var key = switch (inkey.key_type) {
            c.BR_KEYTYPE_RSA => KeyStore{
                .rsa = .{
                    .n = try std.mem.dupe(&arena.allocator, u8, inkey.key.rsa.n[0..inkey.key.rsa.nlen]),
                    .e = try std.mem.dupe(&arena.allocator, u8, inkey.key.rsa.e[0..inkey.key.rsa.elen]),
                },
            },
            c.BR_KEYTYPE_EC => KeyStore{
                .ec = .{
                    .curve = inkey.key.ec.curve,
                    .q = try std.mem.dupe(&arena.allocator, u8, inkey.key.ec.q[0..inkey.key.ec.qlen]),
                },
            },
            else => return error.UnsupportedKeyType,
        };

        return Self{
            .arena = arena,
            .key = key,
            .usages = null,
        };
    }

    pub fn toX509(self: Self) c.br_x509_pkey {
        switch (self.key) {
            .rsa => |rsa| {
                return c.br_x509_pkey{
                    .key_type = c.BR_KEYTYPE_RSA,
                    .key = .{
                        .rsa = .{
                            .n = rsa.n.ptr,
                            .nlen = rsa.n.len,
                            .e = rsa.e.ptr,
                            .elen = rsa.e.len,
                        },
                    },
                };
            },
            .ec => |ec| {
                return c.br_x509_pkey{
                    .key_type = c.BR_KEYTYPE_EC,
                    .key = .{
                        .ec = .{
                            .curve = ec.curve,
                            .q = ec.q.ptr,
                            .qlen = ec.q.len,
                        },
                    },
                };
            },
        }
    }

    pub fn deinit(self: Self) void {
        self.arena.deinit();
    }

    /// Encodes the public key with DER ASN.1 encoding into `target`.
    /// If `target` is not set, the function will only calculate the required
    /// buffer size.
    ///
    /// https://tools.ietf.org/html/rfc8017#appendix-A.1.1
    /// RSAPublicKey ::= SEQUENCE {
    ///     modulus           INTEGER,  -- n
    ///     publicExponent    INTEGER   -- e
    /// }
    pub fn asn1Encode(self: Self, target: ?[]u8) !usize {
        if (self.key != .rsa)
            return error.KeytypeNotSupportedYet;

        var sequence_content = [_]asn1.Value{
            asn1.Value{
                .integer = asn1.Integer{ .value = self.key.rsa.n },
            },
            asn1.Value{
                .integer = asn1.Integer{ .value = self.key.rsa.e },
            },
        };

        var sequence = asn1.Value{
            .sequence = asn1.Sequence{ .items = &sequence_content },
        };

        return try asn1.encode(target, sequence);
    }

    pub const KeyStore = union(enum) {
        ec: EC,
        rsa: RSA,

        pub const EC = struct {
            curve: c_int,
            q: []u8,
        };

        pub const RSA = struct {
            n: []u8,
            e: []u8,
        };
    };
};

pub const DERCertificate = struct {
    const Self = @This();

    allocator: *std.mem.Allocator,
    data: []u8,

    pub fn deinit(self: Self) void {
        self.allocator.free(self.data);
    }

    fn fromX509(allocator: *std.mem.Allocator, cert: *c.br_x509_certificate) !Certificate {
        return Self{
            .allocator = allocator,
            .data = try std.mem.dupe(allocator, u8, cert.data[0..cert.data_len]),
        };
    }

    fn toX509(self: *Self) c.br_x509_certificate {
        return c.br_x509_certificate{
            .data_len = self.data.len,
            .data = self.data.ptr,
        };
    }
};

pub const TrustAnchorCollection = struct {
    const Self = @This();

    arena: std.heap.ArenaAllocator,
    items: std.ArrayList(c.br_x509_trust_anchor),

    pub fn init(allocator: *std.mem.Allocator) Self {
        return Self{
            .items = std.ArrayList(c.br_x509_trust_anchor).init(allocator),
            .arena = std.heap.ArenaAllocator.init(allocator),
        };
    }

    pub fn appendFromPEM(self: *Self, pem_text: []const u8) !void {
        var objectBuffer = std.ArrayList(u8).init(self.items.allocator);
        defer objectBuffer.deinit();

        try objectBuffer.ensureCapacity(8192);

        var x509_decoder: c.br_pem_decoder_context = undefined;
        c.br_pem_decoder_init(&x509_decoder);

        var current_obj_is_certificate = false;

        var offset: usize = 0;
        while (offset < pem_text.len) {
            var diff = c.br_pem_decoder_push(&x509_decoder, pem_text.ptr + offset, pem_text.len - offset);
            offset += diff;

            var event = c.br_pem_decoder_event(&x509_decoder);
            switch (event) {
                0 => unreachable, // there must be an event, we always push the full file

                c.BR_PEM_BEGIN_OBJ => {
                    const name = std.mem.trim(
                        u8,
                        std.mem.spanZ(c.br_pem_decoder_name(&x509_decoder)),
                        "-",
                    );

                    current_obj_is_certificate = std.mem.eql(u8, name, "CERTIFICATE") or std.mem.eql(u8, name, "X509 CERTIFICATE");
                    if (current_obj_is_certificate) {
                        try objectBuffer.resize(0);
                        c.br_pem_decoder_setdest(&x509_decoder, appendToBuffer, &objectBuffer);
                    } else {
                        std.debug.warn("ignore object of type '{}'\n", .{name});
                        c.br_pem_decoder_setdest(&x509_decoder, null, null);
                    }
                },
                c.BR_PEM_END_OBJ => {
                    if (current_obj_is_certificate) {
                        var certificate = c.br_x509_certificate{
                            .data = objectBuffer.items.ptr,
                            .data_len = objectBuffer.items.len,
                        };

                        var trust_anchor = try convertToTrustAnchor(&self.arena.allocator, certificate);

                        try self.items.append(trust_anchor);
                        // ignore end of
                    } else {
                        std.debug.warn("end of ignored object.\n", .{});
                    }
                },
                c.BR_PEM_ERROR => {
                    std.debug.warn("pem error:\n", .{});
                },

                else => unreachable, // no other values are specified
            }
        }
    }

    pub fn deinit(self: Self) void {
        self.items.deinit();
        self.arena.deinit();
    }

    fn convertToTrustAnchor(allocator: *std.mem.Allocator, cert: c.br_x509_certificate) !c.br_x509_trust_anchor {
        var dc: c.br_x509_decoder_context = undefined;

        var vdn = std.ArrayList(u8).init(allocator);
        defer vdn.deinit();

        c.br_x509_decoder_init(&dc, appendToBuffer, &vdn);
        c.br_x509_decoder_push(&dc, cert.data, cert.data_len);

        const public_key: *c.br_x509_pkey = if (@ptrCast(?*c.br_x509_pkey, c.br_x509_decoder_get_pkey(&dc))) |pk|
            pk
        else
            return convertError(c.br_x509_decoder_last_error(&dc));

        var ta = c.br_x509_trust_anchor{
            .dn = undefined,
            .flags = 0,
            .pkey = undefined,
        };

        if (c.br_x509_decoder_isCA(&dc) != 0) {
            ta.flags |= c.BR_X509_TA_CA;
        }

        switch (public_key.key_type) {
            c.BR_KEYTYPE_RSA => {
                var n = try std.mem.dupe(allocator, u8, public_key.key.rsa.n[0..public_key.key.rsa.nlen]);
                errdefer allocator.free(n);

                var e = try std.mem.dupe(allocator, u8, public_key.key.rsa.e[0..public_key.key.rsa.elen]);
                errdefer allocator.free(e);

                ta.pkey = .{
                    .key_type = c.BR_KEYTYPE_RSA,
                    .key = .{
                        .rsa = .{
                            .n = n.ptr,
                            .nlen = n.len,
                            .e = e.ptr,
                            .elen = e.len,
                        },
                    },
                };
            },
            c.BR_KEYTYPE_EC => {
                var q = try std.mem.dupe(allocator, u8, public_key.key.ec.q[0..public_key.key.ec.qlen]);
                errdefer allocator.free(q);

                ta.pkey = .{
                    .key_type = c.BR_KEYTYPE_EC,
                    .key = .{
                        .ec = .{
                            .curve = public_key.key.ec.curve,
                            .q = q.ptr,
                            .qlen = q.len,
                        },
                    },
                };
            },
            else => return error.UnsupportedKeyType,
        }

        errdefer switch (public_key.key_type) {
            c.BR_KEYTYPE_RSA => {
                allocator.free(ta.pkey.key.rsa.n[0..ta.pkey.key.rsa.nlen]);
                allocator.free(ta.pkey.key.rsa.e[0..ta.pkey.key.rsa.elen]);
            },
            c.BR_KEYTYPE_EC => allocator.free(ta.pkey.key.ec.q[0..ta.pkey.key.ec.qlen]),
            else => unreachable,
        };

        const dn = vdn.toOwnedSlice();
        ta.dn = .{
            .data = dn.ptr,
            .len = dn.len,
        };

        return ta;
    }
};

// The "full" profile supports all implemented cipher suites.
//
// Rationale for suite order, from most important to least
// important rule:
//
// -- Don't use 3DES if AES or ChaCha20 is available.
// -- Try to have Forward Secrecy (ECDHE suite) if possible.
// -- When not using Forward Secrecy, ECDH key exchange is
//    better than RSA key exchange (slightly more expensive on the
//    client, but much cheaper on the server, and it implies smaller
//    messages).
// -- ChaCha20+Poly1305 is better than AES/GCM (faster, smaller code).
// -- GCM is better than CCM and CBC. CCM is better than CBC.
// -- CCM is preferable over CCM_8 (with CCM_8, forgeries may succeed
//    with probability 2^(-64)).
// -- AES-128 is preferred over AES-256 (AES-128 is already
//    strong enough, and AES-256 is 40% more expensive).
//
const cypher_suites = [_]u16{
    c.BR_TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256,
    c.BR_TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256,
    c.BR_TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,
    c.BR_TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,
    c.BR_TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,
    c.BR_TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,
    c.BR_TLS_ECDHE_ECDSA_WITH_AES_128_CCM,
    c.BR_TLS_ECDHE_ECDSA_WITH_AES_256_CCM,
    c.BR_TLS_ECDHE_ECDSA_WITH_AES_128_CCM_8,
    c.BR_TLS_ECDHE_ECDSA_WITH_AES_256_CCM_8,
    c.BR_TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA256,
    c.BR_TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA256,
    c.BR_TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA384,
    c.BR_TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA384,
    c.BR_TLS_ECDHE_ECDSA_WITH_AES_128_CBC_SHA,
    c.BR_TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA,
    c.BR_TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA,
    c.BR_TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA,
    c.BR_TLS_ECDH_ECDSA_WITH_AES_128_GCM_SHA256,
    c.BR_TLS_ECDH_RSA_WITH_AES_128_GCM_SHA256,
    c.BR_TLS_ECDH_ECDSA_WITH_AES_256_GCM_SHA384,
    c.BR_TLS_ECDH_RSA_WITH_AES_256_GCM_SHA384,
    c.BR_TLS_ECDH_ECDSA_WITH_AES_128_CBC_SHA256,
    c.BR_TLS_ECDH_RSA_WITH_AES_128_CBC_SHA256,
    c.BR_TLS_ECDH_ECDSA_WITH_AES_256_CBC_SHA384,
    c.BR_TLS_ECDH_RSA_WITH_AES_256_CBC_SHA384,
    c.BR_TLS_ECDH_ECDSA_WITH_AES_128_CBC_SHA,
    c.BR_TLS_ECDH_RSA_WITH_AES_128_CBC_SHA,
    c.BR_TLS_ECDH_ECDSA_WITH_AES_256_CBC_SHA,
    c.BR_TLS_ECDH_RSA_WITH_AES_256_CBC_SHA,
    c.BR_TLS_RSA_WITH_AES_128_GCM_SHA256,
    c.BR_TLS_RSA_WITH_AES_256_GCM_SHA384,
    c.BR_TLS_RSA_WITH_AES_128_CCM,
    c.BR_TLS_RSA_WITH_AES_256_CCM,
    c.BR_TLS_RSA_WITH_AES_128_CCM_8,
    c.BR_TLS_RSA_WITH_AES_256_CCM_8,
    c.BR_TLS_RSA_WITH_AES_128_CBC_SHA256,
    c.BR_TLS_RSA_WITH_AES_256_CBC_SHA256,
    c.BR_TLS_RSA_WITH_AES_128_CBC_SHA,
    c.BR_TLS_RSA_WITH_AES_256_CBC_SHA,
    c.BR_TLS_ECDHE_ECDSA_WITH_3DES_EDE_CBC_SHA,
    c.BR_TLS_ECDHE_RSA_WITH_3DES_EDE_CBC_SHA,
    c.BR_TLS_ECDH_ECDSA_WITH_3DES_EDE_CBC_SHA,
    c.BR_TLS_ECDH_RSA_WITH_3DES_EDE_CBC_SHA,
    c.BR_TLS_RSA_WITH_3DES_EDE_CBC_SHA,
};

// All hash functions are activated.
// Note: the X.509 validation engine will nonetheless refuse to
// validate signatures that use MD5 as hash function.
//
fn getHashClasses() [6]*const c.br_hash_class {
    return .{
        &c.br_md5_vtable,
        &c.br_sha1_vtable,
        &c.br_sha224_vtable,
        &c.br_sha256_vtable,
        &c.br_sha384_vtable,
        &c.br_sha512_vtable,
    };
}

pub const x509 = struct {
    pub const Minimal = struct {
        const Self = @This();

        engine: c.br_x509_minimal_context,

        pub fn init(tac: TrustAnchorCollection) Self {
            var self = Self{
                .engine = undefined,
            };
            const xc = &self.engine;

            // X.509 engine uses SHA-256 to hash certificate DN (for
            // comparisons).
            //
            c.br_x509_minimal_init(xc, &c.br_sha256_vtable, tac.items.items.ptr, tac.items.items.len);

            c.br_x509_minimal_set_rsa(xc, c.br_rsa_pkcs1_vrfy_get_default());
            c.br_x509_minimal_set_ecdsa(xc, &c.br_ec_all_m31, c.br_ecdsa_i31_vrfy_asn1);

            // Set supported hash functions, for the SSL engine and for the
            // X.509 engine.
            const hash_classes = getHashClasses();
            var id: usize = c.br_md5_ID;
            while (id <= c.br_sha512_ID) : (id += 1) {
                const hc = hash_classes[id - 1];
                c.br_x509_minimal_set_hash(xc, @intCast(c_int, id), hc);
            }

            return self;
        }

        pub fn getEngine(self: *Self) *[*c]const c.br_x509_class {
            return &self.engine.vtable;
        }
    };

    pub const KnownKey = struct {
        const Self = @This();

        engine: c.br_x509_knownkey_context,

        pub fn init(key: PublicKey, allowKeyExchange: bool, allowSigning: bool) Self {
            return KnownKey{
                .engine = c.br_x509_knownkey_context{
                    .vtable = &c.br_x509_knownkey_vtable,
                    .pkey = key.toX509(),
                    .usages = (key.usages orelse 0) |
                        (if (allowKeyExchange) @as(c_uint, c.BR_KEYTYPE_KEYX) else 0) |
                        (if (allowSigning) @as(c_uint, c.BR_KEYTYPE_SIGN) else 0), // always allow a stored key for key-exchange
                },
            };
        }

        pub fn getEngine(self: *Self) *[*c]const c.br_x509_class {
            return &self.engine.vtable;
        }
    };
};

pub const Client = struct {
    const Self = @This();

    client: c.br_ssl_client_context,
    iobuf: [c.BR_SSL_BUFSIZE_BIDI]u8,

    pub fn init(engine: *[*c]const c.br_x509_class) Self {
        var ctx = Self{
            .client = undefined,
            .iobuf = undefined,
        };

        const cc = &ctx.client;

        // Reset client context and set supported versions from TLS-1.0
        // to TLS-1.2 (inclusive).
        //
        c.br_ssl_client_zero(cc);
        c.br_ssl_engine_set_versions(&cc.eng, c.BR_TLS10, c.BR_TLS12);

        // Set suites and asymmetric crypto implementations. We use the
        // "i31" code for RSA (it is somewhat faster than the "i32"
        // implementation).
        // TODO: change that when better implementations are made available.

        c.br_ssl_engine_set_suites(&cc.eng, &cypher_suites[0], cypher_suites.len);
        c.br_ssl_client_set_default_rsapub(cc);
        c.br_ssl_engine_set_default_rsavrfy(&cc.eng);
        c.br_ssl_engine_set_default_ecdsa(&cc.eng);

        // Set supported hash functions, for the SSL engine and for the
        // X.509 engine.
        const hash_classes = getHashClasses();
        var id: c_int = c.br_md5_ID;
        while (id <= c.br_sha512_ID) : (id += 1) {
            const hc = hash_classes[@intCast(usize, id - 1)];
            c.br_ssl_engine_set_hash(&cc.eng, id, hc);
        }

        // Set the PRF implementations.
        c.br_ssl_engine_set_prf10(&cc.eng, c.br_tls10_prf);
        c.br_ssl_engine_set_prf_sha256(&cc.eng, c.br_tls12_sha256_prf);
        c.br_ssl_engine_set_prf_sha384(&cc.eng, c.br_tls12_sha384_prf);

        // Symmetric encryption. We use the "default" implementations
        // (fastest among constant-time implementations).
        c.br_ssl_engine_set_default_aes_cbc(&cc.eng);
        c.br_ssl_engine_set_default_aes_ccm(&cc.eng);
        c.br_ssl_engine_set_default_aes_gcm(&cc.eng);
        c.br_ssl_engine_set_default_des_cbc(&cc.eng);
        c.br_ssl_engine_set_default_chapol(&cc.eng);

        // Link the X.509 engine in the SSL engine.
        c.br_ssl_engine_set_x509(&cc.eng, @ptrCast([*c][*c]const c.br_x509_class, engine));

        return ctx;
    }

    pub fn relocate(self: *Self) void {
        c.br_ssl_engine_set_buffer(&self.client.eng, &self.iobuf, self.iobuf.len, 1);
    }

    pub fn reset(self: *Self, host: [:0]const u8, resumeSession: bool) !void {
        const err = c.br_ssl_client_reset(&self.client, host, if (resumeSession) @as(c_int, 1) else 0);
        if (err < 0)
            return convertError(c.br_ssl_engine_last_error(&self.client.eng));
    }

    pub fn getEngine(self: *Self) *c.br_ssl_engine_context {
        return &self.client.eng;
    }
};

const fd_is_int = (@typeInfo(std.os.fd_t) == .Int);

pub fn initStream(engine: *c.br_ssl_engine_context, in_stream: anytype, out_stream: anytype) Stream(@TypeOf(in_stream), @TypeOf(out_stream)) {
    std.debug.assert(@typeInfo(@TypeOf(in_stream)) == .Pointer);
    std.debug.assert(@typeInfo(@TypeOf(out_stream)) == .Pointer);
    return Stream(@TypeOf(in_stream), @TypeOf(out_stream)).init(engine, in_stream, out_stream);
}

pub fn Stream(comptime SrcInStream: type, comptime SrcOutStream: type) type {
    return struct {
        const Self = @This();

        engine: *c.br_ssl_engine_context,
        ioc: c.br_sslio_context,

        /// Initializes a new SSLStream backed by the ssl engine and file descriptor.
        pub fn init(engine: *c.br_ssl_engine_context, in_stream: SrcInStream, out_stream: SrcOutStream) Self {
            var stream = Self{
                .engine = engine,
                .ioc = undefined,
            };
            c.br_sslio_init(
                &stream.ioc,
                stream.engine,
                sockRead,
                @ptrCast(*c_void, in_stream),
                sockWrite,
                @ptrCast(*c_void, out_stream),
            );
            return stream;
        }

        /// Closes the connection. Note that this may fail when the remote part does not terminate the SSL stream correctly.
        pub fn close(self: *Self) !void {
            if (c.br_sslio_close(&self.ioc) < 0)
                return convertError(c.br_ssl_engine_last_error(self.engine));
        }

        /// Flushes all pending data into the fd.
        pub fn flush(self: *Self) !void {
            if (c.br_sslio_flush(&self.ioc) < 0)
                return convertError(c.br_ssl_engine_last_error(self.engine));
        }

        /// low level read from fd to ssl library
        fn sockRead(ctx: ?*c_void, buf: [*c]u8, len: usize) callconv(.C) c_int {
            var input = @ptrCast(SrcInStream, @alignCast(@alignOf(std.meta.Child(SrcInStream)), ctx.?));
            return if (input.read(buf[0..len])) |num|
                if (num > 0) @intCast(c_int, num) else -1
            else |err|
                -1;
        }

        /// low level  write from ssl library to fd
        fn sockWrite(ctx: ?*c_void, buf: [*c]const u8, len: usize) callconv(.C) c_int {
            var output = @ptrCast(SrcOutStream, @alignCast(@alignOf(std.meta.Child(SrcOutStream)), ctx.?));
            return if (output.write(buf[0..len])) |num|
                if (num > 0) @intCast(c_int, num) else -1
            else |err|
                -1;
        }

        const ReadError = error{EndOfStream} || BearError;

        /// reads some data from the ssl stream.
        pub fn read(self: *Self, buffer: []u8) ReadError!usize {
            var result = c.br_sslio_read(&self.ioc, buffer.ptr, buffer.len);
            if (result < 0) {
                const errc = c.br_ssl_engine_last_error(self.engine);
                if (errc == c.BR_ERR_OK)
                    return 0;
                return convertError(errc);
            }
            return @intCast(usize, result);
        }

        const WriteError = error{EndOfStream} || BearError;

        /// writes some data to the ssl stream.
        pub fn write(self: *Self, bytes: []const u8) WriteError!usize {
            var result = c.br_sslio_write(&self.ioc, bytes.ptr, bytes.len);
            if (result < 0) {
                const errc = c.br_ssl_engine_last_error(self.engine);
                if (errc == c.BR_ERR_OK)
                    return 0;
                return convertError(errc);
            }
            return @intCast(usize, result);
        }

        pub const DstInStream = std.io.InStream(*Self, ReadError, read);
        pub fn inStream(self: *Self) DstInStream {
            return .{ .context = self };
        }

        pub const DstOutStream = std.io.OutStream(*Self, WriteError, write);
        pub fn outStream(self: *Self) DstOutStream {
            return .{ .context = self };
        }
    };
}

fn appendToBuffer(dest_ctx: ?*c_void, buf: ?*const c_void, len: usize) callconv(.C) void {
    var dest_buffer = @ptrCast(*std.ArrayList(u8), @alignCast(@alignOf(std.ArrayList(u8)), dest_ctx));
    // std.debug.warn("read chunk of {} bytes...\n", .{len});

    dest_buffer.appendSlice(@ptrCast([*]const u8, buf)[0..len]) catch |err| {
        std.debug.warn("failed to read chunk of {} bytes...\n", .{len});
    };
}

fn Vector(comptime T: type) type {
    return extern struct {
        buf: ?[*]T,
        ptr: usize,
        len: usize,
    };
}

const asn1 = struct {
    const Type = enum {
        bit_string,
        boolean,
        integer,
        @"null",
        object_identifier,
        octet_string,
        bmpstring,
        ia5string,
        printable_string,
        utf8_string,
        sequence,
        set,
    };

    const Value = union(Type) {
        bit_string: void,
        boolean: void,
        integer: Integer,
        @"null": void,
        object_identifier: void,
        octet_string: void,
        bmpstring: void,
        ia5string: void,
        printable_string: void,
        utf8_string: void,
        sequence: void,
        set: void,
    };

    const Integer = struct {
        value: []u8,
    };

    const Sequence = struct {
        items: []Value,
    };

    fn encode(buffer: ?[]u8, value: Value) !usize {
        //
    }
};

const bearssl_sources = [_][]const u8{
    "/BearSSL/src/settings.c",
    "/BearSSL/src/aead/ccm.c",
    "/BearSSL/src/aead/eax.c",
    "/BearSSL/src/aead/gcm.c",
    "/BearSSL/src/codec/ccopy.c",
    "/BearSSL/src/codec/dec16be.c",
    "/BearSSL/src/codec/dec16le.c",
    "/BearSSL/src/codec/dec32be.c",
    "/BearSSL/src/codec/dec32le.c",
    "/BearSSL/src/codec/dec64be.c",
    "/BearSSL/src/codec/dec64le.c",
    "/BearSSL/src/codec/enc16be.c",
    "/BearSSL/src/codec/enc16le.c",
    "/BearSSL/src/codec/enc32be.c",
    "/BearSSL/src/codec/enc32le.c",
    "/BearSSL/src/codec/enc64be.c",
    "/BearSSL/src/codec/enc64le.c",
    "/BearSSL/src/codec/pemdec.c",
    "/BearSSL/src/codec/pemenc.c",
    "/BearSSL/src/ec/ec_all_m15.c",
    "/BearSSL/src/ec/ec_all_m31.c",
    "/BearSSL/src/ec/ec_c25519_i15.c",
    "/BearSSL/src/ec/ec_c25519_i31.c",
    "/BearSSL/src/ec/ec_c25519_m15.c",
    "/BearSSL/src/ec/ec_c25519_m31.c",
    "/BearSSL/src/ec/ec_c25519_m62.c",
    "/BearSSL/src/ec/ec_c25519_m64.c",
    "/BearSSL/src/ec/ec_curve25519.c",
    "/BearSSL/src/ec/ec_default.c",
    "/BearSSL/src/ec/ec_keygen.c",
    "/BearSSL/src/ec/ec_p256_m15.c",
    "/BearSSL/src/ec/ec_p256_m31.c",
    "/BearSSL/src/ec/ec_p256_m62.c",
    "/BearSSL/src/ec/ec_p256_m64.c",
    "/BearSSL/src/ec/ec_prime_i15.c",
    "/BearSSL/src/ec/ec_prime_i31.c",
    "/BearSSL/src/ec/ec_pubkey.c",
    "/BearSSL/src/ec/ec_secp256r1.c",
    "/BearSSL/src/ec/ec_secp384r1.c",
    "/BearSSL/src/ec/ec_secp521r1.c",
    "/BearSSL/src/ec/ecdsa_atr.c",
    "/BearSSL/src/ec/ecdsa_default_sign_asn1.c",
    "/BearSSL/src/ec/ecdsa_default_sign_raw.c",
    "/BearSSL/src/ec/ecdsa_default_vrfy_asn1.c",
    "/BearSSL/src/ec/ecdsa_default_vrfy_raw.c",
    "/BearSSL/src/ec/ecdsa_i15_bits.c",
    "/BearSSL/src/ec/ecdsa_i15_sign_asn1.c",
    "/BearSSL/src/ec/ecdsa_i15_sign_raw.c",
    "/BearSSL/src/ec/ecdsa_i15_vrfy_asn1.c",
    "/BearSSL/src/ec/ecdsa_i15_vrfy_raw.c",
    "/BearSSL/src/ec/ecdsa_i31_bits.c",
    "/BearSSL/src/ec/ecdsa_i31_sign_asn1.c",
    "/BearSSL/src/ec/ecdsa_i31_sign_raw.c",
    "/BearSSL/src/ec/ecdsa_i31_vrfy_asn1.c",
    "/BearSSL/src/ec/ecdsa_i31_vrfy_raw.c",
    "/BearSSL/src/ec/ecdsa_rta.c",
    "/BearSSL/src/hash/dig_oid.c",
    "/BearSSL/src/hash/dig_size.c",
    "/BearSSL/src/hash/ghash_ctmul.c",
    "/BearSSL/src/hash/ghash_ctmul32.c",
    "/BearSSL/src/hash/ghash_ctmul64.c",
    "/BearSSL/src/hash/ghash_pclmul.c",
    "/BearSSL/src/hash/ghash_pwr8.c",
    "/BearSSL/src/hash/md5.c",
    "/BearSSL/src/hash/md5sha1.c",
    "/BearSSL/src/hash/mgf1.c",
    "/BearSSL/src/hash/multihash.c",
    "/BearSSL/src/hash/sha1.c",
    "/BearSSL/src/hash/sha2big.c",
    "/BearSSL/src/hash/sha2small.c",
    "/BearSSL/src/int/i15_add.c",
    "/BearSSL/src/int/i15_bitlen.c",
    "/BearSSL/src/int/i15_decmod.c",
    "/BearSSL/src/int/i15_decode.c",
    "/BearSSL/src/int/i15_decred.c",
    "/BearSSL/src/int/i15_encode.c",
    "/BearSSL/src/int/i15_fmont.c",
    "/BearSSL/src/int/i15_iszero.c",
    "/BearSSL/src/int/i15_moddiv.c",
    "/BearSSL/src/int/i15_modpow.c",
    "/BearSSL/src/int/i15_modpow2.c",
    "/BearSSL/src/int/i15_montmul.c",
    "/BearSSL/src/int/i15_mulacc.c",
    "/BearSSL/src/int/i15_muladd.c",
    "/BearSSL/src/int/i15_ninv15.c",
    "/BearSSL/src/int/i15_reduce.c",
    "/BearSSL/src/int/i15_rshift.c",
    "/BearSSL/src/int/i15_sub.c",
    "/BearSSL/src/int/i15_tmont.c",
    "/BearSSL/src/int/i31_add.c",
    "/BearSSL/src/int/i31_bitlen.c",
    "/BearSSL/src/int/i31_decmod.c",
    "/BearSSL/src/int/i31_decode.c",
    "/BearSSL/src/int/i31_decred.c",
    "/BearSSL/src/int/i31_encode.c",
    "/BearSSL/src/int/i31_fmont.c",
    "/BearSSL/src/int/i31_iszero.c",
    "/BearSSL/src/int/i31_moddiv.c",
    "/BearSSL/src/int/i31_modpow.c",
    "/BearSSL/src/int/i31_modpow2.c",
    "/BearSSL/src/int/i31_montmul.c",
    "/BearSSL/src/int/i31_mulacc.c",
    "/BearSSL/src/int/i31_muladd.c",
    "/BearSSL/src/int/i31_ninv31.c",
    "/BearSSL/src/int/i31_reduce.c",
    "/BearSSL/src/int/i31_rshift.c",
    "/BearSSL/src/int/i31_sub.c",
    "/BearSSL/src/int/i31_tmont.c",
    "/BearSSL/src/int/i32_add.c",
    "/BearSSL/src/int/i32_bitlen.c",
    "/BearSSL/src/int/i32_decmod.c",
    "/BearSSL/src/int/i32_decode.c",
    "/BearSSL/src/int/i32_decred.c",
    "/BearSSL/src/int/i32_div32.c",
    "/BearSSL/src/int/i32_encode.c",
    "/BearSSL/src/int/i32_fmont.c",
    "/BearSSL/src/int/i32_iszero.c",
    "/BearSSL/src/int/i32_modpow.c",
    "/BearSSL/src/int/i32_montmul.c",
    "/BearSSL/src/int/i32_mulacc.c",
    "/BearSSL/src/int/i32_muladd.c",
    "/BearSSL/src/int/i32_ninv32.c",
    "/BearSSL/src/int/i32_reduce.c",
    "/BearSSL/src/int/i32_sub.c",
    "/BearSSL/src/int/i32_tmont.c",
    "/BearSSL/src/int/i62_modpow2.c",
    "/BearSSL/src/kdf/hkdf.c",
    "/BearSSL/src/kdf/shake.c",
    "/BearSSL/src/mac/hmac.c",
    "/BearSSL/src/mac/hmac_ct.c",
    "/BearSSL/src/rand/aesctr_drbg.c",
    "/BearSSL/src/rand/hmac_drbg.c",
    "/BearSSL/src/rand/sysrng.c",
    "/BearSSL/src/rsa/rsa_default_keygen.c",
    "/BearSSL/src/rsa/rsa_default_modulus.c",
    "/BearSSL/src/rsa/rsa_default_oaep_decrypt.c",
    "/BearSSL/src/rsa/rsa_default_oaep_encrypt.c",
    "/BearSSL/src/rsa/rsa_default_pkcs1_sign.c",
    "/BearSSL/src/rsa/rsa_default_pkcs1_vrfy.c",
    "/BearSSL/src/rsa/rsa_default_priv.c",
    "/BearSSL/src/rsa/rsa_default_privexp.c",
    "/BearSSL/src/rsa/rsa_default_pss_sign.c",
    "/BearSSL/src/rsa/rsa_default_pss_vrfy.c",
    "/BearSSL/src/rsa/rsa_default_pub.c",
    "/BearSSL/src/rsa/rsa_default_pubexp.c",
    "/BearSSL/src/rsa/rsa_i15_keygen.c",
    "/BearSSL/src/rsa/rsa_i15_modulus.c",
    "/BearSSL/src/rsa/rsa_i15_oaep_decrypt.c",
    "/BearSSL/src/rsa/rsa_i15_oaep_encrypt.c",
    "/BearSSL/src/rsa/rsa_i15_pkcs1_sign.c",
    "/BearSSL/src/rsa/rsa_i15_pkcs1_vrfy.c",
    "/BearSSL/src/rsa/rsa_i15_priv.c",
    "/BearSSL/src/rsa/rsa_i15_privexp.c",
    "/BearSSL/src/rsa/rsa_i15_pss_sign.c",
    "/BearSSL/src/rsa/rsa_i15_pss_vrfy.c",
    "/BearSSL/src/rsa/rsa_i15_pub.c",
    "/BearSSL/src/rsa/rsa_i15_pubexp.c",
    "/BearSSL/src/rsa/rsa_i31_keygen.c",
    "/BearSSL/src/rsa/rsa_i31_keygen_inner.c",
    "/BearSSL/src/rsa/rsa_i31_modulus.c",
    "/BearSSL/src/rsa/rsa_i31_oaep_decrypt.c",
    "/BearSSL/src/rsa/rsa_i31_oaep_encrypt.c",
    "/BearSSL/src/rsa/rsa_i31_pkcs1_sign.c",
    "/BearSSL/src/rsa/rsa_i31_pkcs1_vrfy.c",
    "/BearSSL/src/rsa/rsa_i31_priv.c",
    "/BearSSL/src/rsa/rsa_i31_privexp.c",
    "/BearSSL/src/rsa/rsa_i31_pss_sign.c",
    "/BearSSL/src/rsa/rsa_i31_pss_vrfy.c",
    "/BearSSL/src/rsa/rsa_i31_pub.c",
    "/BearSSL/src/rsa/rsa_i31_pubexp.c",
    "/BearSSL/src/rsa/rsa_i32_oaep_decrypt.c",
    "/BearSSL/src/rsa/rsa_i32_oaep_encrypt.c",
    "/BearSSL/src/rsa/rsa_i32_pkcs1_sign.c",
    "/BearSSL/src/rsa/rsa_i32_pkcs1_vrfy.c",
    "/BearSSL/src/rsa/rsa_i32_priv.c",
    "/BearSSL/src/rsa/rsa_i32_pss_sign.c",
    "/BearSSL/src/rsa/rsa_i32_pss_vrfy.c",
    "/BearSSL/src/rsa/rsa_i32_pub.c",
    "/BearSSL/src/rsa/rsa_i62_keygen.c",
    "/BearSSL/src/rsa/rsa_i62_oaep_decrypt.c",
    "/BearSSL/src/rsa/rsa_i62_oaep_encrypt.c",
    "/BearSSL/src/rsa/rsa_i62_pkcs1_sign.c",
    "/BearSSL/src/rsa/rsa_i62_pkcs1_vrfy.c",
    "/BearSSL/src/rsa/rsa_i62_priv.c",
    "/BearSSL/src/rsa/rsa_i62_pss_sign.c",
    "/BearSSL/src/rsa/rsa_i62_pss_vrfy.c",
    "/BearSSL/src/rsa/rsa_i62_pub.c",
    "/BearSSL/src/rsa/rsa_oaep_pad.c",
    "/BearSSL/src/rsa/rsa_oaep_unpad.c",
    "/BearSSL/src/rsa/rsa_pkcs1_sig_pad.c",
    "/BearSSL/src/rsa/rsa_pkcs1_sig_unpad.c",
    "/BearSSL/src/rsa/rsa_pss_sig_pad.c",
    "/BearSSL/src/rsa/rsa_pss_sig_unpad.c",
    "/BearSSL/src/rsa/rsa_ssl_decrypt.c",
    "/BearSSL/src/ssl/prf.c",
    "/BearSSL/src/ssl/prf_md5sha1.c",
    "/BearSSL/src/ssl/prf_sha256.c",
    "/BearSSL/src/ssl/prf_sha384.c",
    "/BearSSL/src/ssl/ssl_ccert_single_ec.c",
    "/BearSSL/src/ssl/ssl_ccert_single_rsa.c",
    "/BearSSL/src/ssl/ssl_client.c",
    "/BearSSL/src/ssl/ssl_client_default_rsapub.c",
    "/BearSSL/src/ssl/ssl_client_full.c",
    "/BearSSL/src/ssl/ssl_engine.c",
    "/BearSSL/src/ssl/ssl_engine_default_aescbc.c",
    "/BearSSL/src/ssl/ssl_engine_default_aesccm.c",
    "/BearSSL/src/ssl/ssl_engine_default_aesgcm.c",
    "/BearSSL/src/ssl/ssl_engine_default_chapol.c",
    "/BearSSL/src/ssl/ssl_engine_default_descbc.c",
    "/BearSSL/src/ssl/ssl_engine_default_ec.c",
    "/BearSSL/src/ssl/ssl_engine_default_ecdsa.c",
    "/BearSSL/src/ssl/ssl_engine_default_rsavrfy.c",
    "/BearSSL/src/ssl/ssl_hashes.c",
    "/BearSSL/src/ssl/ssl_hs_client.c",
    "/BearSSL/src/ssl/ssl_hs_server.c",
    "/BearSSL/src/ssl/ssl_io.c",
    "/BearSSL/src/ssl/ssl_keyexport.c",
    "/BearSSL/src/ssl/ssl_lru.c",
    "/BearSSL/src/ssl/ssl_rec_cbc.c",
    "/BearSSL/src/ssl/ssl_rec_ccm.c",
    "/BearSSL/src/ssl/ssl_rec_chapol.c",
    "/BearSSL/src/ssl/ssl_rec_gcm.c",
    "/BearSSL/src/ssl/ssl_scert_single_ec.c",
    "/BearSSL/src/ssl/ssl_scert_single_rsa.c",
    "/BearSSL/src/ssl/ssl_server.c",
    "/BearSSL/src/ssl/ssl_server_full_ec.c",
    "/BearSSL/src/ssl/ssl_server_full_rsa.c",
    "/BearSSL/src/ssl/ssl_server_mine2c.c",
    "/BearSSL/src/ssl/ssl_server_mine2g.c",
    "/BearSSL/src/ssl/ssl_server_minf2c.c",
    "/BearSSL/src/ssl/ssl_server_minf2g.c",
    "/BearSSL/src/ssl/ssl_server_minr2g.c",
    "/BearSSL/src/ssl/ssl_server_minu2g.c",
    "/BearSSL/src/ssl/ssl_server_minv2g.c",
    "/BearSSL/src/symcipher/aes_big_cbcdec.c",
    "/BearSSL/src/symcipher/aes_big_cbcenc.c",
    "/BearSSL/src/symcipher/aes_big_ctr.c",
    "/BearSSL/src/symcipher/aes_big_ctrcbc.c",
    "/BearSSL/src/symcipher/aes_big_dec.c",
    "/BearSSL/src/symcipher/aes_big_enc.c",
    "/BearSSL/src/symcipher/aes_common.c",
    "/BearSSL/src/symcipher/aes_ct.c",
    "/BearSSL/src/symcipher/aes_ct64.c",
    "/BearSSL/src/symcipher/aes_ct64_cbcdec.c",
    "/BearSSL/src/symcipher/aes_ct64_cbcenc.c",
    "/BearSSL/src/symcipher/aes_ct64_ctr.c",
    "/BearSSL/src/symcipher/aes_ct64_ctrcbc.c",
    "/BearSSL/src/symcipher/aes_ct64_dec.c",
    "/BearSSL/src/symcipher/aes_ct64_enc.c",
    "/BearSSL/src/symcipher/aes_ct_cbcdec.c",
    "/BearSSL/src/symcipher/aes_ct_cbcenc.c",
    "/BearSSL/src/symcipher/aes_ct_ctr.c",
    "/BearSSL/src/symcipher/aes_ct_ctrcbc.c",
    "/BearSSL/src/symcipher/aes_ct_dec.c",
    "/BearSSL/src/symcipher/aes_ct_enc.c",
    "/BearSSL/src/symcipher/aes_pwr8.c",
    "/BearSSL/src/symcipher/aes_pwr8_cbcdec.c",
    "/BearSSL/src/symcipher/aes_pwr8_cbcenc.c",
    "/BearSSL/src/symcipher/aes_pwr8_ctr.c",
    "/BearSSL/src/symcipher/aes_pwr8_ctrcbc.c",
    "/BearSSL/src/symcipher/aes_small_cbcdec.c",
    "/BearSSL/src/symcipher/aes_small_cbcenc.c",
    "/BearSSL/src/symcipher/aes_small_ctr.c",
    "/BearSSL/src/symcipher/aes_small_ctrcbc.c",
    "/BearSSL/src/symcipher/aes_small_dec.c",
    "/BearSSL/src/symcipher/aes_small_enc.c",
    "/BearSSL/src/symcipher/aes_x86ni.c",
    "/BearSSL/src/symcipher/aes_x86ni_cbcdec.c",
    "/BearSSL/src/symcipher/aes_x86ni_cbcenc.c",
    "/BearSSL/src/symcipher/aes_x86ni_ctr.c",
    "/BearSSL/src/symcipher/aes_x86ni_ctrcbc.c",
    "/BearSSL/src/symcipher/chacha20_ct.c",
    "/BearSSL/src/symcipher/chacha20_sse2.c",
    "/BearSSL/src/symcipher/des_ct.c",
    "/BearSSL/src/symcipher/des_ct_cbcdec.c",
    "/BearSSL/src/symcipher/des_ct_cbcenc.c",
    "/BearSSL/src/symcipher/des_support.c",
    "/BearSSL/src/symcipher/des_tab.c",
    "/BearSSL/src/symcipher/des_tab_cbcdec.c",
    "/BearSSL/src/symcipher/des_tab_cbcenc.c",
    "/BearSSL/src/symcipher/poly1305_ctmul.c",
    "/BearSSL/src/symcipher/poly1305_ctmul32.c",
    "/BearSSL/src/symcipher/poly1305_ctmulq.c",
    "/BearSSL/src/symcipher/poly1305_i15.c",
    "/BearSSL/src/x509/asn1enc.c",
    "/BearSSL/src/x509/encode_ec_pk8der.c",
    "/BearSSL/src/x509/encode_ec_rawder.c",
    "/BearSSL/src/x509/encode_rsa_pk8der.c",
    "/BearSSL/src/x509/encode_rsa_rawder.c",
    "/BearSSL/src/x509/skey_decoder.c",
    "/BearSSL/src/x509/x509_decoder.c",
    "/BearSSL/src/x509/x509_knownkey.c",
    "/BearSSL/src/x509/x509_minimal.c",
    "/BearSSL/src/x509/x509_minimal_full.c",
};
