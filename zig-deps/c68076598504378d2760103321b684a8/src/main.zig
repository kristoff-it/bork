const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const Sha256 = std.crypto.hash.sha2.Sha256;
const Hmac256 = std.crypto.auth.hmac.sha2.HmacSha256;
const Chacha20Poly1305 = std.crypto.aead.chacha_poly.ChaCha20Poly1305;

pub const asn1 = @import("asn1.zig");
pub const x509 = @import("x509.zig");

const mixtime = @import("mixtime.zig").mixtime;

comptime {
    std.testing.refAllDecls(x509);
    std.testing.refAllDecls(asn1);
}

// zig fmt: off
const client_hello_start: [61]u8 = [_]u8{
    // Record header: Handshake record type, protocol version, handshake size
    0x16, 0x03, 0x01, undefined, undefined,
    // Handshake message type, bytes of client hello
    0x01, undefined, undefined, undefined,
    // Client version (hardcoded to TLS 1.2 even for TLS 1.3)
    0x03, 0x03,
} ++ ([1]u8{undefined} ** 32) ++ [_]u8{
    // Session ID
    0x00,
    // Cipher suites, we just use TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256 (CC A8) for now
    0x00, 0x02, 0xCC, 0xA8,
    // Compression methods (no compression)
    0x01, 0x00,
    // Extensions length
    undefined, undefined,
    // Extension: server
    // id, length, length of entry
    0x00, 0x00, undefined, undefined, undefined, undefined,
    // entry type, length of bytes
    0x00, undefined, undefined,
};

const client_hello_end = [37]u8 {
    // Extension: supported groups, for now just x25519 (00 1D)
    0x00, 0x0A, 0x00, 0x04, 0x00, 0x02, 0x00, 0x1D,
    // Extension: EC point formats => uncompressed point format
    0x00, 0x0B, 0x00, 0x02, 0x01, 0x00,
    // Extension: Signature algorithms
    // RSA/PKCS1/SHA256, ECDSA/SECP256r1/SHA256, RSA/PKCS1/SHA512, ECDSA/SECP521r1/SHA512
    0x00, 0x0D, 0x00, 0x0A, 0x00, 0x08, 0x04, 0x01, 0x04, 0x03, 0x06, 0x01, 0x06, 0x02,
    // Extension: Renegotiation Info => new connection
    0xFF, 0x01, 0x00, 0x01, 0x00,
    // Extension: SCT (signed certificate timestamp)
    0x00, 0x12, 0x00, 0x00
};
// zig fmt: on

fn handshake_record_length(reader: anytype) !usize {
    return try record_length(0x16, reader);
}

// Assumes a sha256 reader
fn record_length(t: u8, reader: anytype) !usize {
    try check_record_type(t, reader);
    var record_header: [4]u8 = undefined;
    try reader.readNoEof(&record_header);
    if (!mem.eql(u8, record_header[0..2], "\x03\x03") and !mem.eql(u8, record_header[0..2], "\x03\x01"))
        return error.ServerInvalidVersion;
    return mem.readIntSliceBig(u16, record_header[2..4]);
}

pub const ServerAlert = error{
    AlertCloseNotify,
    AlertUnexpectedMessage,
    AlertBadRecordMAC,
    AlertDecryptionFailed,
    AlertRecordOverflow,
    AlertDecompressionFailure,
    AlertHandshakeFailure,
    AlertNoCertificate,
    AlertBadCertificate,
    AlertUnsupportedCertificate,
    AlertCertificateRevoked,
    AlertCertificateExpired,
    AlertCertificateUnknown,
    AlertIllegalParameter,
    AlertUnknownCA,
    AlertAccessDenied,
    AlertDecodeError,
    AlertDecryptError,
    AlertExportRestriction,
    AlertProtocolVersion,
    AlertInsufficientSecurity,
    AlertInternalError,
    AlertUserCanceled,
    AlertNoRenegotiation,
    AlertUnsupportedExtension,
};

