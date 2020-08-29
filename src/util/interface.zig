// based off of 'https://github.com/Hejsil/zig-interface'

// MIT License
//
// Copyright (c) 2018
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

const std = @import("std");
const builtin = @import("builtin");
const TypeInfo = builtin.TypeInfo;

const debug = std.debug;

// note: can't handle ZSTs

fn checkCompatibility(
    comptime Impl: type,
    comptime T: type,
    comptime expect: TypeInfo.Fn,
    comptime actual: TypeInfo.Fn,
) void {
    debug.assert(!expect.is_generic);
    debug.assert(!expect.is_var_args);
    debug.assert(expect.args.len > 0);
    debug.assert(expect.calling_convention == actual.calling_convention);
    debug.assert(expect.is_generic == actual.is_generic);
    debug.assert(expect.is_var_args == actual.is_var_args);
    debug.assert(expect.return_type.? == actual.return_type.?);
    debug.assert(expect.args.len == actual.args.len);

    for (expect.args) |expect_arg, i| {
        const actual_arg = actual.args[i];
        debug.assert(!expect_arg.is_generic);
        debug.assert(expect_arg.is_generic == actual_arg.is_generic);
        debug.assert(expect_arg.is_noalias == actual_arg.is_noalias);

        if (i == 0) {
            const expect_ptr = @typeInfo(expect_arg.arg_type.?).Pointer;
            const actual_ptr = @typeInfo(actual_arg.arg_type.?).Pointer;
            debug.assert(expect_ptr.size == TypeInfo.Pointer.Size.One);
            debug.assert(expect_ptr.size == actual_ptr.size);
            debug.assert(expect_ptr.is_const == actual_ptr.is_const);
            debug.assert(expect_ptr.is_volatile == actual_ptr.is_volatile);
            debug.assert(actual_ptr.child == T);
            debug.assert(expect_ptr.child == Impl);
        } else {
            debug.assert(expect_arg.arg_type.? == actual_arg.arg_type.?);
        }
    }
}

pub fn populate(comptime Interface: type, comptime T: type) *const Interface {
    const Closure = struct {
        const interface = blk: {
            const Impl = Interface.Impl;

            var ret: Interface = undefined;
            inline for (@typeInfo(Interface).Struct.fields) |field| {
                // currently, accessing default values is a compiler bug
                //   see issue 'https://github.com/ziglang/zig/issues/5508'
                //   for now, use optionals instead
                const FieldType = field.field_type;
                switch (@typeInfo(FieldType)) {
                    .Fn => |expect| {
                        const actual = @typeInfo(@TypeOf(@field(T, field.name))).Fn;
                        checkCompatibility(Impl, T, expect, actual);
                        @field(ret, field.name) = @ptrCast(FieldType, @field(T, field.name));
                    },
                    .Optional => |opt| {
                        const FnType = opt.child;
                        const expect = @typeInfo(FnType).Fn;

                        var found_impl_decl: ?TypeInfo.Declaration = null;
                        inline for (@typeInfo(T).Struct.decls) |impl_decl| {
                            if (std.mem.eql(u8, field.name, impl_decl.name)) {
                                found_impl_decl = impl_decl;
                            }
                        }

                        if (found_impl_decl) |found| {
                            const actual = @typeInfo(@TypeOf(@field(T, found.name))).Fn;
                            checkCompatibility(Impl, T, expect, actual);
                            @field(ret, field.name) = @ptrCast(FnType, @field(T, found.name));
                        } else {
                            // compiler bug
                            @field(ret, field.name) = @ptrCast(FnType, @field(Interface, field.name));
                        }
                    },
                    else => {
                        // TODO error
                    },
                }

                // const FieldType = field.field_type;
                // const expect = @typeInfo(FieldType).Fn;
                // if (field.default_value) |default| {
                //     var found_impl_decl: ?TypeInfo.Declaration = null;
                //     inline for (@typeInfo(T).Struct.decls) |impl_decl| {
                //         if (std.mem.eql(u8, field.name, impl_decl.name)) {
                //             found_impl_decl = impl_decl;
                //         }
                //     }
                //     if (found_impl_decl) |found| {
                //         const actual = @typeInfo(@TypeOf(@field(T, found.name))).Fn;
                //         checkCompatibility(Impl, T, expect, actual);
                //         @field(ret, field.name) = @ptrCast(FieldType, @field(T, found.name));
                //     } else {
                //         // compiler bug
                //         // @field(ret, field.name) = @ptrCast(FieldType, default);
                //     }
                // } else {
                //     const actual = @typeInfo(@TypeOf(@field(T, field.name))).Fn;
                //     checkCompatibility(Impl, T, expect, actual);
                //     @field(ret, field.name) = @ptrCast(FieldType, @field(T, field.name));
                // }
            }
            break :blk ret;
        };
    };
    return &Closure.interface;
}
