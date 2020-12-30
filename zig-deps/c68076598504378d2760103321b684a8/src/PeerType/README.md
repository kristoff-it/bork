# PeerType

## API
```zig
/// types must be an iterable of types (tuple, slice, ptr to array)
pub fn PeerType(comptime types: anytype) ?type;
pub fn coercesTo(comptime dst: type, comptime src: type) bool;
pub fn requiresComptime(comptime T: type) bool;
```

## License
MIT