fn check_record_type(
    expected: u8,
    reader: anytype,
) (@TypeOf(reader).Error || ServerAlert || error{ ServerMalformedResponse, EndOfStream })!void {
    const record_type = try reader.readByte();
    // Alert
    if (record_type == 0x15) {
        // Skip SSL version, length of record
        try reader.skipBytes(4, .{});

        const severity = try reader.readByte();
        const err_num = try reader.readByte();
        return switch (err_num) {
            0 => error.AlertCloseNotify,
            10 => error.AlertUnexpectedMessage,
            20 => error.AlertBadRecordMAC,
            21 => error.AlertDecryptionFailed,
            22 => error.AlertRecordOverflow,
            30 => error.AlertDecompressionFailure,
            40 => error.AlertHandshakeFailure,
            41 => error.AlertNoCertificate,
            42 => error.AlertBadCertificate,
            43 => error.AlertUnsupportedCertificate,
            44 => error.AlertCertificateRevoked,
            45 => error.AlertCertificateExpired,
            46 => error.AlertCertificateUnknown,
            47 => error.AlertIllegalParameter,
            48 => error.AlertUnknownCA,
            49 => error.AlertAccessDenied,
            50 => error.AlertDecodeError,
            51 => error.AlertDecryptError,
            60 => error.AlertExportRestriction,
            70 => error.AlertProtocolVersion,
            71 => error.AlertInsufficientSecurity,
            80 => error.AlertInternalError,
            90 => error.AlertUserCanceled,
            100 => error.AlertNoRenegotiation,
            110 => error.AlertUnsupportedExtension,
            else => error.ServerMalformedResponse,
        };
    }
    if (record_type != expected)
        return error.ServerMalformedResponse;
}

fn Sha256Reader(comptime Reader: anytype) type {
    const State = struct {
        sha256: *Sha256,
        reader: Reader,
    };
    const S = struct {
        pub fn read(state: State, buffer: []u8) Reader.Error!usize {
            const amt = try state.reader.read(buffer);
            if (amt != 0) {
                state.sha256.update(buffer[0..amt]);
            }
            return amt;
        }
    };
    return std.io.Reader(State, Reader.Error, S.read);
}

fn sha256_reader(sha256: *Sha256, reader: anytype) Sha256Reader(@TypeOf(reader)) {
    return .{ .context = .{ .sha256 = sha256, .reader = reader } };
}

fn Sha256Writer(comptime Writer: anytype) type {
    const State = struct {
        sha256: *Sha256,
        writer: Writer,
    };
    const S = struct {
        pub fn write(state: State, buffer: []const u8) Writer.Error!usize {
            const amt = try state.writer.write(buffer);
            if (amt != 0) {
                state.sha256.update(buffer[0..amt]);
            }
            return amt;
        }
    };
    return std.io.Writer(State, Writer.Error, S.write);
}

fn sha256_writer(sha256: *Sha256, writer: anytype) Sha256Writer(@TypeOf(writer)) {
    return .{ .context = .{ .sha256 = sha256, .writer = writer } };
}

fn CertificateReaderState(comptime Reader: type) type {
    return struct {
        reader: Reader,
        length: usize,
        idx: usize = 0,
    };
}

fn CertificateReader(comptime Reader: type) type {
    const S = struct {
        pub fn read(state: *CertificateReaderState(Reader), buffer: []u8) Reader.Error!usize {
            const out_bytes = std.math.min(buffer.len, state.length - state.idx);
            const res = try state.reader.readAll(buffer[0..out_bytes]);
            state.idx += res;
            return res;
        }
    };

    return std.io.Reader(*CertificateReaderState(Reader), Reader.Error, S.read);
}

pub const CertificateVerifier = union(enum) {
    none,
    function: anytype,
};

pub fn CertificateVerifierReader(comptime Reader: type) type {
    return CertificateReader(Sha256Reader(Reader));
}

pub const HandshakeOptions = mixtime(.{
    .{ "rand", .runtime, ?*std.rand.Random },
    .{ "reader", .runtime },
    .{ "writer", .runtime },
    .{ "cert_verifier", .compiletime, CertificateVerifier },
    // @TODO Things like supported cipher suites, compression methods, extensions as comptime here?
    // @TODO Comptime slice of supported cipher suites, generate the handshake accordingly at comptime.
});

pub fn ClientConnectError(comptime verifier: CertificateVerifier, comptime Reader: type, comptime Writer: type) type {
    const Additional = error{
        ServerInvalidVersion,
        ServerMalformedResponse,
        EndOfStream,
        ServerInvalidCipherSuite,
        ServerInvalidCompressionMethod,
        ServerInvalidRenegotiationData,
        ServerInvalidECPointCompression,
        ServerInvalidExtension,
        ServerInvalidCurve,
        ServerInvalidSignature,
        X25519KeyPairCreateFailed,
        X25519MultFailed,
        ServerAuthenticationFailed,
        ServerInvalidVerifyData,
    };
    const err_msg = "Certificate verifier function cannot be generic, use CertificateVerifierReader to get the reader argument type";
    return Reader.Error || Writer.Error || ServerAlert || Additional || switch (verifier) {
        .none => error{},
        .function => |f| @typeInfo(@typeInfo(@TypeOf(f)).Fn.return_type orelse
            @compileError(err_msg)).ErrorUnion.error_set || error{CertificateVerificationFailed},
    };
}

