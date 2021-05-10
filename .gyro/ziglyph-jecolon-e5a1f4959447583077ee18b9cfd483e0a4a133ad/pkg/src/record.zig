pub const Record = union(enum) {
    single: u21,
    range: Range,

    pub fn match(self: Record, cp: u21) bool {
        return switch (self) {
            .single => |rcp| cp == rcp,
            .range => |r| r.match(cp),
        };
    }
};

pub const Range = struct {
    lo: u21,
    hi: u21,

    pub fn match(self: Range, cp: u21) bool {
        return cp >= self.lo and cp <= self.hi;
    }
};
