const std = @import("std");

fn getSrcPtrType(comptime T: type) ?type {
    return switch (@typeInfo(T)) {
        .Pointer => T,
        .Fn => T,
        .AnyFrame => T,
        .Optional => |o| switch (@typeInfo(o.child)) {
            .Pointer => |p| if (p.is_allowzero) null else o.child,
            .Fn => o.child,
            .AnyFrame => o.child,
            else => null,
        },
        else => null,
    };
}

fn isAllowZeroPtr(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .Pointer => |p| p.is_allowzero,
        .Optional => true,
        else => false,
    };
}

fn genericArgCount(comptime fn_info: std.builtin.TypeInfo.Fn) comptime_int {
    for (fn_info.args) |arg, i| {
        if (arg.is_generic)
            return fn_info.args.len - i;
    }
    return 0;
}

fn sentinelEql(comptime left: anytype, comptime right: anytype) bool {
    if (@TypeOf(left) != @TypeOf(right)) {
        return false;
    }
    return std.meta.eql(left, right);
}

/// Translated from ir.cpp:types_match_const_cast_only
fn typesMatchConstCastOnly(comptime wanted: type, comptime actual: type, comptime wanted_is_mutable: bool) bool {
    comptime {
        const wanted_info = @typeInfo(wanted);
        const actual_info = @typeInfo(actual);

        if (wanted == actual)
            return true;

        const wanted_ptr_type = getSrcPtrType(wanted);
        const actual_ptr_type = getSrcPtrType(actual);
        const wanted_allows_zero = isAllowZeroPtr(wanted);
        const actual_allows_zero = isAllowZeroPtr(actual);
        const wanted_is_c_ptr = wanted_info == .Pointer and wanted_info.Pointer.size == .C;
        const actual_is_c_ptr = actual_info == .Pointer and actual_info.Pointer.size == .C;
        const wanted_opt_or_ptr = wanted_ptr_type != null and @typeInfo(wanted_ptr_type.?) == .Pointer;
        const actual_opt_or_ptr = actual_ptr_type != null and @typeInfo(actual_ptr_type.?) == .Pointer;

        if (wanted_opt_or_ptr and actual_opt_or_ptr) {
            const wanted_ptr_info = @typeInfo(wanted_ptr_type.?).Pointer;
            const actual_ptr_info = @typeInfo(actual_ptr_type.?).Pointer;
            const ok_null_term_ptrs = wanted_ptr_info.sentinel == null or
                (actual_ptr_info.sentinel != null and
                sentinelEql(wanted_ptr_info.sentinel, actual_ptr_info.sentinel));

            if (!ok_null_term_ptrs) {
                return false;
            }
            const ptr_sizes_eql = actual_ptr_info.size == wanted_ptr_info.size;
            if (!(ptr_sizes_eql or wanted_is_c_ptr or actual_is_c_ptr)) {
                return false;
            }
            const ok_cv_qualifiers = (!actual_ptr_info.is_const or wanted_ptr_info.is_const) and
                (!actual_ptr_info.is_volatile or wanted_ptr_info.is_volatile);
            if (!ok_cv_qualifiers) {
                return false;
            }
            if (!typesMatchConstCastOnly(
                wanted_ptr_info.child,
                actual_ptr_info.child,
                !wanted_ptr_info.is_const,
            )) {
                return false;
            }
            const ok_allows_zero = (wanted_allows_zero and
                (actual_allows_zero or !wanted_is_mutable)) or
                (!wanted_allows_zero and !actual_allows_zero);
            if (!ok_allows_zero) {
                return false;
            }
            if ((@sizeOf(wanted) > 0 and @sizeOf(actual) > 0) and
                actual_ptr_info.alignment >= wanted_ptr_info.alignment)
            {
                return true;
            }
        }

        // arrays
        if (wanted_info == .Array and actual_info == .Array and
            wanted_info.Array.len == actual_info.Array.len)
        {
            if (!typesMatchConstCastOnly(
                wanted_info.Array.child,
                actual_info.Array.child,
                wanted_is_mutable,
            )) {
                return false;
            }
            const ok_sentinels = wanted_info.Array.sentinel == null or
                (actual_info.Array.sentinel != null and
                sentinelEql(wanted_info.Array.sentinel, actual_info.Array.sentinel));
            if (!ok_sentinels) {
                return false;
            }
            return true;
        }

        // const slice
        if (isSlice(wanted) and isSlice(actual)) {
            const wanted_slice_info = @typeInfo(wanted).Pointer;
            const actual_slice_info = @typeInfo(actual).Pointer;
            const ok_sentinels = wanted_slice_info.sentinel == null or
                (actual_slice_info.sentinel != null and
                sentinelEql(wanted_slice_info.sentinel, actual_slice_info.sentinel));
            if (!ok_sentinels) {
                return false;
            }
            const ok_cv_qualifiers = (!actual_slice_info.is_const or wanted_slice_info.is_const) and
                (!actual_slice_info.is_volatile or wanted_slice_info.is_volatile);
            if (!ok_cv_qualifiers) {
                return false;
            }
            if (actual_slice_info.alignment < wanted_slice_info.alignment) {
                return false;
            }
            if (!typesMatchConstCastOnly(
                wanted_slice_info.child,
                actual_slice_info.child,
                !wanted_slice_info.is_const,
            )) {
                return false;
            }
            return true;
        }

        // optional types
        if (wanted_info == .Optional and actual_info == .Optional) {
            if ((wanted_ptr_type != null) != (actual_ptr_type != null)) {
                return false;
            }
            if (!typesMatchConstCastOnly(
                wanted_info.Optional.child,
                actual_info.Optional.child,
                wanted_is_mutable,
            )) {
                return false;
            }
            return true;
        }

        // error union
        if (wanted_info == .ErrorUnion and actual_info == .ErrorUnion) {
            if (!typesMatchConstCastOnly(
                wanted_info.ErrorUnion.payload,
                actual_info.ErrorUnion.payload,
                wanted_is_mutable,
            )) {
                return false;
            }
            if (!typesMatchConstCastOnly(
                wanted_info.ErrorUnion.error_set,
                actual_info.ErrorUnion.error_set,
                wanted_is_mutable,
            )) {
                return false;
            }
            return true;
        }

        // error set
        if (wanted_info == .ErrorSet and actual_info == .ErrorSet) {
            return isSuperset(wanted, actual);
        }

        // fn
        if (wanted_info == .Fn and actual_info == .Fn) {
            if (wanted_info.Fn.alignment > actual_info.Fn.alignment) {
                return false;
            }
            if (wanted_info.Fn.is_var_args != actual_info.Fn.is_var_args) {
                return false;
            }
            if (wanted_info.Fn.is_generic != actual_info.Fn.is_generic) {
                return false;
            }
            if (!wanted_info.Fn.is_generic and
                actual_info.Fn.return_type != null)
            {
                if (!typesMatchConstCastOnly(
                    wanted_info.Fn.return_type.?,
                    actual_info.Fn.return_type.?,
                    false,
                )) {
                    return false;
                }
            }
            if (wanted_info.Fn.args.len != actual_info.Fn.args.len) {
                return false;
            }
            if (genericArgCount(wanted_info.Fn) != genericArgCount(actual_info.Fn)) {
                return false;
            }
            if (wanted_info.Fn.calling_convention != actual_info.Fn.calling_convention) {
                return false;
            }
            var i = 0;
            while (i < wanted_info.Fn.args.len) : (i += 1) {
                const actual_arg_info = actual_info.Fn.args[i];
                const wanted_arg_info = wanted_info.Fn.args[i];

                if (actual_arg_info.is_generic != wanted_arg_info.is_generic) {
                    return false;
                }
                if (actual_arg_info.is_noalias != wanted_arg_info.is_noalias) {
                    return false;
                }
                if (actual_arg_info.is_generic) {
                    continue;
                }
                if (!typesMatchConstCastOnly(
                    actual_arg_info.arg_type.?,
                    wanted_arg_info.arg_type.?,
                    false,
                )) {
                    return false;
                }
            }
            return true;
        }

        if (wanted_info == .Int and actual_info == .Int) {
            if (wanted_info.Int.signedness != actual_info.Int.signedness or
                wanted_info.Int.bits != actual_info.Int.bits)
            {
                return false;
            }
            return true;
        }

        if (wanted_info == .Vector and actual_info == .Vector) {
            if (wanted_info.Vector.len != actual_info.Vector.len) {
                return false;
            }
            if (!typesMatchConstCastOnly(
                wanted_info.Vector.child,
                actual_info.Vector.child,
                false,
            )) {
                return false;
            }
            return true;
        }
        return false;
    }
}

