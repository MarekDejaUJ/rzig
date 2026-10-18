//! Read-only access to borrowed R objects.
//!
//! These helpers validate types and bounds before calling R's accessors. A
//! mismatch is returned as `null` or as a recorded error, so R never longjmps
//! through a Zig frame. Copies go into the call context; no R object is
//! allocated or modified.

const std = @import("std");
const c = @import("c/abi.zig");
const convert = @import("convert.zig");
const es = @import("error_state.zig");
const Ctx = @import("alloc.zig").Ctx;

const OpaqueSexp = opaque {
    /// The kind of R object.
    pub fn kind(self: *OpaqueSexp) Kind {
        return Kind.of(typeOf(self));
    }

    /// The length of the object (0 for NULL and objects without a length).
    pub fn length(self: *OpaqueSexp) usize {
        return xlength(self) orelse 0;
    }

    /// Whether the object is R's NULL.
    pub fn isNull(self: *OpaqueSexp) bool {
        return c.Rf_isNull(toRaw(self)) != c.FALSE;
    }

    /// Whether the object has a class attribute.
    pub fn isObject(self: *OpaqueSexp) bool {
        return c.Rf_isObject(toRaw(self)) != c.FALSE;
    }

    /// Whether the object is an S4 object.
    pub fn isS4(self: *OpaqueSexp) bool {
        return c.Rf_isS4(toRaw(self)) != c.FALSE;
    }

    /// Whether `class_name` is one of the classes in the class attribute.
    pub fn inherits(self: *OpaqueSexp, class_name: []const u8) bool {
        var buffer: [name_capacity]u8 = undefined;
        const text = cString(class_name, &buffer) orelse return false;
        return c.Rf_inherits(toRaw(self), text) != c.FALSE;
    }

    /// The attribute `name`, or `null`. The slots of an S4 object are its
    /// attributes. Row names are read with `rzig.DataFrame`, because R
    /// builds them on request, and pairlists have no attributes here.
    pub fn attribute(self: *OpaqueSexp, name: []const u8) es.Error!?Sexp {
        const kind_value = c.TYPEOF(toRaw(self));
        if (kind_value == c.LISTSXP or kind_value == c.LANGSXP) {
            return es.raise("rzig: attributes of pairlists are not read through rzig.Sexp", .{});
        }
        if (std.mem.eql(u8, name, "row.names")) {
            return es.raise("rzig: read row names with rzig.DataFrame, which counts the rows", .{});
        }
        var buffer: [name_capacity]u8 = undefined;
        const text = cString(name, &buffer) orelse
            return es.raise("rzig: an attribute name has at most 255 bytes and no NUL byte", .{});
        const value = c.Rf_getAttrib(toRaw(self), c.Rf_install(text));
        if (c.Rf_isNull(value) != c.FALSE) return null;
        return fromRaw(value);
    }

    /// The names of the object, copied into the call context (NA is `null`),
    /// or `null` when it has none.
    pub fn names(self: *OpaqueSexp, ctx: *Ctx) es.Error!?[]const ?[]const u8 {
        const value = (try self.attribute("names")) orelse return null;
        if (typeOf(value) != c.STRSXP) return null;
        return try copyStrings(ctx, value);
    }

    /// The classes of the class attribute, copied into the call context; empty
    /// when the attribute is absent.
    pub fn classes(self: *OpaqueSexp, ctx: *Ctx) es.Error![]const []const u8 {
        const value = (try self.attribute("class")) orelse return &.{};
        if (typeOf(value) != c.STRSXP) return &.{};
        const strings = try copyStrings(ctx, value);
        const result = try ctx.alloc([]const u8, strings.len);
        for (strings, result) |string, *slot| slot.* = string orelse "NA";
        return result;
    }

    /// Element `index` (zero-based) of a list, or `null` beyond its end or for
    /// an object that is not a list.
    pub fn element(self: *OpaqueSexp, index: usize) ?Sexp {
        const kind_value = c.TYPEOF(toRaw(self));
        if (kind_value != c.VECSXP and kind_value != c.EXPRSXP) return null;
        if (index >= self.length()) return null;
        return fromRaw(c.VECTOR_ELT(toRaw(self), @intCast(index)));
    }

    /// The first element of a list called `name`, or `null`.
    pub fn field(self: *OpaqueSexp, name: []const u8) es.Error!?Sexp {
        if (c.TYPEOF(toRaw(self)) != c.VECSXP) return null;
        const list_names = (try self.attribute("names")) orelse return null;
        if (typeOf(list_names) != c.STRSXP) return null;
        const mark = c.vmaxget();
        defer c.vmaxset(mark);
        const count = @min(self.length(), xlength(list_names) orelse 0);
        for (0..count) |index| {
            const entry = c.STRING_ELT(toRaw(list_names), @intCast(index));
            if (entry == c.R_NaString) continue;
            if (std.mem.eql(u8, std.mem.span(c.Rf_translateCharUTF8(entry)), name)) {
                return fromRaw(c.VECTOR_ELT(toRaw(self), @intCast(index)));
            }
        }
        return null;
    }

    /// Convert the object to `T` with the rules of an exported function's
    /// parameter of that type (for example `[]const f64` or `rzig.Record(S)`).
    pub fn get(self: *OpaqueSexp, comptime T: type, ctx: *Ctx) es.Error!T {
        return convert.fromSexp(T, ctx, toRaw(self), "the R value");
    }
};