pub fn client_connect(
    opt_tup: anytype,
    hostname: []const u8,
) ClientConnectError(
    opt_tup.cert_verifier,
    @TypeOf(opt_tup.reader),
    @TypeOf(opt_tup.writer),
)!Client(@TypeOf(opt_tup.reader), @TypeOf(opt_tup.writer)) {
    const options = HandshakeOptions.make(opt_tup);

    var handshake_record_hash = Sha256.init(.{});
    const reader = options.reader;
    const writer = options.writer;
    const hashing_reader = sha256_reader(&handshake_record_hash, reader);
    const hashing_writer = sha256_writer(&handshake_record_hash, writer);

    var client_random: [32]u8 = undefined;
    const rand = options.rand orelse std.crypto.random;
    rand.bytes(&client_random);

    var server_random: [32]u8 = undefined;

    {
        var msg_buf = client_hello_start;
        mem.writeIntBig(u16, msg_buf[3..5], @intCast(u16, hostname.len + 0x5D));
        mem.writeIntBig(u24, msg_buf[6..9], @intCast(u24, hostname.len + 0x59));
        mem.copy(u8, msg_buf[11..43], &client_random);
        mem.writeIntBig(u16, msg_buf[50..52], @intCast(u16, hostname.len + 0x2E));
        mem.writeIntBig(u16, msg_buf[54..56], @intCast(u16, hostname.len + 5));
        mem.writeIntBig(u16, msg_buf[56..58], @intCast(u16, hostname.len + 3));
        mem.writeIntBig(u16, msg_buf[59..61], @intCast(u16, hostname.len));
        try writer.writeAll(msg_buf[0..5]);
        try hashing_writer.writeAll(msg_buf[5..]);
    }
    try hashing_writer.writeAll(hostname);
    try hashing_writer.writeAll(&client_hello_end);

    // Read server hello
    {
        const length = try handshake_record_length(reader);
        if (length < 44)
            return error.ServerMalformedResponse;
        {
            var hs_hdr_and_server_ver: [6]u8 = undefined;
            try hashing_reader.readNoEof(&hs_hdr_and_server_ver);
            if (hs_hdr_and_server_ver[0] != 0x02)
                return error.ServerMalformedResponse;
            if (!mem.eql(u8, hs_hdr_and_server_ver[4..6], "\x03\x03"))
                return error.ServerInvalidVersion;
        }
        try hashing_reader.readNoEof(&server_random);

        // Just skip the session id for now
        const sess_id_len = try hashing_reader.readByte();
        if (sess_id_len != 0)
            try hashing_reader.skipBytes(sess_id_len, .{});

        // TODO: More cipher suites
        if (!try hashing_reader.isBytes("\xCC\xA8"))
            return error.ServerInvalidCipherSuite;

        // Compression method
        if ((try hashing_reader.readByte()) != 0x00)
            return error.ServerInvalidCompressionMethod;

        const exts_length = try hashing_reader.readIntBig(u16);
        var ext_byte_idx: usize = 0;
        while (ext_byte_idx < exts_length) {
            var ext_tag: [2]u8 = undefined;
            try hashing_reader.readNoEof(&ext_tag);

            const ext_len = try hashing_reader.readIntBig(u16);
            ext_byte_idx += 4 + ext_len;
            if (ext_tag[0] == 0xFF and ext_tag[1] == 0x01) {
                // Renegotiation info
                const renegotiation_info = try hashing_reader.readByte();
                if (ext_len != 0x01 or renegotiation_info != 0x00)
                    return error.ServerInvalidRenegotiationData;
            } else if (ext_tag[0] == 0x00 and ext_tag[1] == 0x00) {
                // Server name
                if (ext_len != 0)
                    try hashing_reader.skipBytes(ext_len, .{});
            } else if (ext_tag[0] == 0x00 and ext_tag[1] == 0x0B) {
                const format_count = try hashing_reader.readByte();
                var found_uncompressed = false;
                var i: usize = 0;
                while (i < format_count) : (i += 1) {
                    const byte = try hashing_reader.readByte();
                    if (byte == 0x0)
                        found_uncompressed = true;
                }
                if (!found_uncompressed)
                    return error.ServerInvalidECPointCompression;
            } else return error.ServerInvalidExtension;
        }
        if (ext_byte_idx != exts_length)
            return error.ServerMalformedResponse;
    }
    // Read server certificates
    {
        const length = try handshake_record_length(reader);
        {
            var handshake_header: [4]u8 = undefined;
            try hashing_reader.readNoEof(&handshake_header);
            if (handshake_header[0] != 0x0b)
                return error.ServerMalformedResponse;
        }
        const certs_length = try hashing_reader.readIntBig(u24);
        switch (options.cert_verifier) {
            .none => try hashing_reader.skipBytes(certs_length, .{}),
            .function => |f| {
                var reader_state = CertificateReaderState(@TypeOf(hashing_reader)){
                    .reader = hashing_reader,
                    .length = certs_length,
                };
                var cert_reader = CertificateReader(@TypeOf(hashing_reader)){ .context = &reader_state };
                if (!try f(cert_reader))
                    return error.CertificateVerificationFailed;
                try hashing_reader.skipBytes(reader_state.length - reader_state.idx, .{});
            },
        }
    }
    // Read server ephemeral public key
    var server_public_key: [32]u8 = undefined;
    {
        const length = try handshake_record_length(reader);
        {
            var handshake_header: [4]u8 = undefined;
            try hashing_reader.readNoEof(&handshake_header);
            if (handshake_header[0] != 0x0c)
                return error.ServerMalformedResponse;

            // Only x25519 supported for now.
            if (!try hashing_reader.isBytes("\x03\x00\x1D"))
                return error.ServerInvalidCurve;
        }

        const pub_key_len = try hashing_reader.readByte();
        if (pub_key_len != 32)
            return error.ServerMalformedResponse;

        try hashing_reader.readNoEof(&server_public_key);

        // Signed public key
        const signature_id = try hashing_reader.readIntBig(u16);
        const signature_len = try hashing_reader.readIntBig(u16);
        switch (signature_id) {
            // RSA/PKCS1/SHA256
            0x0401 => {
                if (signature_len != 256)
                    return error.ServerMalformedResponse;
            },
            // ECDSA/SECP256r1/SHA256
            0x0403 => {
                if (signature_len != 256)
                    return error.ServerMalformedResponse;
            },
            // RSA/PKCS1/SHA512
            0x0601 => {
                if (signature_len != 512)
                    return error.ServerMalformedResponse;
            },
            // ECDSA/SECP521r1/SHA512
            0x0602 => {
                if (signature_len != 512)
                    return error.ServerMalformedResponse;
            },
            else => return error.ServerInvalidSignature,
        }
        // TODO Verify the signature
        try hashing_reader.skipBytes(signature_len, .{});
    }
    // Read server hello done
    {
        const length = try handshake_record_length(reader);
        const is_bytes = try hashing_reader.isBytes("\x0e\x00\x00\x00");
        if (length != 4 or !is_bytes)
            return error.ServerMalformedResponse;
    }

    // Generate keys for the session
    var client_key_pair_seed: [32]u8 = undefined;
    rand.bytes(&client_key_pair_seed);
    const client_key_pair = std.crypto.dh.X25519.KeyPair.create(client_key_pair_seed) catch
        return error.X25519KeyPairCreateFailed;
    {
        // Client key exchange
        try writer.writeAll(&[5]u8{ 0x16, 0x03, 0x03, 0x00, 0x25 });
        try hashing_writer.writeAll(&[5]u8{ 0x10, 0x00, 0x00, 0x21, 0x20 });
        try hashing_writer.writeAll(&client_key_pair.public_key);
    }
    // Client encryption keys calculation for ECDHE_RSA cipher suites with SHA256 hash
    var master_secret: [48]u8 = undefined;
    // No MAC keys for CHACHA20POLY1305
    var client_key: [32]u8 = undefined;
    var server_key: [32]u8 = undefined;
    var client_iv: [12]u8 = undefined;
    var server_iv: [12]u8 = undefined;
    {
        const pre_master_secret = std.crypto.dh.X25519.scalarmult(client_key_pair.secret_key, server_public_key) catch
            return error.X25519MultFailed;

        var seed: [77]u8 = undefined;
        seed[0..13].* = "master secret".*;
        seed[13..45].* = client_random;
        seed[45..77].* = server_random;

        var a1: [32 + seed.len]u8 = undefined;
        Hmac256.create(a1[0..32], &seed, &pre_master_secret);
        var a2: [32 + seed.len]u8 = undefined;
        Hmac256.create(a2[0..32], a1[0..32], &pre_master_secret);

        a1[32..].* = seed;
        a2[32..].* = seed;

        var p1: [32]u8 = undefined;
        Hmac256.create(&p1, &a1, &pre_master_secret);
        var p2: [32]u8 = undefined;
        Hmac256.create(&p2, &a2, &pre_master_secret);

        master_secret[0..32].* = p1;
        master_secret[32..48].* = p2[0..16].*;

        // Key expansion
        seed[0..13].* = "key expansion".*;
        seed[13..45].* = server_random;
        seed[45..77].* = client_random;
        a1[32..].* = seed;
        a2[32..].* = seed;
        // client write key: 32 bytes
        // server write key: 32 bytes
        // client write IV: 12 bytes
        // server write IV: 12 bytes
        // TOTAL: 88 bytes
        // We generate 32 bytes of data at a time, so we need 3 rounds for 96 bytes.
        // Execute two rounds
        Hmac256.create(a1[0..32], &seed, &master_secret);
        Hmac256.create(a2[0..32], a1[0..32], &master_secret);
        Hmac256.create(&p1, &a1, &master_secret);
        Hmac256.create(&p2, &a2, &master_secret);
        client_key = p1;
        server_key = p2;
        // Last round
        Hmac256.create(a1[0..32], a2[0..32], &master_secret);
        Hmac256.create(&p1, &a1, &master_secret);
        client_iv = p1[0..12].*;
        server_iv = p1[12..24].*;
    }

    // Client change cipher spec and client handshake finished
    {
        // https://tools.ietf.org/id/draft-mavrogiannopoulos-chacha-tls-03.html

        // The message we need to encrypt is the following:
        // 0x14 0x00 0x00 0x0c
        // <12 bytes of verify_data>
        // seed = "client finished" + SHA256(all handshake messages)
        // a1 = HMAC-SHA256(key=MasterSecret, data=seed)
        // p1 = HMAC-SHA256(key=MasterSecret, data=a1 + seed)
        // verify_data = p1[0..12]
        var verify_message: [16]u8 = undefined;
        verify_message[0..4].* = "\x14\x00\x00\x0C".*;
        {
            var seed: [47]u8 = undefined;
            seed[0..15].* = "client finished".*;
            // We still need to update the hash one time, so we copy
            // to get the current digest here.
            var hash_copy = handshake_record_hash;
            hash_copy.final(seed[15..47]);

            var a1: [32 + seed.len]u8 = undefined;
            Hmac256.create(a1[0..32], &seed, &master_secret);
            a1[32..].* = seed;
            var p1: [32]u8 = undefined;
            Hmac256.create(&p1, &a1, &master_secret);
            verify_message[4..16].* = p1[0..12].*;
        }
        handshake_record_hash.update(&verify_message);

        // Encypt the message!
        var nonce: [12]u8 = client_iv;
        var additional_data: [13]u8 = undefined;
        mem.writeIntBig(u64, additional_data[0..8], 0);
        additional_data[8..13].* = [5]u8{ 0x16, 0x03, 0x03, 0x00, 0x10 };

        var encrypted: [32]u8 = undefined;
        Chacha20Poly1305.encrypt(
            encrypted[0..16],
            encrypted[16..],
            &verify_message,
            &additional_data,
            nonce,
            client_key,
        );

        try writer.writeAll(&[11]u8{
            // Client change cipher spec
            0x14, 0x03, 0x03,
            0x00, 0x01, 0x01,
            // Verify data
            0x16, 0x03, 0x03,
            0x00, 0x20,
        });
        try writer.writeAll(&encrypted);
    }

    // Server change cipher spec
    {
        const length = try record_length(0x14, reader);
        const next_byte = try reader.readByte();
        if (length != 1 or next_byte != 0x01)
            return error.ServerMalformedResponse;
    }
    // Server handshake finished
    {
        const length = try handshake_record_length(reader);

        if (length != 32)
            return error.ServerMalformedResponse;

        var msg_in: [32]u8 = undefined;
        try reader.readNoEof(&msg_in);

        var decrypted: [16]u8 = undefined;
        const nonce: [12]u8 = server_iv;
        var additional_data: [13]u8 = undefined;
        mem.writeIntBig(u64, additional_data[0..8], 0);
        additional_data[8..13].* = [5]u8{ 0x16, 0x03, 0x03, 0x00, 0x10 };

        Chacha20Poly1305.decrypt(
            &decrypted,
            msg_in[0..16],
            msg_in[16..].*,
            &additional_data,
            nonce,
            server_key,
        ) catch return error.ServerAuthenticationFailed;

        var verify_message: [16]u8 = undefined;
        verify_message[0..4].* = "\x14\x00\x00\x0C".*;
        {
            var seed: [47]u8 = undefined;
            seed[0..15].* = "server finished".*;
            handshake_record_hash.final(seed[15..47]);
            var a1: [32 + seed.len]u8 = undefined;
            Hmac256.create(a1[0..32], &seed, &master_secret);
            a1[32..].* = seed;
            var p1: [32]u8 = undefined;
            Hmac256.create(&p1, &a1, &master_secret);
            verify_message[4..16].* = p1[0..12].*;
        }
        if (!mem.eql(u8, &decrypted, &verify_message))
            return error.ServerInvalidVerifyData;
    }

    return Client(@TypeOf(reader), @TypeOf(writer)){
        .client_key = client_key,
        .server_key = server_key,
        .client_iv = client_iv,
        .server_iv = server_iv,
        .parent_reader = reader,
        .parent_writer = writer,
    };
}