fn isSuperset(comptime A: type, comptime B: type) bool {
    const a_info = @typeInfo(A).ErrorSet.?;
    const b_info = @typeInfo(B).ErrorSet.?;

    for (b_info) |b_err| {
        var found = false;
        for (a_info) |a_err| {
            if (std.mem.eql(u8, a_err.name, b_err.name)) {
                found = true;
                break;
            }
        }
        if (!found) {
            return false;
        }
    }
    return true;
}

fn errSetEql(comptime A: type, comptime B: type) bool {
    if (A == B) return true;

    const a_info = @typeInfo(A).ErrorSet.?;
    const b_info = @typeInfo(B).ErrorSet.?;

    if (a_info.len != b_info.len) return false;
    return isSuperset(A, B);
}

/// Translated from ir.cpp:ir_resolve_peer_types
pub fn PeerType(comptime types: anytype) ?type {
    var prev_type: type = undefined;
    var prev_info: std.builtin.TypeInfo = undefined;

    var i = 0;
    while (true) {
        prev_type = types[i];
        prev_info = @typeInfo(prev_type);

        if (prev_info == .NoReturn) {
            i += 1;
            if (i == types.len) {
                return prev_type;
            }
            continue;
        }
        break;
    }

    // Differences with stage1 implementation:
    //   we need only keep the type and use ||
    //   to update it, no need to separately keep
    //   an error entry table.
    var err_set_type: ?type = null;
    if (prev_info == .ErrorSet) {
        err_set_type = prev_type;
    }

    var any_are_null = prev_info == .Null;
    var convert_to_const_slice = false;
    var make_the_slice_const = false;
    var make_the_pointer_const = false;

    while (i < types.len) : (i += 1) {
        const cur_type = types[i];
        const cur_info = @typeInfo(cur_type);
        prev_info = @typeInfo(prev_type);

        if (prev_type == cur_type)
            continue;

        if (prev_info == .NoReturn) {
            prev_type = cur_type;
            continue;
        }

        if (cur_info == .NoReturn) {
            continue;
        }

        if (prev_info == .ErrorSet) {
            switch (cur_info) {
                .ErrorSet => {
                    if (err_set_type == anyerror) {
                        continue;
                    }

                    if (cur_type == anyerror) {
                        prev_type = cur_type;
                        err_set_type = anyerror;
                        continue;
                    }

                    if (isSuperset(err_set_type.?, cur_type)) {
                        continue;
                    }

                    if (isSuperset(cur_type, err_set_type.?)) {
                        err_set_type = cur_type;
                        prev_type = cur_type;
                        continue;
                    }
                    err_set_type = err_set_type.? || cur_type;
                    continue;
                },
                .ErrorUnion => |cur_err_union| {
                    if (err_set_type == anyerror) {
                        prev_type = cur_type;
                        continue;
                    }

                    const cur_err_set_type = cur_err_union.error_set;
                    if (cur_err_set_type == anyerror) {
                        err_set_type = anyerror;
                        prev_type = cur_type;
                        continue;
                    }

                    if (isSuperset(cur_err_set_type, err_set_type.?)) {
                        err_set_type = cur_err_set_type;
                        prev_type = cur_type;
                        errors = cur_errors;
                        continue;
                    }

                    err_set_type = err_set_type.? || cur_err_set_type;
                    prev_type = cur_type;
                    continue;
                },
                else => {
                    prev_type = cur_type;
                    continue;
                },
            }
        }

        if (cur_info == .ErrorSet) {
            if (cur_type == anyerror) {
                err_set_type = anyerror;
                continue;
            }
            if (err_set_type == anyerror) {
                continue;
            }

            if (err_set_type == null) {
                err_set_type = cur_type;
                continue;
            }

            if (isSuperset(err_set_type.?, cur_type)) {
                continue;
            }
            err_set_type = err_set_type.? || cur_type;
            continue;
        }

        if (prev_info == .ErrorUnion and cur_info == .ErrorUnion) {
            const prev_payload_type = prev_info.ErrorUnion.payload;
            const cur_payload_type = cur_info.ErrorUnion.payload;
            const const_cast_prev = typesMatchConstCastOnly(prev_payload_type, cur_payload_type, false);
            const const_cast_cur = typesMatchConstCastOnly(cur_payload_type, prev_payload_type, false);

            if (const_cast_cur or const_cast_prev) {
                if (const_cast_cur) {
                    prev_type = cur_type;
                }

                const prev_err_set_type = if (err_set_type) |s|
                    s
                else
                    prev_info.ErrorUnion.error_set;

                const cur_err_set_type = cur_info.ErrorUnion.error_set;
                if (errSetEql(prev_err_set_type, cur_err_set_type)) {
                    continue;
                }

                if (prev_err_set_type == anyerror or cur_err_set_type == anyerror) {
                    err_set_type = anyerror;
                    continue;
                }

                if (err_set_type == null) {
                    err_set_type = prev_err_set_type;
                }

                if (isSuperset(err_set_type, cur_err_set_type)) {
                    continue;
                }

                if (isSuperset(cur_err_set_type, err_set_type)) {
                    err_set_type = cur_err_set_type;
                    continue;
                }

                err_set_type = err_set_type.? || cur_err_set_type;
                continue;
            }
        }

        if (prev_info == .Null) {
            prev_type = cur_type;
            any_are_null = true;
            continue;
        }

        if (cur_info == .Null) {
            any_are_null = true;
            continue;
        }

        if (prev_info == .Enum and cur_info == .EnumLiteral) {
            // We assume the enum literal is coercible to any enum type
            continue;
        }

        if (prev_info == .Union and prev_info.Union.tag_type != null and cur_info == .EnumLiteral) {
            // Same as above
            continue;
        }

        if (cur_info == .Enum and prev_info == .EnumLiteral) {
            // Same as above
            prev_type = cur_type;
            continue;
        }

        if (cur_info == .Union and cur_info.Union.tag_type != null and prev_info == .EnumLiteral) {
            // Same as above
            prev_type = cur_type;
            continue;
        }

        if (prev_info == .Pointer and prev_info.Pointer.size == .C and
            (cur_info == .ComptimeInt or cur_info == .Int))
        {
            continue;
        }

        if (cur_info == .Pointer and cur_info.Pointer.size == .C and
            (prev_info == .ComptimeInt or prev_info == .Int))
        {
            prev_type = cur_type;
            continue;
        }

        if (prev_info == .Pointer and cur_info == .Pointer) {
            if (prev_info.Pointer.size == .C and
                typesMatchConstCastOnly(
                prev_info.Pointer.child,
                cur_info.Pointer.child,
                !prev_info.Pointer.is_const,
            )) {
                continue;
            }

            if (cur_info.Pointer.size == .C and
                typesMatchConstCastOnly(
                cur_info.Pointer.child,
                prev_info.Pointer.child,
                !cur_info.Pointer.is_const,
            )) {
                prev_type = cur_type;
                continue;
            }
        }

        if (typesMatchConstCastOnly(prev_type, cur_type, false))
            continue;

        if (typesMatchConstCastOnly(cur_type, prev_type, false)) {
            prev_type = cur_type;
            continue;
        }

        if (prev_info == .Int and cur_info == .Int and
            prev_info.Int.signedness == cur_info.Int.signedness)
        {
            if (cur_info.Int.bits > prev_info.Int.bits) {
                prev_type = cur_type;
            }
            continue;
        }

        if (prev_info == .Float and cur_info == .Float) {
            if (cur_info.Float.bits > prev_info.Float.bits) {
                prev_type = cur_type;
            }
            continue;
        }

        if (prev_info == .ErrorUnion and
            typesMatchConstCastOnly(prev_info.ErrorUnion.payload, cur_type, false))
        {
            continue;
        }

        if (cur_info == .ErrorUnion and
            typesMatchConstCastOnly(cur_info.ErrorUnion.payload, prev_type, false))
        {
            if (err_set_type) |err_set| {
                const cur_err_set_type = cur_info.ErrorUnion.error_set;
                if (err_set_type == anyerror or cur_err_set_type == anyerror) {
                    err_set_type = anyerror;
                    prev_type = cur_type;
                    continue;
                }
                err_set_type = err_set_type.? || cur_err_set_type;
            }
            prev_type = cur_type;
            continue;
        }

        if (prev_info == .Optional and
            typesMatchConstCastOnly(prev_info.Optional.child, cur_type, false))
        {
            continue;
        }

        if (cur_info == .Optional and
            typesMatchConstCastOnly(cur_info.Optional.child, prev_type, false))
        {
            prev_type = cur_type;
            continue;
        }

        if (prev_info == .Optional and
            typesMatchConstCastOnly(cur_type, prev_info.Optional.child, false))
        {
            prev_type = cur_type;
            any_are_null = true;
            continue;
        }

        if (cur_info == .Optional and
            typesMatchConstCastOnly(prev_type, cur_info.Optional.child, false))
        {
            any_are_null = true;
            continue;
        }

        if (cur_info == .Undefined)
            continue;

        if (prev_info == .Undefined) {
            prev_type = cur_type;
            continue;
        }

        if (prev_info == .ComptimeInt and (cur_info == .Int or cur_info == .ComptimeInt)) {
            prev_type = cur_type;
            continue;
        }

        if (prev_info == .ComptimeFloat and (cur_info == .Float or cur_info == .ComptimeFloat)) {
            prev_type = cur_type;
            continue;
        }

        if (cur_info == .ComptimeInt and (prev_info == .Int or prev_info == .ComptimeInt)) {
            continue;
        }

        if (cur_info == .ComptimeFloat and (prev_info == .Float or prev_info == .ComptimeFloat)) {
            continue;
        }

        // *[N]T to [*]T
        if (prev_info == .Pointer and prev_info.Pointer.size == .One and
            @typeInfo(prev_info.Pointer.child) == .Array and
            (cur_info == .Pointer and cur_info.Pointer.size == .Many))
        {
            convert_to_const_slice = false;
            prev_type = cur_type;
            if (prev_info.Pointer.is_const and !cur_info.Pointer.is_const) {
                make_the_pointer_const = true;
            }
            continue;
        }

        // *[N]T to [*]T
        if (cur_info == .Pointer and cur_info.Pointer.size == .One and
            @typeInfo(cur_info.Pointer.child) == .Array and
            (prev_info == .Pointer and prev_info.Pointer.size == .Many))
        {
            if (cur_info.Pointer.is_const and !prev_info.Pointer.is_const) {
                make_the_pointer_const = true;
            }
            continue;
        }

        // *[N]T to []T
        // *[N]T to E![]T
        if (cur_info == .Pointer and cur_info.Pointer.size == .One and
            @typeInfo(cur_info.Pointer.child) == .Array and
            ((prev_info == .ErrorUnion and isSlice(prev_info.ErrorUnion.payload)) or
            isSlice(prev_type)))
        {
            const array_type = cur_info.Pointer.child;
            const slice_type = if (prev_info == .ErrorUnion)
                prev_info.ErrorUnion.payload
            else
                prev_type;

            const array_info = @typeInfo(array_type).Array;
            const slice_ptr_type = slicePtrType(slice_type);
            const slice_ptr_info = @typeInfo(slice_ptr_type);
            if (typesMatchConstCastOnly(
                slice_ptr_info.Pointer.child,
                array_info.child,
                false,
            )) {
                const const_ok = slice_ptr_info.Pointer.is_const or
                    array_info.size == 0 or !cur_info.Pointer.is_const;
                if (!const_ok) make_the_slice_const = true;
                convert_to_const_slice = false;
                continue;
            }
        }

        // *[N]T to []T
        // *[N]T to E![]T
        if (prev_info == .Pointer and prev_info.Pointer.size == .One and
            @typeInfo(prev_info.Pointer.child) == .Array and
            ((cur_info == .ErrorUnion and isSlice(cur_info.ErrorUnion.payload)) or
            (cur_info == .Optional and isSlice(cur_info.Optional.child)) or
            isSlice(cur_type)))
        {
            const array_type = prev_info.Pointer.child;
            const slice_type = switch (cur_info) {
                .ErrorUnion => |error_union_info| error_union_info.payload,
                .Optional => |optional_info| optional_info.child,
                else => cur_type,
            };

            const array_info = @typeInfo(array_type).Array;
            const slice_ptr_type = slicePtrType(slice_type);
            const slice_ptr_info = @typeInfo(slice_ptr_type);
            if (typesMatchConstCastOnly(
                slice_ptr_info.Pointer.child,
                array_info.child,
                false,
            )) {
                const const_ok = slice_ptr_info.Pointer.is_const or
                    array_info.size == 0 or !prev_info.Pointer.is_const;
                if (!const_ok) make_the_slice_const = true;
                prev_type = cur_type;
                convert_to_const_slice = false;
                continue;
            }
        }

        // *[N]T and *[M]T
        const both_ptr_to_arr = (cur_info == .Pointer and cur_info.Pointer.size == .One and
            @typeInfo(cur_info.Pointer.child) == .Array and
            prev_info == .Pointer and prev_info.Pointer.size == .One and
            @typeInfo(prev_info.Pointer.child) == .Array);

        if (both_ptr_to_arr) {
            const cur_array_info = @typeInfo(cur_info.Pointer.child).Array;
            const prev_array_info = @typeInfo(prev_info.Pointer.child).Array;

            if (prev_array_info.sentinel == null or (cur_array_info.sentinel != null and
                sentinelEql(prev_array_info.sentinel, cur_array_info.sentinel)) and
                typesMatchConstCastOnly(
                cur_array_info.child,
                prev_array_info.child,
                !cur_info.Pointer.is_const,
            )) {
                const const_ok = cur_info.Pointer.is_const or !prev_info.Pointer.is_const or
                    prev_array_info.len == 0;

                if (!const_ok) make_the_slice_const = true;
                prev_type = cur_type;
                convert_to_const_slice = true;
                continue;
            }

            if (cur_array_info.sentinel == null or (prev_array_info.sentinel != null and
                sentinelEql(cur_array_info.sentinel, prev_array_info.sentinel)) and
                typesMatchConstCastOnly(
                prev_array_info.child,
                cur_array_info.child,
                !prev_info.Pointer.is_const,
            )) {
                const const_ok = prev_indo.Pointer.is_const or !cur_info.Pointer.is_const or
                    cur_array_info.len == 0;

                if (!const_ok) make_the_slice_const = true;
                convert_to_const_slice = true;
                continue;
            }
        }

        if (prev_info == .Enum and cur_info == .Union and cur_info.Union.tag_type != null) {
            if (cur_info.Union.tag_type.? == prev_type) {
                continue;
            }
        }

        if (cur_info == .Enum and prev_info == .Union and prev_info.Union.tag_type != null) {
            if (prev_info.Union.tag_type.? == cur_type) {
                prev_type = cur_type;
                continue;
            }
        }

        return null;
    }

    if (convert_to_const_slice) {
        if (prev_info == .Pointer) {
            const array_type = prev_info.Pointer.child;
            const array_info = @typeInfo(array_type).Array;

            const slice_type = @Type(.{
                .Pointer = .{
                    .child = array_info.child,
                    .is_const = prev_info.Pointer.is_const or make_the_slice_const,
                    .is_volatile = false,
                    .size = .Slice,
                    .alignment = if (@sizeOf(array_info.child) > 0) @alignOf(array_info.child) else 0,
                    .is_allowzero = false,
                    .sentinel = array_info.sentinel,
                },
            });

            if (err_set_type) |err_type| {
                return err_type!slice_type;
            }
            return slice_type;
        }
    } else if (err_set_type) |err_type| {
        return switch (prev_info) {
            .ErrorSet => err_type,
            .ErrorUnion => |u| err_type!u.payload,
            else => null,
        };
    } else if (any_are_null and prev_info != .Null) {
        if (prev_info == .Optional) {
            return prev_type;
        }
        return ?prev_type;
    } else if (make_the_slice_const) {
        const slice_type = switch (prev_info) {
            .ErrorUnion => |u| u.payload,
            .Pointer => |p| if (p.size == .Slice) prev_type else unreachable,
            else => unreachable,
        };

        const adjusted_slice_type = blk: {
            var ptr_info = @typeInfo(slice_type);
            ptr_info.Pointer.is_const = make_the_slice_const;
            break :blk @Type(ptr_info);
        };
        return switch (prev_info) {
            .ErrorUnion => |u| u.error_set!adjusted_slice_type,
            .Pointer => |p| if (p.size == .Slice) adjusted_slice_type else unreachable,
            else => unreachable,
        };
    } else if (make_the_pointer_const) {
        return blk: {
            var ptr_info = @typeInfo(prev_type);
            ptr_info.Pointer.is_const = make_the_pointer_const;
            break :blk @Type(ptr_info);
        };
    }
    return prev_type;
}

