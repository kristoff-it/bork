const std = @import("std");
const ascii = @import("../../ascii.zig");

pub const Currency = @import("../../components.zig").Currency;
pub const Math = @import("../../components.zig").Math;
pub const ModifierSymbol = @import("../../components.zig").ModifierSymbol;
pub const OtherSymbol = @import("../../components.zig").OtherSymbol;

const Self = @This();

currency: Currency,
math: Math,
modifier_symbol: ModifierSymbol,
other_symbol: OtherSymbol,

pub fn new() Self {
    return Self{
        .currency = Currency{},
        .math = Math{},
        .modifier_symbol = ModifierSymbol{},
        .other_symbol = OtherSymbol{},
    };
}

// isSymbol detects symbols which curiosly may include some code points commonly thought of as
// punctuation.
pub fn isSymbol(self: Self, cp: u21) bool {
    return self.math.isMathSymbol(cp) or self.modifier_symbol.isModifierSymbol(cp) or
        self.currency.isCurrencySymbol(cp) or self.other_symbol.isOtherSymbol(cp);
}

/// isAsciiSymbol detects ASCII only symbols.
pub fn isAsciiSymbol(cp: u21) bool {
    return if (cp < 128) ascii.isSymbol(@intCast(u8, cp)) else false;
}

const expect = std.testing.expect;

test "Component isSymbol" {
    var symbol = new();

    expect(symbol.isSymbol('<'));
    expect(symbol.isSymbol('>'));
    expect(symbol.isSymbol('='));
    expect(symbol.isSymbol('$'));
    expect(symbol.isSymbol('^'));
    expect(symbol.isSymbol('+'));
    expect(symbol.isSymbol('|'));
    expect(!symbol.isSymbol('A'));
    expect(!symbol.isSymbol('?'));
}