// @TODO Split into another file

// TODO See stdlib, this is a modified non vectorized implementation
const ChaCha20Stream = struct {
    const math = std.math;
    const BlockVec = [16]u32;

    fn initContext(key: [8]u32, d: [4]u32) BlockVec {
        const c = "expand 32-byte k";
        const constant_le = comptime [4]u32{
            mem.readIntLittle(u32, c[0..4]),
            mem.readIntLittle(u32, c[4..8]),
            mem.readIntLittle(u32, c[8..12]),
            mem.readIntLittle(u32, c[12..16]),
        };
        return BlockVec{
            constant_le[0], constant_le[1], constant_le[2], constant_le[3],
            key[0],         key[1],         key[2],         key[3],
            key[4],         key[5],         key[6],         key[7],
            d[0],           d[1],           d[2],           d[3],
        };
    }

    const QuarterRound = struct {
        a: usize,
        b: usize,
        c: usize,
        d: usize,
    };

    fn Rp(a: usize, b: usize, c: usize, d: usize) QuarterRound {
        return QuarterRound{
            .a = a,
            .b = b,
            .c = c,
            .d = d,
        };
    }

    inline fn chacha20Core(x: *BlockVec, input: BlockVec) void {
        x.* = input;

        const rounds = comptime [_]QuarterRound{
            Rp(0, 4, 8, 12),
            Rp(1, 5, 9, 13),
            Rp(2, 6, 10, 14),
            Rp(3, 7, 11, 15),
            Rp(0, 5, 10, 15),
            Rp(1, 6, 11, 12),
            Rp(2, 7, 8, 13),
            Rp(3, 4, 9, 14),
        };

        comptime var j: usize = 0;
        inline while (j < 20) : (j += 2) {
            inline for (rounds) |r| {
                x[r.a] +%= x[r.b];
                x[r.d] = math.rotl(u32, x[r.d] ^ x[r.a], @as(u32, 16));
                x[r.c] +%= x[r.d];
                x[r.b] = math.rotl(u32, x[r.b] ^ x[r.c], @as(u32, 12));
                x[r.a] +%= x[r.b];
                x[r.d] = math.rotl(u32, x[r.d] ^ x[r.a], @as(u32, 8));
                x[r.c] +%= x[r.d];
                x[r.b] = math.rotl(u32, x[r.b] ^ x[r.c], @as(u32, 7));
            }
        }
    }

    inline fn hashToBytes(out: *[64]u8, x: BlockVec) void {
        var i: usize = 0;
        while (i < 4) : (i += 1) {
            mem.writeIntLittle(u32, out[16 * i + 0 ..][0..4], x[i * 4 + 0]);
            mem.writeIntLittle(u32, out[16 * i + 4 ..][0..4], x[i * 4 + 1]);
            mem.writeIntLittle(u32, out[16 * i + 8 ..][0..4], x[i * 4 + 2]);
            mem.writeIntLittle(u32, out[16 * i + 12 ..][0..4], x[i * 4 + 3]);
        }
    }

    inline fn contextFeedback(x: *BlockVec, ctx: BlockVec) void {
        var i: usize = 0;
        while (i < 16) : (i += 1) {
            x[i] +%= ctx[i];
        }
    }

    // TODO: Optimize this
    fn chacha20Xor(out: []u8, in: []const u8, key: [8]u32, ctx: *BlockVec, idx: *usize, buf: *[64]u8) void {
        var x: BlockVec = undefined;

        const start_idx = idx.*;
        var i: usize = 0;
        while (i < in.len) {
            if (idx.* % 64 == 0) {
                if (idx.* != 0) {
                    ctx.*[12] += 1;
                }
                chacha20Core(x[0..], ctx.*);
                contextFeedback(&x, ctx.*);
                hashToBytes(buf, x);
            }

            out[i] = in[i] ^ buf[idx.* % 64];

            i += 1;
            idx.* += 1;
        }
    }
};