fn slicePtrType(comptime S: type) type {
    var info = @typeInfo(S);
    info.Pointer.size = .Many;
    return @Type(info);
}

const isSlice = std.meta.trait.isSlice;

pub fn coercesTo(comptime dst: type, comptime src: type) bool {
    return (PeerType(.{ dst, src }) orelse return false) == dst;
}

const ContainsAnytype = struct { val: anytype };
const AnyType = std.meta.fieldInfo(ContainsAnytype, "val").field_type;

pub fn requiresComptime(comptime T: type) bool {
    comptime {
        switch (T) {
            AnyType,
            comptime_int,
            comptime_float,
            type,
            @Type(.EnumLiteral),
            @Type(.Null),
            @Type(.Undefined),
            => return true,
            else => {},
        }

        const info = @typeInfo(T);
        switch (info) {
            .BoundFn => return true,
            .Array => |a| return requiresComptime(a.child),
            .Struct => |s| {
                for (s.fields) |f| {
                    if (requiresComptime(f.field_type))
                        return true;
                }
                return false;
            },
            .Union => |u| {
                for (u.fields) |f| {
                    if (requiresComptime(f.field_type))
                        return true;
                }
                return false;
            },
            .Optional => |o| return requiresComptime(o.child),
            .ErrorUnion => |u| return requiresComptime(u.payload),
            .Pointer => |p| {
                if (@typeInfo(p.child) == .Opaque)
                    return false;
                return requiresComptime(p.child);
            },
            .Fn => |f| return f.is_generic,
            else => return false,
        }
    }
}