/// The kinds of R objects that `Sexp.kind()` distinguishes.
pub const Kind = enum {
    nil,
    logical,
    integer,
    double,
    complex,
    character,
    list,
    raw,
    function,
    environment,
    s4,
    other,

    fn of(sexp_type: c.SEXPTYPE) Kind {
        return switch (sexp_type) {
            c.NILSXP => .nil,
            c.LGLSXP => .logical,
            c.INTSXP => .integer,
            c.REALSXP => .double,
            c.CPLXSXP => .complex,
            c.STRSXP => .character,
            c.VECSXP => .list,
            c.RAWSXP => .raw,
            c.CLOSXP, c.BUILTINSXP, c.SPECIALSXP => .function,
            c.ENVSXP => .environment,
            c.OBJSXP => .s4,
            else => .other,
        };
    }
};

const name_capacity = 256;

/// `name` with a terminating NUL in `buffer`, or `null` when it does not fit
/// or contains a NUL byte.
fn cString(name: []const u8, buffer: *[name_capacity]u8) ?[*:0]const u8 {
    if (name.len >= buffer.len or std.mem.indexOfScalar(u8, name, 0) != null) return null;
    @memcpy(buffer[0..name.len], name);
    buffer[name.len] = 0;
    return buffer[0..name.len :0].ptr;
}

fn copyStrings(ctx: *Ctx, value: Sexp) es.Error![]const ?[]const u8 {
    const count = xlength(value) orelse 0;
    const mark = c.vmaxget();
    defer c.vmaxset(mark);
    const result = try ctx.alloc(?[]const u8, count);
    for (result, 0..) |*slot, index| {
        const entry = c.STRING_ELT(toRaw(value), @intCast(index));
        slot.* = if (entry == c.R_NaString) null else try ctx.dupe(u8, std.mem.span(c.Rf_translateCharUTF8(entry)));
    }
    return result;
}

/// Borrowed R value, valid for the duration of its `.Call`, with read-only
/// methods: `kind`, `length`, `isNull`, `isObject`, `isS4`, `inherits`,
/// `attribute`, `names`, `classes`, `element`, `field` and `get`.
pub const Sexp = *OpaqueSexp;

/// Wrap an internal C SEXP without changing ownership or protection.
pub fn fromRaw(value: c.SEXP) Sexp {
    return @ptrCast(value);
}

/// Recover the internal C SEXP without changing ownership or protection.
pub fn toRaw(value: Sexp) c.SEXP {
    return @ptrCast(value);
}

/// Return the R storage type of a borrowed value.
pub fn typeOf(value: Sexp) c.SEXPTYPE {
    return @intCast(c.TYPEOF(toRaw(value)));
}

/// Return a long-vector-safe length, or `null` if R reports an invalid value.
pub fn xlength(value: Sexp) ?usize {
    return checkedLength(c.Rf_xlength(toRaw(value)));
}

/// Borrow a read-only double slice, or `null` when `value` is not a REALSXP.
pub fn realRo(value: Sexp) ?[]const f64 {
    if (typeOf(value) != c.REALSXP) return null;
    const len = xlength(value) orelse return null;
    return c.REAL_RO(toRaw(value))[0..len];
}

/// Borrow a read-only integer slice, or `null` when `value` is not an INTSXP.
pub fn intRo(value: Sexp) ?[]const c_int {
    if (typeOf(value) != c.INTSXP) return null;
    const len = xlength(value) orelse return null;
    return c.INTEGER_RO(toRaw(value))[0..len];
}

/// Read a CHARSXP, returning `null` for a wrong type or out-of-bounds index.
pub fn stringElt(value: Sexp, index: usize) ?Sexp {
    if (typeOf(value) != c.STRSXP) return null;
    const len = xlength(value) orelse return null;
    if (index >= len) return null;
    return fromRaw(c.STRING_ELT(toRaw(value), @intCast(index)));
}

/// Test whether a borrowed value is R's null singleton.
pub fn isNull(value: Sexp) bool {
    return c.Rf_isNull(toRaw(value)) != c.FALSE;
}

fn checkedLength(value: c.R_xlen_t) ?usize {
    if (value < 0) return null;
    return @intCast(value);
}

test "length conversion rejects negative values" {
    try std.testing.expectEqual(@as(?usize, null), checkedLength(-1));
    try std.testing.expectEqual(@as(?usize, 0), checkedLength(0));
    try std.testing.expectEqual(@as(?usize, 42), checkedLength(42));
}

test "read accessors preserve const borrows" {
    try std.testing.expect(@TypeOf(realRo) == fn (Sexp) ?[]const f64);
    try std.testing.expect(@TypeOf(intRo) == fn (Sexp) ?[]const c_int);
    try std.testing.expect(@TypeOf(stringElt) == fn (Sexp, usize) ?Sexp);
}
