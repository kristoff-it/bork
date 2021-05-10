const std = @import("std");
const ascii = @import("../../ascii.zig");

pub const Close = @import("../../components.zig").Close;
pub const Connector = @import("../../components.zig").Connector;
pub const Dash = @import("../../components.zig").Dash;
pub const Final = @import("../../components.zig").Final;
pub const Initial = @import("../../components.zig").Initial;
pub const Open = @import("../../components.zig").Open;
pub const OtherPunct = @import("../../components.zig").OtherPunct;

const Self = @This();

close: Close,
connector: Connector,
dash: Dash,
final: Final,
initial: Initial,
open: Open,
other_punct: OtherPunct,

pub fn new() Self {
    return Self{
        .close = Close{},
        .connector = Connector{},
        .dash = Dash{},
        .final = Final{},
        .initial = Initial{},
        .open = Open{},
        .other_punct = OtherPunct{},
    };
}

/// isPunct detects punctuation characters. Note some punctuation maybe considered symbols by Unicode.
pub fn isPunct(self: Self, cp: u21) bool {
    return self.close.isClosePunctuation(cp) or self.connector.isConnectorPunctuation(cp) or
        self.dash.isDashPunctuation(cp) or self.final.isFinalPunctuation(cp) or
        self.initial.isInitialPunctuation(cp) or self.open.isOpenPunctuation(cp) or
        self.other_punct.isOtherPunctuation(cp);
}

/// isAsciiPunct detects ASCII only punctuation.
pub fn isAsciiPunct(cp: u21) bool {
    return if (cp < 128) ascii.isPunct(@intCast(u8, cp)) else false;
}

const expect = std.testing.expect;

test "Component isPunct" {
    var punct = new();

    expect(punct.isPunct('!'));
    expect(punct.isPunct('?'));
    expect(punct.isPunct(','));
    expect(punct.isPunct('.'));
    expect(punct.isPunct(':'));
    expect(punct.isPunct(';'));
    expect(punct.isPunct('\''));
    expect(punct.isPunct('"'));
    expect(punct.isPunct('¿'));
    expect(punct.isPunct('¡'));
    expect(punct.isPunct('-'));
    expect(punct.isPunct('('));
    expect(punct.isPunct(')'));
    expect(punct.isPunct('{'));
    expect(punct.isPunct('}'));
    expect(punct.isPunct('–'));
    // Punct? in Unicode.
    expect(punct.isPunct('@'));
    expect(punct.isPunct('#'));
    expect(punct.isPunct('%'));
    expect(punct.isPunct('&'));
    expect(punct.isPunct('*'));
    expect(punct.isPunct('_'));
    expect(punct.isPunct('/'));
    expect(punct.isPunct('\\'));
    expect(!punct.isPunct('\u{0003}'));
}