fn testPeerTypeIs(comptime types: anytype, comptime result: type) void {
    std.testing.expect((PeerType(types) orelse unreachable) == result);
}

fn testNoPeerType(comptime types: anytype) void {
    std.testing.expect(PeerType(types) == null);
}

test "PeerType" {
    testPeerTypeIs(.{ *const [3:0]u8, *const [15:0]u8 }, [:0]const u8);
    testPeerTypeIs(.{ usize, u8 }, usize);

    const E1 = error{OutOfMemory};
    const E2 = error{};
    const S = struct {};
    testPeerTypeIs(.{ E1, E2 }, E1);
    testPeerTypeIs(.{ E1, anyerror!S, E2 }, anyerror!S);

    testPeerTypeIs(.{ *align(16) usize, *align(2) usize }, *align(2) usize);

    testNoPeerType(.{ usize, void });
    testNoPeerType(.{ struct {}, struct {} });
}

test "coercesTo" {
    std.testing.expect(coercesTo([]const u8, *const [123:0]u8));
    std.testing.expect(coercesTo(usize, comptime_int));
}

test "requiresComptime" {
    std.testing.expect(requiresComptime(comptime_int));
    std.testing.expect(requiresComptime(struct { foo: anytype }));
    std.testing.expect(requiresComptime(struct { foo: struct { bar: comptime_float } }));
    std.testing.expect(!requiresComptime(struct { foo: void }));
}
