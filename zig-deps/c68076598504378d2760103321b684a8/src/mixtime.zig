usingnamespace @import("PeerType/PeerType.zig");
const std = @import("std");

fn MixtimeType(comptime description: anytype, comptime Tuple: type) type {
    const Context = enum { compiletime, runtime };
    const StructField = std.builtin.TypeInfo.StructField;
    const tuple_fields = std.meta.fields(Tuple);
    var struct_field_data: [tuple_fields.len]StructField = undefined;

    var extra_error_msg: []const u8 = "Extraneous fields:\n";
    var extra_fields = false;

    for (tuple_fields) |field, tuple_i| {
        var descr_idx: ?usize = null;
        for (description) |d, d_i| {
            if (std.mem.eql(u8, d[0], field.name)) {
                descr_idx = d_i;
            }
        }

        if (descr_idx) |i| {
            const context: Context = description[i][1];
            if (context == .compiletime and !field.is_comptime)
                @compileError("Field '" ++ field.name ++ "' should be compile time known");

            struct_field_data[tuple_i] = field;
            const new_field = &struct_field_data[tuple_i];
            if (context == .runtime) {
                new_field.is_comptime = false;
            }

            // If the field description contains two elements, the field is
            // typeless, so we can keep the struct's type information intact.
            if (description[i].len > 2) {
                // If the next description element is a type, we perform typechecking
                if (@TypeOf(description[i][2]) == type) {
                    if (!coercesTo(description[i][2], field.field_type))
                        @compileError("Field '" ++ field.name ++ "' should be " ++ @typeName(description[i][2]) ++ ", is " ++ @typeName(field.field_type));

                    new_field.field_type = description[i][2];
                    new_field.default_value = if (new_field.default_value) |d|
                        @as(?description[i][2], d)
                    else
                        null;
                }
            } else {
                if (context == .runtime) {
                    if (requiresComptime(field.field_type)) {
                        @compileError("Cannot initialize runtime typeless field '" ++ field.name ++
                            "' with value of comptime-only type '" ++ @typeName(field.field_type) ++ "'");
                    }
                }
                new_field.default_value = null;
            }
        } else {
            extra_error_msg = extra_error_msg ++ "  -- " ++ field.name ++ "\n";
            extra_fields = true;
        }
    }
    if (extra_fields) @compileError(extra_error_msg);

    var extra_field_data: [description.len - tuple_fields.len]StructField = undefined;
    var i = 0;
    for (description) |descr| {
        if (!@hasField(Tuple, descr[0])) {
            if (descr.len == 2) {
                @compileError("Missing value for typeless field '" ++ descr[0] ++ "'.");
            }
            const context: Context = descr[1];
            if (@TypeOf(descr[2]) == type) {
                if (descr.len != 4) {
                    @compileError("Missing value for field '" ++ descr[0] ++ "' with no default value");
                }
                const default_value: ?descr[2] = descr[3];
                extra_field_data[i] = .{
                    .name = descr[0],
                    .field_type = descr[2],
                    .default_value = default_value,
                    .is_comptime = context == .compiletime,
                    .alignment = if (@sizeOf(descr[2]) > 0) @alignOf(descr[2]) else 0,
                };
                i += 1;
            } else {
                const field_type = @TypeOf(descr[2]);
                const default_value: ?field_type = descr[2];
                extra_field_data[i] = .{
                    .name = descr[0],
                    .field_type = field_type,
                    .default_value = default_value,
                    .is_comptime = context == .compiletime,
                    .alignment = if (@sizeOf(field_type) > 0) @alignOf(field_type) else 0,
                };
                i += 1;
            }
        }
    }

    const struct_fields = &struct_field_data ++ &extra_field_data;
    return @Type(.{
        .Struct = .{
            .is_tuple = false,
            .layout = .Auto,
            .decls = &[_]std.builtin.TypeInfo.Declaration{},
            .fields = struct_fields,
        },
    });
}

pub fn mixtime(comptime description: anytype) type {
    return struct {
        pub fn make(tuple: anytype) MixtimeType(description, @TypeOf(tuple)) {
            const Tuple = @TypeOf(tuple);
            const T = MixtimeType(description, @TypeOf(tuple));
            var value: T = undefined;
            inline for (std.meta.fields(T)) |field| {
                if (field.is_comptime)
                    continue;

                if (@hasField(Tuple, field.name)) {
                    @field(value, field.name) = @field(tuple, field.name);
                } else if (field.default_value) |default_value| {
                    @field(value, field.name) = default_value;
                } else unreachable;
            }
            return value;
        }
    };
}

// Fix this gap highlighter issue vvvvv
const DummyOptions = mixtime(.{
    .{ "name", .compiletime, []const u8 },
    .{ "port", .runtime, usize, 8080 },
    .{ "some_type", .compiletime, type, void },
    .{ "any", .runtime },
    // Defaults to 42 but can be of any type
    .{ "ct_any", .compiletime, 42 },
});

fn takesOptions(option_tuple: anytype) void {
    const options = DummyOptions.make(option_tuple);
    _ = options.name;
    _ = options.port;
    _ = options.some_type;
    _ = options.any;
    _ = options.ct_any;
}

test "dummy test" {
    takesOptions(.{ .name = "whatever", .some_type = usize, .any = @as(usize, 0) });
    takesOptions(.{ .name = "whatever", .port = 101, .any = "hello" });
    var rt_value: usize = 0;
    takesOptions(.{ .name = "whatever", .port = rt_value, .ct_any = u616, .any = {} });
    takesOptions(.{ .name = "whatever", .some_type = usize, .any = &rt_value });

    // errors
    // takesOptions(.{ .name = "whatever", .some_type = usize }); // error: Missing value for typeless field 'any'.
    // takesOptions(.{ .any = usize }); // error: Cannot initialize runtime typeless field 'any' with value of comptime-only type 'type'
    // takesOptions(.{ .port = 1337 }); // error: Missing field 'name' with no default value
    // var rt_name: []const u8 = "hi there";
    // takesOptions(.{ .name = rt_name }); // error: Field 'name' should be compile time known
    // takesOptions(.{ .foo = 0 }); // error: Extraneous fields:
    //                              // -- foo
}