fn keyToWords(key: [32]u8) [8]u32 {
    var k: [8]u32 = undefined;
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        k[i] = mem.readIntLittle(u32, key[i * 4 ..][0..4]);
    }
    return k;
}

pub fn Client(comptime _Reader: type, comptime _Writer: type) type {
    return struct {
        // @TODO Pass this in HandshakeOptions with this as a default.
        const internal_buffer_size = 4 * 1024;
        const ReaderError = _Reader.Error || ServerAlert || error{ ServerMalformedResponse, ServerInvalidVersion };
        pub const Reader = std.io.Reader(*@This(), ReaderError, read);
        pub const Writer = std.io.Writer(*@This(), _Writer.Error, write);

        client_seq: u64 = 1,
        server_seq: u64 = 1,
        server_iv: [12]u8,
        client_iv: [12]u8,
        client_key: [32]u8,
        server_key: [32]u8,

        parent_reader: _Reader,
        parent_writer: _Writer,

        reader_state: union(enum) {
            in_record: struct {
                left: usize,
                context: ChaCha20Stream.BlockVec,
                idx: usize,
                buf: [64]u8,
            },
            none,
        } = .none,

        pub fn reader(self: *@This()) Reader {
            return .{ .context = self };
        }

        pub fn writer(self: *@This()) Writer {
            return .{ .context = self };
        }

        pub fn read(self: *@This(), buffer: []u8) ReaderError!usize {
            switch (self.reader_state) {
                .none => {
                    const len = (record_length(0x17, self.parent_reader) catch |err| switch (err) {
                        error.EndOfStream => return 0,
                        else => |e| return e,
                    }) - 16;

                    const curr_bytes = std.math.min(std.math.min(len, internal_buffer_size), buffer.len);

                    var nonce: [12]u8 = undefined;
                    nonce[0..4].* = mem.zeroes([4]u8);
                    mem.writeIntBig(u64, nonce[4..12], self.server_seq);
                    for (nonce) |*n, i| {
                        n.* ^= self.server_iv[i];
                    }

                    // Partially decrypt the data.
                    var encrypted: [internal_buffer_size]u8 = undefined;
                    const actually_read = try self.parent_reader.read(encrypted[0..curr_bytes]);

                    var c: [4]u32 = undefined;
                    c[0] = 1;
                    c[1] = mem.readIntLittle(u32, nonce[0..4]);
                    c[2] = mem.readIntLittle(u32, nonce[4..8]);
                    c[3] = mem.readIntLittle(u32, nonce[8..12]);
                    const server_key = keyToWords(self.server_key);
                    var context = ChaCha20Stream.initContext(server_key, c);
                    var idx: usize = 0;
                    var buf: [64]u8 = undefined;
                    ChaCha20Stream.chacha20Xor(
                        buffer[0..actually_read],
                        encrypted[0..actually_read],
                        server_key,
                        &context,
                        &idx,
                        &buf,
                    );
                    if (actually_read < len) {
                        self.reader_state = .{
                            .in_record = .{
                                .left = len - actually_read,
                                .context = context,
                                .idx = idx,
                                .buf = buf,
                            },
                        };
                    } else {
                        // @TODO Verify Poly1305.
                        self.parent_reader.skipBytes(16, .{}) catch |err| switch (err) {
                            error.EndOfStream => return 0,
                            else => |e| return e,
                        };
                        self.server_seq += 1;
                    }
                    return actually_read;
                },
                .in_record => |*record_info| {
                    const curr_bytes = std.math.min(std.math.min(internal_buffer_size, buffer.len), record_info.left);
                    // Partially decrypt the data.
                    var encrypted: [internal_buffer_size]u8 = undefined;
                    const actually_read = try self.parent_reader.read(encrypted[0..curr_bytes]);
                    ChaCha20Stream.chacha20Xor(
                        buffer[0..actually_read],
                        encrypted[0..actually_read],
                        keyToWords(self.server_key),
                        &record_info.context,
                        &record_info.idx,
                        &record_info.buf,
                    );

                    record_info.left -= actually_read;
                    if (record_info.left == 0) {
                        // @TODO Verify Poly1305.
                        self.parent_reader.skipBytes(16, .{}) catch |err| switch (err) {
                            error.EndOfStream => return 0,
                            else => |e| return e,
                        };
                        self.reader_state = .none;
                        self.server_seq += 1;
                    }
                    return actually_read;
                },
            }
        }

        pub fn write(self: *@This(), buffer: []const u8) _Writer.Error!usize {
            if (buffer.len == 0) return 0;

            const curr_bytes = @truncate(u16, std.math.min(buffer.len, internal_buffer_size));
            var encrypted_data: [internal_buffer_size]u8 = undefined;
            var tag_data: [16]u8 = undefined;

            try self.parent_writer.writeAll(&[3]u8{ 0x17, 0x03, 0x03 });
            try self.parent_writer.writeIntBig(u16, curr_bytes + 16);

            var nonce: [12]u8 = undefined;
            nonce[0..4].* = mem.zeroes([4]u8);
            mem.writeIntBig(u64, nonce[4..12], self.client_seq);
            for (nonce) |*n, i| {
                n.* ^= self.client_iv[i];
            }

            var additional_data: [13]u8 = undefined;
            mem.writeIntBig(u64, additional_data[0..8], self.client_seq);
            additional_data[8..11].* = [3]u8{ 0x17, 0x03, 0x03 };
            mem.writeIntBig(u16, additional_data[11..], curr_bytes);

            Chacha20Poly1305.encrypt(
                encrypted_data[0..curr_bytes],
                &tag_data,
                buffer[0..curr_bytes],
                &additional_data,
                nonce,
                self.client_key,
            );
            try self.parent_writer.writeAll(encrypted_data[0..curr_bytes]);
            try self.parent_writer.writeAll(&tag_data);

            self.client_seq += 1;
            return curr_bytes;
        }

        pub fn close_notify(self: *@This()) !void {
            try self.writer().writeAll(&[5]u8{
                0x15, 0x03, 0x03, 0x00, 0x12,
            });

            var encrypted_data: [2]u8 = undefined;
            var tag_data: [16]u8 = undefined;
            var nonce: [12]u8 = undefined;

            nonce[0..4].* = mem.zeroes([4]u8);
            mem.writeIntBig(u64, nonce[4..12], self.client_seq);
            for (nonce) |*n, i| {
                n.* ^= self.client_iv[i];
            }

            var additional_data: [13]u8 = undefined;
            mem.writeIntBig(u64, additional_data[0..8], self.client_seq);
            additional_data[8..13].* = [5]u8{ 0x15, 0x03, 0x03, 0x00, 0x02 };

            Chacha20Poly1305.encrypt(
                &encrypted_data,
                &tag_data,
                "\x01\x00",
                &additional_data,
                nonce,
                self.client_key,
            );
            self.client_seq += 1;
        }
    };
}

