const Terminal = @import("render/Terminal.zig");
const network = @import("network.zig");

pub const Event = union(enum) {
    display: Terminal.Event,
    network: network.Event,
    resize: void,
};