test "Dummy" {
    const sock = try std.net.tcpConnectToHost(std.testing.allocator, "en.wikipedia.org", 443);
    defer sock.close();

    var client = try client_connect(.{
        .rand = null,
        .reader = sock.reader(),
        .writer = sock.writer(),
        .cert_verifier = .none,
    }, "en.wikipedia.org");
    defer client.close_notify() catch {};

    try client.writer().writeAll("GET /wiki/Main_Page HTTP/1.1\r\nHost: en.wikipedia.org\r\nAccept: */*\r\n\r\n");

    // Check some headers are read correctly.
    {
        const header = try client.reader().readUntilDelimiterAlloc(std.testing.allocator, '\n', std.math.maxInt(usize));
        std.testing.expectEqualStrings("HTTP/1.1 200 OK", mem.trim(u8, header, &std.ascii.spaces));
        std.testing.allocator.free(header);
    }

    {
        const header = try client.reader().readUntilDelimiterAlloc(std.testing.allocator, '\n', std.math.maxInt(usize));
        std.testing.allocator.free(header);
    }

    {
        const header = try client.reader().readUntilDelimiterAlloc(std.testing.allocator, '\n', std.math.maxInt(usize));
        std.testing.expect(mem.endsWith(u8, mem.trim(u8, header, &std.ascii.spaces), ".eqiad.wmnet"));
        std.testing.allocator.free(header);
    }

    {
        const header = try client.reader().readUntilDelimiterAlloc(std.testing.allocator, '\n', std.math.maxInt(usize));
        std.testing.expectEqualStrings("X-Content-Type-Options: nosniff", mem.trim(u8, header, &std.ascii.spaces));
        std.testing.allocator.free(header);
    }

    {
        const header = try client.reader().readUntilDelimiterAlloc(std.testing.allocator, '\n', std.math.maxInt(usize));
        std.testing.expectEqualStrings("P3p: CP=\"See https://en.wikipedia.org/wiki/Special:CentralAutoLogin/P3P for more info.\"", mem.trim(u8, header, &std.ascii.spaces));
        std.testing.allocator.free(header);
    }

    // Skip the rest of the headers expect for Content-Length
    var content_length: ?usize = null;
    hdr_loop: while (true) {
        const header = try client.reader().readUntilDelimiterAlloc(std.testing.allocator, '\n', std.math.maxInt(usize));
        defer std.testing.allocator.free(header);

        const hdr_contents = mem.trim(u8, header, &std.ascii.spaces);
        if (hdr_contents.len == 0) {
            break :hdr_loop;
        }

        if (mem.startsWith(u8, hdr_contents, "Content-Length: ")) {
            content_length = try std.fmt.parseUnsigned(usize, hdr_contents[16..], 10);
        }
    }
    std.testing.expect(content_length != null);
    const html_contents = try std.testing.allocator.alloc(u8, content_length.?);
    defer std.testing.allocator.free(html_contents);

    try client.reader().readNoEof(html_contents);
}
