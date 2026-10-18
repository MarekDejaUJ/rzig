//! Conversion between borrowed R values and Zig values.
//!
//! Everything here can allocate on the R side, so everything here can trigger
//! GC. Protect immediately after every allocation.

const std = @import("std");
const attributes = @import("attributes.zig");
const compat = @import("compat.zig");
const complex = @import("complex.zig");
const record = @import("record.zig");
const external = @import("external.zig");
const sparse = @import("sparse.zig");
const c = @import("c/abi.zig");
const es = @import("error_state.zig");
const list = @import("list.zig");
const matrix = @import("matrix.zig");
const na = @import("na.zig");
const protect = @import("protect.zig");
const sexp = @import("sexp.zig");
const rcall = @import("rcall.zig");
const Ctx = @import("alloc.zig").Ctx;

/// Opt-in mutable input. The wrapper duplicates the incoming SEXP first,
/// because R vectors are copy-on-modify and may be shared. `T` is `[]f64`,
/// `[]i32`, `rzig.Matrix` or `rzig.IntMatrix`; for a matrix, `data` is a
/// writable view with `nrow` and `ncol`.
pub fn Mut(comptime T: type) type {
    return struct {
        pub const rzig_mut_inner = T;

        /// Writable data backed by an R-owned duplicate of the input.
        data: MutableData(T),
    };
}

fn MutableData(comptime T: type) type {
    if (matrix.isMatrix(T)) return matrix.MutableMatrixOf(T.rzig_matrix_element);
    return T;
}

/// Report whether `T` is a mutable-input wrapper created by `Mut`.
pub fn isMutableInput(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"struct" => @hasDecl(T, "rzig_mut_inner"),
        else => false,
    };
}

/// Duplicate and protect a mutable input before exposing its storage.
pub fn fromMutableSexp(
    comptime T: type,
    stack: *protect.Stack,
    x: c.SEXP,
    comptime name: []const u8,
    mutable_result: *?c.SEXP,
) es.Error!T {
    if (comptime !isSupportedMutableInput(T)) {
        @compileError("rzig: rzig.Mut supports []f64, []i32, rzig.Matrix and rzig.IntMatrix");
    }
    const Inner = T.rzig_mut_inner;
    if (comptime Inner == []f64) {
        if (isInteger64(x)) {
            return es.raise(
                "rzig: {s} is a bit64::integer64 vector, whose values are not doubles; use as.numeric() in R",
                .{name},
            );
        }
        if (c.TYPEOF(x) != c.REALSXP) {
            return es.raise(
                "rzig: {s} must be a numeric vector for rzig.Mut([]f64); got {s}; use as.numeric() in R",
                .{ name, typeName(x) },
            );
        }
    } else if (comptime Inner == []i32) {
        if (c.TYPEOF(x) != c.INTSXP) {
            return es.raise(
                "rzig: {s} must be an integer vector for rzig.Mut([]i32); got {s}; use as.integer() in R",
                .{ name, typeName(x) },
            );
        }
    }
    // Matrices are validated like borrowed matrices: storage type, dim and length.
    const shape: ?MatrixShape = if (comptime matrix.isMatrix(Inner))
        try matrixShape(Inner.rzig_matrix_element, x, name)
    else
        null;

    const length = try vectorLength(x, name);
    std.debug.assert(mutable_result.* == null);
    const duplicate = stack.push(c.Rf_duplicate(x));
    mutable_result.* = duplicate;
    if (comptime Inner == []f64) return .{ .data = c.REAL(duplicate)[0..length] };
    if (comptime Inner == []i32) return .{ .data = c.INTEGER(duplicate)[0..length] };
    const Element = Inner.rzig_matrix_element;
    const data = if (comptime Element == f64) c.REAL(duplicate)[0..length] else c.INTEGER(duplicate)[0..length];
    return .{ .data = .{ .data = data, .nrow = shape.?.rows, .ncol = shape.?.columns } };
}

/// SEXP -> Zig. `pos` is the zero-based parameter index and `name` its
/// identifier, both used only to build a good error message.
pub fn fromSexp(
    comptime T: type,
    ctx: *Ctx,
    x: c.SEXP,
    comptime name: []const u8,
) es.Error!T {
    if (comptime T == f64) return scalarF64(x, name);
    if (comptime T == i32) return scalarI32(x, name, "i32");
    if (comptime T == bool) return scalarBool(x, name);
    if (comptime T == usize) return scalarUsize(x, name);
    if (comptime T == i64) return scalarI64(x, name);
    if (comptime T == []const i64) return integer64Slice(x, name);
    if (comptime T == []const f64) return realSlice(x, name);
    if (comptime T == []const i32) return integerSlice(x, name);
    if (comptime T == []const bool) return logicalSlice(ctx, x, name);
    if (comptime T == []const u8) return stringScalar(ctx, x, name);
    if (comptime T == []const []const u8) return stringSlice(ctx, x, name);
    if (comptime T == []const na.Logical) return logicalNaSlice(x, name);
    if (comptime T == []const ?[]const u8) return stringNaSlice(ctx, x, name);
    if (comptime T == ?[]const u8) return optionalString(ctx, x, name);
    if (comptime T == complex.Complex) return scalarComplex(x, name);
    if (comptime T == []const complex.Complex) return complexSlice(x, name);
    if (comptime T == complex.Raw) return rawFromSexp(x, name);
    if (comptime matrix.isMatrix(T)) return matrixFromSexp(T, ctx, x, name);
    if (comptime record.isRecord(T)) return recordFromSexp(T, ctx, x, name);
    if (comptime T == record.Factor) return factorFromSexp(ctx, x, name);
    if (comptime external.isExternal(T)) return externalFromSexp(T, ctx, x, name);
    if (comptime T == sparse.CscMatrix) return cscFromSexp(x, name);
    if (comptime T == sexp.Sexp) return sexp.fromRaw(x);
    if (comptime T == rcall.Function) return functionFromSexp(x, name);

    return switch (@typeInfo(T)) {
        .optional => |info| if (comptime isScalar(info.child))
            optionalScalar(info.child, ctx, x, name)
        else
            optionalValue(info.child, ctx, x, name),
        else => @compileError(unsupportedMessage(T, name)),
    };
}

const MatrixShape = struct {
    rows: usize,
    columns: usize,
    length: usize,
};

fn matrixFromSexp(comptime T: type, ctx: *Ctx, x: c.SEXP, comptime name: []const u8) es.Error!T {
    const Element = T.rzig_matrix_element;
    const shape = try matrixShape(Element, x, name);
    if (comptime Element == f64) {
        return .{ .data = c.REAL_RO(x)[0..shape.length], .nrow = shape.rows, .ncol = shape.columns };
    }
    if (comptime Element == i32) {
        return .{ .data = c.INTEGER_RO(x)[0..shape.length], .nrow = shape.rows, .ncol = shape.columns };
    }
    const source = c.LOGICAL_RO(x)[0..shape.length];
    for (source, 0..) |value, index| {
        if (na.isNaLogical(value)) {
            return es.raise(
                "rzig: {s} cannot contain NA; found NA at position {d}",
                .{ name, index + 1 },
            );
        }
    }
    const data = try ctx.alloc(bool, shape.length);
    for (source, data) |value, *slot| slot.* = value != c.FALSE;
    return .{ .data = data, .nrow = shape.rows, .ncol = shape.columns };
}

fn article(word: []const u8) []const u8 {
    return if (word.len > 0 and std.mem.indexOfScalar(u8, "aeiou", word[0]) != null) "an" else "a";
}

const MatrixKind = struct {
    sexp: c.SEXPTYPE,
    label: []const u8,
    storage: []const u8,
};

fn matrixKind(comptime Element: type) MatrixKind {
    return switch (Element) {
        f64 => .{ .sexp = c.REALSXP, .label = "a numeric", .storage = "double" },
        i32 => .{ .sexp = c.INTSXP, .label = "an integer", .storage = "integer" },
        bool => .{ .sexp = c.LGLSXP, .label = "a logical", .storage = "logical" },
        else => @compileError("rzig: matrices hold f64, i32 or bool elements"),
    };
}

/// Check the storage type, `dim` attribute and length of a matrix argument.
fn matrixShape(comptime Element: type, x: c.SEXP, comptime name: []const u8) es.Error!MatrixShape {
    const kind = comptime matrixKind(Element);
    if (c.Rf_isMatrix(x) == c.FALSE) {
        const dimensions = c.Rf_getAttrib(x, c.R_DimSymbol);
        if (c.TYPEOF(dimensions) == c.INTSXP) {
            return es.raise(
                "rzig: {s} must be " ++ kind.label ++ " matrix; got {s} {s} array with {d} dimensions",
                .{ name, article(typeName(x)), typeName(x), c.Rf_xlength(dimensions) },
            );
        }
        return es.raise(
            "rzig: {s} must be " ++ kind.label ++ " matrix; got {s} {s} vector without dimensions",
            .{ name, article(typeName(x)), typeName(x) },
        );
    }
    if (c.TYPEOF(x) != kind.sexp) {
        return es.raise(
            "rzig: {s} must store " ++ kind.storage ++ " values; got {s} {s} matrix; use storage.mode(x) <- \"" ++
                kind.storage ++ "\" in R",
            .{ name, article(typeName(x)), typeName(x) },
        );
    }

    const dimensions = c.Rf_getAttrib(x, c.R_DimSymbol);
    if (c.TYPEOF(dimensions) != c.INTSXP or c.Rf_xlength(dimensions) != 2) {
        return es.raise("rzig: {s} has a malformed matrix dimension attribute", .{name});
    }
    const raw_rows = c.INTEGER_ELT(dimensions, 0);
    const raw_columns = c.INTEGER_ELT(dimensions, 1);
    if (raw_rows < 0 or raw_columns < 0) {
        return es.raise("rzig: {s} has negative matrix dimensions", .{name});
    }
    const rows: usize = @intCast(raw_rows);
    const columns: usize = @intCast(raw_columns);
    const expected = std.math.mul(usize, rows, columns) catch
        return es.raise("rzig: {s} matrix dimensions exceed Zig's size limit", .{name});
    const length = try vectorLength(x, name);
    if (expected != length) {
        return es.raise(
            "rzig: {s} has dimensions {d} x {d} but contains {d} values",
            .{ name, rows, columns, length },
        );
    }

    return .{ .rows = rows, .columns = columns, .length = length };
}

/// Reject an unsupported exported-function parameter with full call-site
/// context while all names and types are still available at comptime.
pub fn validateInputType(
    comptime T: type,
    comptime function_name: []const u8,
    comptime position: usize,
) void {
    if (!isSupportedInput(T)) {
        @compileError(
            "rzig: function `" ++ function_name ++ "`, parameter " ++
                std.fmt.comptimePrint("{d}", .{position}) ++
                " has unsupported type '" ++ @typeName(T) ++ "'.\n" ++
                "  nearest supported alternative: " ++ nearestInputAlternative(T),
        );
    }
}

/// Reject an unsupported exported-function return with the function name and
/// closest representation that RZig can marshal.
pub fn validateReturnType(comptime T: type, comptime function_name: []const u8) void {
    if (!isSupportedReturn(T)) {
        @compileError(
            "rzig: function `" ++ function_name ++ "` has unsupported return type '" ++
                @typeName(T) ++ "'.\n" ++
                "  nearest supported alternative: " ++ nearestReturnAlternative(T),
        );
    }
}

/// Whether exported functions accept `T` (rzig.Function results use it).
pub fn supportsInput(comptime T: type) bool {
    return isSupportedInput(T);
}

/// Whether exported functions can return `T` (rzig.Function arguments use it).
pub fn supportsReturn(comptime T: type) bool {
    return isSupportedReturn(T);
}

fn functionFromSexp(x: c.SEXP, comptime name: []const u8) es.Error!rcall.Function {
    if (c.Rf_isFunction(x) == c.FALSE) {
        return es.raise("rzig: {s} must be a function; got {s}", .{ name, typeName(x) });
    }
    return .{ .object = x, .name = comptime rcall.callName(name) };
}

fn stringScalar(ctx: *Ctx, x: c.SEXP, comptime name: []const u8) es.Error![]const u8 {
    if (c.TYPEOF(x) != c.STRSXP) {
        return es.raise(
            "rzig: {s} must be a character vector of length 1; got {s}",
            .{ name, typeName(x) },
        );
    }
    const length = try vectorLength(x, name);
    if (length != 1) {
        return es.raise("rzig: {s} must have length 1; got length {d}", .{ name, length });
    }

    const element = c.STRING_ELT(x, 0);
    if (element == c.R_NaString) return es.raise("rzig: {s} cannot be NA", .{name});

    const mark = c.vmaxget();
    defer c.vmaxset(mark);
    return ctx.dupe(u8, try utf8Element(element, name));
}

/// The UTF-8 text of the CHARSXP `element` of `name`, in R's temporary storage.
/// R cannot translate a string in the "bytes" encoding and signals an R error
/// for one, so such a string is rejected before the translation.
fn utf8Element(element: c.SEXP, comptime name: []const u8) es.Error![]const u8 {
    if (c.Rf_getCharCE(element) == c.CE_BYTES) {
        return es.raise(
            "rzig: {s} contains a string in the \"bytes\" encoding, which cannot be translated to UTF-8",
            .{name},
        );
    }
    return std.mem.span(c.Rf_translateCharUTF8(element));
}

/// The text of a list or column name for matching and messages: UTF-8, or the
/// stored bytes of a name in the "bytes" encoding, which R cannot translate.
pub fn nameText(element: c.SEXP) []const u8 {
    if (c.Rf_getCharCE(element) == c.CE_BYTES) return std.mem.span(c.R_CHAR(element));
    return std.mem.span(c.Rf_translateCharUTF8(element));
}

fn stringSlice(ctx: *Ctx, x: c.SEXP, comptime name: []const u8) es.Error![]const []const u8 {
    if (c.TYPEOF(x) != c.STRSXP) {
        return es.raise(
            "rzig: {s} must be a character vector; got {s}",
            .{ name, typeName(x) },
        );
    }
    const length = try vectorLength(x, name);
    for (0..length) |index| {
        if (c.STRING_ELT(x, @intCast(index)) == c.R_NaString) {
            return es.raise(
                "rzig: {s} cannot contain NA; found NA at position {d}",
                .{ name, index + 1 },
            );
        }
    }

    const mark = c.vmaxget();
    defer c.vmaxset(mark);
    const result = try ctx.alloc([]const u8, length);
    for (result, 0..) |*slot, index| {
        const element = c.STRING_ELT(x, @intCast(index));
        slot.* = try ctx.dupe(u8, try utf8Element(element, name));
    }
    return result;
}

/// A borrowed view of a Matrix::dgCMatrix, checked slot by slot.
fn cscFromSexp(x: c.SEXP, comptime name: []const u8) es.Error!sparse.CscMatrix {
    if (c.Rf_isS4(x) == c.FALSE or c.Rf_inherits(x, "dgCMatrix") == c.FALSE) {
        return es.raise(
            "rzig: {s} must be a Matrix::dgCMatrix; got {s}; use as(as(x, \"generalMatrix\"), \"CsparseMatrix\") in R",
            .{ name, typeName(x) },
        );
    }
    const i_slot = c.Rf_getAttrib(x, c.Rf_install("i"));
    const p_slot = c.Rf_getAttrib(x, c.Rf_install("p"));
    const x_slot = c.Rf_getAttrib(x, c.Rf_install("x"));
    const dim_slot = c.Rf_getAttrib(x, c.Rf_install("Dim"));
    if (c.TYPEOF(i_slot) != c.INTSXP or c.TYPEOF(p_slot) != c.INTSXP or c.TYPEOF(x_slot) != c.REALSXP or
        c.TYPEOF(dim_slot) != c.INTSXP or c.Rf_xlength(dim_slot) != 2)
    {
        return es.raise("rzig: {s} is a dgCMatrix with malformed slots", .{name});
    }
    const rows = c.INTEGER_ELT(dim_slot, 0);
    const columns = c.INTEGER_ELT(dim_slot, 1);
    if (rows < 0 or columns < 0) return es.raise("rzig: {s} has negative dimensions", .{name});
    const row_indices = c.INTEGER_RO(i_slot)[0..try vectorLength(i_slot, name)];
    const col_pointers = c.INTEGER_RO(p_slot)[0..try vectorLength(p_slot, name)];
    const values = c.REAL_RO(x_slot)[0..try vectorLength(x_slot, name)];
    if (col_pointers.len == 0) return es.raise("rzig: {s} is a dgCMatrix with an empty slot p", .{name});
    if (sparse.problem(row_indices, col_pointers, values.len, @intCast(rows), @intCast(columns))) |what| {
        return es.raise("rzig: {s} is a dgCMatrix whose {s}", .{ name, what });
    }
    return .{
        .row_indices = row_indices,
        .col_pointers = col_pointers,
        .values = values,
        .nrow = @intCast(rows),
        .ncol = @intCast(columns),
    };
}

/// The value of an external pointer made by this library for the same type.
fn externalFromSexp(comptime E: type, ctx: *Ctx, x: c.SEXP, comptime name: []const u8) es.Error!E {
    const T = E.rzig_external_inner;
    const class = comptime external.shortName(T);
    if (c.TYPEOF(x) != c.EXTPTRSXP or c.R_ExternalPtrTag(x) != external.Holder(T).tag()) {
        return es.raise(
            "rzig: {s} must be a " ++ class ++ " made by this package; got {s}",
            .{ name, typeName(x) },
        );
    }
    const address = c.R_ExternalPtrAddr(x) orelse return es.raise(
        "rzig: {s} is a " ++ class ++ " whose Zig value was lost when R saved and restored it; create it again",
        .{name},
    );
    const holder: *external.Holder(T) = @ptrCast(@alignCast(address));
    ctx.noteExternalInput(holder, @ptrCast(x)) catch return es.raise("rzig: out of memory reading {s}", .{name});
    return .{ .ptr = &holder.value };
}

/// A named list or data frame read into the fields of a struct.
fn recordFromSexp(comptime T: type, ctx: *Ctx, x: c.SEXP, comptime name: []const u8) es.Error!T {
    const Inner = T.rzig_record_inner;
    const frame = comptime record.isDataFrame(T);
    if (comptime frame) {
        if (c.TYPEOF(x) != c.VECSXP or c.Rf_inherits(x, "data.frame") == c.FALSE) {
            return es.raise("rzig: {s} must be a data frame; got {s}", .{ name, typeName(x) });
        }
    } else if (c.TYPEOF(x) != c.VECSXP) {
        return es.raise(
            "rzig: {s} must be a named list; got {s}; use list(name = value) in R",
            .{ name, typeName(x) },
        );
    }
    const length = try vectorLength(x, name);
    const names = c.Rf_getAttrib(x, c.R_NamesSymbol);
    if (length > 0 and c.TYPEOF(names) != c.STRSXP) {
        return es.raise("rzig: {s} must be a named list; its entries have no names", .{name});
    }
    const rows: usize = if (comptime frame) dataFrameRows(x) else 0;

    const info = @typeInfo(Inner).@"struct";
    const field_names = comptime compat.fieldNames(info);
    const field_types = comptime compat.fieldTypes(info);
    var value: Inner = undefined;
    inline for (field_names, 0..) |field_name, index| {
        const Field = field_types[index];
        const label = name ++ (if (frame) ", column `" else ", entry `") ++ field_name ++ "`";
        if (try findEntry(names, length, field_name)) |position| {
            @field(value, field_name) = try fromSexp(Field, ctx, c.VECTOR_ELT(x, @intCast(position)), label);
            if (comptime frame) try checkColumnLength(@field(value, field_name), rows, label);
        } else if (comptime compat.fieldDefault(info, index)) |default| {
            @field(value, field_name) = default;
        } else if (comptime @typeInfo(Field) == .optional) {
            @field(value, field_name) = null;
        } else {
            return es.raise(
                "rzig: {s} has no " ++ (if (frame) "column" else "entry") ++ " `" ++ field_name ++ "`",
                .{name},
            );
        }
    }
    if (comptime !frame) try warnUnknownEntries(field_names, names, length, name);
    if (comptime frame) return .{ .value = value, .nrow = rows };
    return .{ .value = value };
}

/// The position of the first entry called `field_name`, or `null`.
fn findEntry(names: c.SEXP, length: usize, comptime field_name: []const u8) es.Error!?usize {
    if (c.TYPEOF(names) != c.STRSXP) return null;
    const mark = c.vmaxget();
    defer c.vmaxset(mark);
    for (0..length) |index| {
        const element = c.STRING_ELT(names, @intCast(index));
        if (element == c.R_NaString) continue;
        if (std.mem.eql(u8, nameText(element), field_name)) return index;
    }
    return null;
}

fn warnUnknownEntries(
    comptime field_names: []const [:0]const u8,
    names: c.SEXP,
    length: usize,
    comptime name: []const u8,
) es.Error!void {
    if (c.TYPEOF(names) != c.STRSXP) return;
    const mark = c.vmaxget();
    defer c.vmaxset(mark);
    for (0..length) |index| {
        const element = c.STRING_ELT(names, @intCast(index));
        const text = if (element == c.R_NaString)
            "NA"
        else if (c.Rf_getCharCE(element) == c.CE_BYTES)
            "(a name in the \"bytes\" encoding)"
        else
            nameText(element);
        var known = false;
        inline for (field_names) |field_name| {
            if (std.mem.eql(u8, text, field_name)) known = true;
        }
        if (!known) es.warn("rzig: {s} has an unknown entry `{s}`, which is ignored", .{ name, text });
    }
}

fn dataFrameRows(x: c.SEXP) usize {
    // R expands compact row names (c(NA, -n)) when they are read this way.
    const row_names = c.Rf_getAttrib(x, c.Rf_install("row.names"));
    return @intCast(@max(0, c.Rf_xlength(row_names)));
}

/// The number of values of a data frame column, or `null` for an absent one.
fn columnLength(column: anytype) ?usize {
    const Column = @TypeOf(column);
    if (comptime Column == record.Factor) return column.codes.len;
    return switch (@typeInfo(Column)) {
        .pointer => column.len,
        .optional => if (column) |present| columnLength(present) else null,
        else => null,
    };
}

fn checkColumnLength(column: anytype, rows: usize, comptime label: []const u8) es.Error!void {
    if (columnLength(column)) |count| {
        if (count != rows) {
            return es.raise("rzig: {s} has {d} values for {d} rows", .{ label, count, rows });
        }
    }
}

/// A factor: borrowed codes and copied levels.
fn factorFromSexp(ctx: *Ctx, x: c.SEXP, comptime name: []const u8) es.Error!record.Factor {
    if (c.TYPEOF(x) != c.INTSXP or c.Rf_inherits(x, "factor") == c.FALSE) {
        return es.raise("rzig: {s} must be a factor; got {s}; use factor() in R", .{ name, typeName(x) });
    }
    const levels = c.Rf_getAttrib(x, c.Rf_install("levels"));
    if (c.TYPEOF(levels) != c.STRSXP) {
        return es.raise("rzig: {s} is a factor without character levels", .{name});
    }
    const level_names = try stringSlice(ctx, levels, name ++ ", levels");
    const length = try vectorLength(x, name);
    const codes = c.INTEGER_RO(x)[0..length];
    for (codes, 0..) |code, index| {
        if (code == c.NA_INTEGER) continue;
        if (code < 1 or code > level_names.len) {
            return es.raise(
                "rzig: {s} has code {d} at position {d}, outside its {d} levels",
                .{ name, code, index + 1, level_names.len },
            );
        }
    }
    return .{ .codes = codes, .levels = level_names };
}

/// A complex scalar; a double or integer scalar becomes its real part.
fn scalarComplex(x: c.SEXP, comptime name: []const u8) es.Error!complex.Complex {
    const kind: c.SEXPTYPE = @intCast(c.TYPEOF(x));
    if (kind != c.CPLXSXP and kind != c.REALSXP and kind != c.INTSXP) {
        return es.raise(
            "rzig: {s} must be a complex, double, or integer vector of length 1; got {s}",
            .{ name, typeName(x) },
        );
    }
    const length = try vectorLength(x, name);
    if (length != 1) return es.raise("rzig: {s} must have length 1; got length {d}", .{ name, length });
    const value: complex.Complex = switch (kind) {
        c.CPLXSXP => .{ .re = c.COMPLEX_RO(x)[0].r, .im = c.COMPLEX_RO(x)[0].i },
        c.REALSXP => .{ .re = c.REAL_ELT(x, 0), .im = 0 },
        else => if (na.isNaInt(c.INTEGER_ELT(x, 0)))
            .{ .re = na.real, .im = 0 }
        else
            .{ .re = @floatFromInt(c.INTEGER_ELT(x, 0)), .im = 0 },
    };
    if (na.isNaReal(value.re) or na.isNaReal(value.im)) {
        return es.raise("rzig: {s} cannot be NA", .{name});
    }
    return value;
}

/// A borrowed complex vector; NA and NaN parts are passed through.
fn complexSlice(x: c.SEXP, comptime name: []const u8) es.Error![]const complex.Complex {
    if (c.TYPEOF(x) != c.CPLXSXP) {
        return es.raise(
            "rzig: {s} must be a complex vector; got {s}; use as.complex() in R",
            .{ name, typeName(x) },
        );
    }
    const length = try vectorLength(x, name);
    const data: [*]const complex.Complex = @ptrCast(c.COMPLEX_RO(x));
    return data[0..length];
}

/// The borrowed bytes of a raw vector.
fn rawFromSexp(x: c.SEXP, comptime name: []const u8) es.Error!complex.Raw {
    if (c.TYPEOF(x) != c.RAWSXP) {
        return es.raise(
            "rzig: {s} must be a raw vector; got {s}; use as.raw() or charToRaw() in R",
            .{ name, typeName(x) },
        );
    }
    const length = try vectorLength(x, name);
    return .{ .data = c.RAW_RO(x)[0..length] };
}

/// A borrowed logical vector that keeps NA.
fn logicalNaSlice(x: c.SEXP, comptime name: []const u8) es.Error![]const na.Logical {
    if (c.TYPEOF(x) != c.LGLSXP) {
        return es.raise(
            "rzig: {s} must be a logical vector; got {s}",
            .{ name, typeName(x) },
        );
    }
    const length = try vectorLength(x, name);
    const data: [*]const na.Logical = @ptrCast(c.LOGICAL_RO(x));
    return data[0..length];
}

/// A copied character vector in which NA becomes `null`.
fn stringNaSlice(ctx: *Ctx, x: c.SEXP, comptime name: []const u8) es.Error![]const ?[]const u8 {
    if (c.TYPEOF(x) != c.STRSXP) {
        return es.raise(
            "rzig: {s} must be a character vector; got {s}",
            .{ name, typeName(x) },
        );
    }
    const length = try vectorLength(x, name);
    const mark = c.vmaxget();
    defer c.vmaxset(mark);
    const result = try ctx.alloc(?[]const u8, length);
    for (result, 0..) |*slot, index| {
        const element = c.STRING_ELT(x, @intCast(index));
        slot.* = if (element == c.R_NaString)
            null
        else
            try ctx.dupe(u8, try utf8Element(element, name));
    }
    return result;
}

/// A character scalar; NA and NULL become `null`.
fn optionalString(ctx: *Ctx, x: c.SEXP, comptime name: []const u8) es.Error!?[]const u8 {
    if (c.Rf_isNull(x) != c.FALSE) return null;
    if (c.TYPEOF(x) == c.STRSXP and c.Rf_xlength(x) == 1 and c.STRING_ELT(x, 0) == c.R_NaString) return null;
    if (c.TYPEOF(x) == c.LGLSXP and c.Rf_xlength(x) == 1 and na.isNaLogical(c.LOGICAL_ELT(x, 0))) return null;
    return try stringScalar(ctx, x, name);
}

fn realSlice(x: c.SEXP, comptime name: []const u8) es.Error![]const f64 {
    if (isInteger64(x)) {
        return es.raise(
            "rzig: {s} is a bit64::integer64 vector, whose values are not doubles; use []const i64 in Zig or as.numeric() in R",
            .{name},
        );
    }
    if (c.TYPEOF(x) != c.REALSXP) {
        return es.raise(
            "rzig: {s} must be a numeric vector; got {s}; use as.numeric() in R",
            .{ name, typeName(x) },
        );
    }
    const length = try vectorLength(x, name);
    return c.REAL_RO(x)[0..length];
}

fn integerSlice(x: c.SEXP, comptime name: []const u8) es.Error![]const i32 {
    if (c.TYPEOF(x) != c.INTSXP) {
        return es.raise(
            "rzig: {s} must be an integer vector; got {s}; use as.integer() in R",
            .{ name, typeName(x) },
        );
    }
    const length = try vectorLength(x, name);
    return c.INTEGER_RO(x)[0..length];
}

fn logicalSlice(ctx: *Ctx, x: c.SEXP, comptime name: []const u8) es.Error![]const bool {
    if (c.TYPEOF(x) != c.LGLSXP) {
        return es.raise(
            "rzig: {s} must be a logical vector; got {s}",
            .{ name, typeName(x) },
        );
    }
    const length = try vectorLength(x, name);
    const source = c.LOGICAL_RO(x)[0..length];
    for (source, 0..) |value, index| {
        if (na.isNaLogical(value)) {
            return es.raise(
                "rzig: {s} cannot contain NA; found NA at position {d}",
                .{ name, index + 1 },
            );
        }
    }

    const result = try ctx.alloc(bool, length);
    for (source, result) |value, *slot| slot.* = value != c.FALSE;
    return result;
}

fn vectorLength(x: c.SEXP, comptime name: []const u8) es.Error!usize {
    const length = c.Rf_xlength(x);
    if (length < 0) {
        return es.raise("rzig: {s} has an invalid negative length", .{name});
    }
    return @intCast(length);
}

fn optionalScalar(
    comptime T: type,
    ctx: *Ctx,
    x: c.SEXP,
    comptime name: []const u8,
) es.Error!?T {
    if (comptime !isScalar(T)) @compileError(unsupportedMessage(?T, name));
    if (c.Rf_isNull(x) != c.FALSE) return null;

    try validateScalar(T, x, name);
    if (scalarIsNa(x)) return null;
    return try fromSexp(T, ctx, x, name);
}

/// A non-scalar input that may be NULL, which becomes `null`.
fn optionalValue(comptime T: type, ctx: *Ctx, x: c.SEXP, comptime name: []const u8) es.Error!?T {
    if (c.Rf_isNull(x) != c.FALSE) return null;
    return try fromSexp(T, ctx, x, name);
}

fn scalarF64(x: c.SEXP, comptime name: []const u8) es.Error!f64 {
    try validateScalar(f64, x, name);
    const value = switch (@as(c.SEXPTYPE, @intCast(c.TYPEOF(x)))) {
        c.REALSXP => c.REAL_ELT(x, 0),
        c.INTSXP => @as(f64, @floatFromInt(c.INTEGER_ELT(x, 0))),
        c.LGLSXP => @as(f64, @floatFromInt(c.LOGICAL_ELT(x, 0))),
        else => return es.raise("rzig: internal scalar conversion error for {s}", .{name}),
    };
    if (scalarIsNa(x)) {
        return es.raise("rzig: {s} cannot be NA; use ?f64 to accept missing values", .{name});
    }
    return value;
}

fn scalarI32(
    x: c.SEXP,
    comptime name: []const u8,
    comptime target_name: []const u8,
) es.Error!i32 {
    try validateScalar(i32, x, name);
    if (scalarIsNa(x)) {
        return es.raise(
            "rzig: {s} cannot be NA; use ?{s} to accept missing values",
            .{ name, target_name },
        );
    }

    return switch (@as(c.SEXPTYPE, @intCast(c.TYPEOF(x)))) {
        c.INTSXP => @intCast(c.INTEGER_ELT(x, 0)),
        c.LGLSXP => @intCast(c.LOGICAL_ELT(x, 0)),
        c.REALSXP => realToI32(c.REAL_ELT(x, 0), name),
        else => es.raise("rzig: internal scalar conversion error for {s}", .{name}),
    };
}

fn realToI32(value: f64, comptime name: []const u8) es.Error!i32 {
    const min: f64 = @floatFromInt(std.math.minInt(i32));
    const max: f64 = @floatFromInt(std.math.maxInt(i32));
    if (!std.math.isFinite(value) or @trunc(value) != value or value < min or value > max) {
        return es.raise(
            "rzig: {s} must be a whole number representable as i32; got {d}",
            .{ name, value },
        );
    }
    return @intFromFloat(value);
}

fn scalarBool(x: c.SEXP, comptime name: []const u8) es.Error!bool {
    try validateScalar(bool, x, name);
    const value = c.LOGICAL_ELT(x, 0);
    if (na.isNaLogical(value)) {
        return es.raise("rzig: {s} cannot be NA; use ?bool to accept missing values", .{name});
    }
    return value != c.FALSE;
}

fn scalarUsize(x: c.SEXP, comptime name: []const u8) es.Error!usize {
    try validateScalar(usize, x, name);
    if (scalarIsNa(x)) {
        return es.raise("rzig: {s} cannot be NA; use ?usize to accept missing values", .{name});
    }

    const kind: c.SEXPTYPE = @intCast(c.TYPEOF(x));
    const value: f64 = switch (kind) {
        c.INTSXP => @floatFromInt(c.INTEGER_ELT(x, 0)),
        c.LGLSXP => @floatFromInt(c.LOGICAL_ELT(x, 0)),
        c.REALSXP => c.REAL_ELT(x, 0),
        else => return es.raise("rzig: internal scalar conversion error for {s}", .{name}),
    };
    if (std.math.isFinite(value) and value < 0) {
        return es.raise("rzig: {s} must be non-negative; got {d}", .{ name, value });
    }
    // The range of R's integers, so package code can store the value in an
    // i32; counts beyond it use i64.
    const max: f64 = @floatFromInt(std.math.maxInt(i32));
    if (!std.math.isFinite(value) or @trunc(value) != value or value > max) {
        return es.raise(
            "rzig: {s} must be a whole number from 0 to 2147483647; got {d}; use i64 for larger counts",
            .{ name, value },
        );
    }
    return @intFromFloat(value);
}

fn validateScalar(comptime T: type, x: c.SEXP, comptime name: []const u8) es.Error!void {
    const kind: c.SEXPTYPE = @intCast(c.TYPEOF(x));
    if (comptime T != i64) {
        if (isInteger64(x)) {
            return es.raise(
                "rzig: {s} is a bit64::integer64 value, whose bits are not a double; use i64 in Zig or as.numeric() in R",
                .{name},
            );
        }
    }
    const valid_type = if (comptime T == bool)
        kind == c.LGLSXP
    else
        kind == c.REALSXP or kind == c.INTSXP or kind == c.LGLSXP;

    if (!valid_type) {
        if (comptime T == bool) {
            return es.raise(
                "rzig: {s} must be a logical vector of length 1; got {s}",
                .{ name, typeName(x) },
            );
        }
        return es.raise(
            "rzig: {s} must be a double, integer, or logical vector of length 1; got {s}",
            .{ name, typeName(x) },
        );
    }

    const length = c.Rf_xlength(x);
    if (length != 1) {
        return es.raise("rzig: {s} must have length 1; got length {d}", .{ name, length });
    }
}

fn scalarIsNa(x: c.SEXP) bool {
    const kind: c.SEXPTYPE = @intCast(c.TYPEOF(x));
    return switch (kind) {
        c.REALSXP => if (isInteger64(x))
            @as(i64, @bitCast(c.REAL_ELT(x, 0))) == std.math.minInt(i64)
        else
            na.isNaReal(c.REAL_ELT(x, 0)),
        c.INTSXP => na.isNaInt(c.INTEGER_ELT(x, 0)),
        c.LGLSXP => na.isNaLogical(c.LOGICAL_ELT(x, 0)),
        else => false,
    };
}

fn isScalar(comptime T: type) bool {
    return T == f64 or T == i32 or T == bool or T == usize or T == i64;
}

/// A double vector with class `integer64` (package bit64): each element holds
/// the bits of a 64-bit integer, and the smallest one is NA.
fn isInteger64(x: c.SEXP) bool {
    return c.TYPEOF(x) == c.REALSXP and c.Rf_inherits(x, "integer64") != c.FALSE;
}

fn scalarI64(x: c.SEXP, comptime name: []const u8) es.Error!i64 {
    try validateScalar(i64, x, name);
    if (scalarIsNa(x)) {
        return es.raise("rzig: {s} cannot be NA; use ?i64 to accept missing values", .{name});
    }
    const kind: c.SEXPTYPE = @intCast(c.TYPEOF(x));
    switch (kind) {
        c.INTSXP => return c.INTEGER_ELT(x, 0),
        c.LGLSXP => return c.LOGICAL_ELT(x, 0),
        c.REALSXP => {
            if (isInteger64(x)) return @bitCast(c.REAL_ELT(x, 0));
            const value = c.REAL_ELT(x, 0);
            if (!std.math.isFinite(value) or @trunc(value) != value or @abs(value) > max_exact_double) {
                return es.raise(
                    "rzig: {s} must be a whole number from -9007199254740991 to 9007199254740991, " ++
                        "or a bit64::integer64; got {d}",
                    .{ name, value },
                );
            }
            return @intFromFloat(value);
        },
        else => return es.raise("rzig: internal scalar conversion error for {s}", .{name}),
    }
}

/// 2^53 - 1, the largest integer a double holds exactly.
const max_exact_double: f64 = 9007199254740991;

/// A borrowed bit64::integer64 vector; NA is `std.math.minInt(i64)`.
fn integer64Slice(x: c.SEXP, comptime name: []const u8) es.Error![]const i64 {
    if (!isInteger64(x)) {
        return es.raise(
            "rzig: {s} must be a bit64::integer64 vector; got {s}; use bit64::as.integer64() in R",
            .{ name, typeName(x) },
        );
    }
    const length = try vectorLength(x, name);
    const data: [*]const i64 = @ptrCast(@alignCast(c.REAL_RO(x)));
    return data[0..length];
}

fn isSupportedInput(comptime T: type) bool {
    if (isSupportedMutableInput(T)) return true;
    if (record.isRecord(T)) return isSupportedRecordInput(T);
    if (T == record.Factor) return true;
    if (isSupportedExternal(T)) return true;
    if (isScalar(T) or
        T == []const f64 or
        T == []const i32 or
        T == []const i64 or
        T == []const bool or
        T == []const u8 or
        T == []const []const u8 or
        T == []const na.Logical or
        T == []const ?[]const u8 or
        T == ?[]const u8 or
        T == complex.Complex or
        T == []const complex.Complex or
        T == complex.Raw or
        T == matrix.Matrix or
        T == matrix.IntMatrix or
        T == matrix.BoolMatrix or
        T == sparse.CscMatrix or
        T == sexp.Sexp or
        T == rcall.Function)
    {
        return true;
    }
    return switch (@typeInfo(T)) {
        .optional => |info| isScalar(info.child) or
            (@typeInfo(info.child) != .optional and !isMutableInput(info.child) and isSupportedInput(info.child)),
        else => false,
    };
}

fn isSupportedExternal(comptime T: type) bool {
    return external.isExternal(T);
}

fn isSupportedRecordInput(comptime T: type) bool {
    if (!record.isRecord(T)) return false;
    const info = @typeInfo(T.rzig_record_inner).@"struct";
    inline for (comptime compat.fieldTypes(info)) |Field| {
        if (isMutableInput(Field) or !isSupportedInput(Field)) return false;
        if (comptime record.isDataFrame(T) and !isColumnInput(Field)) return false;
    }
    return true;
}

fn isColumnInput(comptime T: type) bool {
    const Column = switch (@typeInfo(T)) {
        .optional => |info| info.child,
        else => T,
    };
    return Column == record.Factor or switch (@typeInfo(Column)) {
        .pointer => |info| info.size == .slice,
        else => false,
    };
}

fn isSupportedRecordReturn(comptime T: type) bool {
    if (!record.isRecord(T)) return false;
    const info = @typeInfo(T.rzig_record_inner).@"struct";
    inline for (comptime compat.fieldTypes(info)) |Field| {
        if (Field == void or !isSupportedReturn(Field)) return false;
        if (comptime record.isDataFrame(T) and !(Field == record.Factor or isSupportedVectorReturn(Field))) return false;
    }
    return true;
}

fn isSupportedMutableInput(comptime T: type) bool {
    if (!isMutableInput(T)) return false;
    const Inner = T.rzig_mut_inner;
    return Inner == []f64 or Inner == []i32 or Inner == matrix.Matrix or Inner == matrix.IntMatrix;
}

fn isSupportedReturn(comptime T: type) bool {
    if (isSupportedAttributedReturn(T)) return true;
    if (record.isRecord(T)) return isSupportedRecordReturn(T);
    if (T == record.Factor) return true;
    if (isSupportedExternal(T)) return true;
    if (T == void or
        T == f64 or
        T == i32 or
        T == i64 or
        T == []const i64 or
        T == []i64 or
        T == bool or
        T == []const f64 or
        T == []f64 or
        T == []const i32 or
        T == []i32 or
        T == []const bool or
        T == []bool or
        T == []const u8 or
        T == []const []const u8 or
        T == [][]const u8 or
        T == []const na.Logical or
        T == []na.Logical or
        T == []const ?[]const u8 or
        T == []?[]const u8 or
        T == complex.Complex or
        T == []const complex.Complex or
        T == []complex.Complex or
        T == complex.Raw or
        T == list.List or
        T == sexp.Sexp or
        T == rcall.Function)
    {
        return true;
    }
    return switch (@typeInfo(T)) {
        .optional => |info| isSupportedReturn(info.child),
        else => false,
    };
}

fn isSupportedAttributedReturn(comptime T: type) bool {
    if (!attributes.isAttributed(T)) return false;
    return isSupportedVectorReturn(T.rzig_attributed_inner);
}

fn isSupportedVectorReturn(comptime T: type) bool {
    return T == []const f64 or T == []f64 or
        T == []const i32 or T == []i32 or
        T == []const bool or T == []bool or
        T == []const na.Logical or T == []na.Logical or
        T == []const []const u8 or T == [][]const u8 or
        T == []const ?[]const u8 or T == []?[]const u8 or
        T == []const complex.Complex or T == []complex.Complex;
}

fn nearestInputAlternative(comptime T: type) []const u8 {
    if (isMutableInput(T)) {
        return "rzig.Mut([]f64), rzig.Mut([]i32), rzig.Mut(rzig.Matrix) or rzig.Mut(rzig.IntMatrix) " ++
            "for a duplicated writable vector or matrix";
    }
    if (T == [][]const f64 or T == []const []const f64) return "rzig.Matrix for an R numeric matrix";
    if (T == [][]const i32 or T == []const []const i32) return "rzig.IntMatrix for an R integer matrix";
    if (T == [][]const bool or T == []const []const bool) return "rzig.BoolMatrix for an R logical matrix";
    if (T == f32 or T == f16 or T == f128) return "f64 for an R numeric scalar";
    if (T == []const f32 or T == []const f16 or T == []const f128 or
        T == []f32 or T == []f16 or T == []f128)
    {
        return "[]const f64 for an R numeric vector";
    }
    if (T == []f64) return "[]const f64 for a borrowed read-only numeric vector";
    if (T == []i32) return "[]const i32 for a borrowed read-only integer vector";
    if (T == []bool) return "[]const bool for a borrowed read-only logical vector";
    if (T == []na.Logical) return "[]const rzig.Logical for a borrowed logical vector that keeps NA";
    if (T == []complex.Complex) return "[]const rzig.Complex for a borrowed complex vector";
    if (T == std.math.Complex(f64)) return "rzig.Complex for an R complex scalar (convert with toStd())";
    if (T == []?[]const u8 or T == []const ?[]u8) return "[]const ?[]const u8 for a character vector that keeps NA";
    if (T == []u8) return "[]const u8 for a UTF-8 string";
    if (@typeInfo(T) == .@"fn" or
        (@typeInfo(T) == .pointer and @typeInfo(@typeInfo(T).pointer.child) == .@"fn"))
    {
        return "rzig.Function for an R function";
    }

    return switch (@typeInfo(T)) {
        .float => "f64 for an R numeric scalar",
        .int => |info| if (info.bits > 32)
            "i64 for an R integer64 or whole-number scalar"
        else if (info.signedness == .signed)
            "i32 for an R integer scalar"
        else
            "usize for a non-negative R integer scalar",
        .pointer => |info| switch (@typeInfo(info.child)) {
            .bool => "[]const bool for an R logical vector",
            .float => "[]const f64 for an R numeric vector",
            .int => |child| if (info.child == u8)
                "[]const u8 for a UTF-8 string"
            else if (child.bits > 32)
                "[]const i64 for a bit64::integer64 vector"
            else
                "[]const i32 for an R integer vector",
            else => "rzig.Sexp for explicit low-level handling",
        },
        .optional => |info| nearestInputAlternative(info.child),
        .array => |info| switch (@typeInfo(info.child)) {
            .float => "[]const f64 for an R numeric vector",
            .int => if (info.child == u8)
                "[]const u8 for a UTF-8 string"
            else
                "[]const i32 for an R integer vector",
            else => "rzig.Sexp for explicit low-level handling",
        },
        else => "rzig.Sexp for explicit low-level handling",
    };
}

fn nearestReturnAlternative(comptime T: type) []const u8 {
    if (attributes.isAttributed(T)) return "rzig.Attributed(T) where T is a supported vector return";
    if (T == usize) return "i32 for an R integer scalar";
    if (T == f32 or T == f16 or T == f128) return "f64 for an R numeric scalar";
    if (T == []const f32 or T == []const f16 or T == []const f128 or
        T == []f32 or T == []f16 or T == []f128)
    {
        return "[]const f64 for an R numeric vector";
    }

    return switch (@typeInfo(T)) {
        .float => "f64 for an R numeric scalar",
        .int => "i32 for an R integer scalar",
        .pointer => "[]const u8 for a UTF-8 string or rzig.Sexp for low-level handling",
        .optional => |info| nearestReturnAlternative(info.child),
        .array => "[]const f64 for an R numeric vector",
        else => "rzig.Sexp for explicit low-level handling",
    };
}

/// Zig -> SEXP. Pushes onto `stack` immediately after allocating.
pub fn toSexp(
    stack: *protect.Stack,
    ctx: *Ctx,
    value: anytype,
) es.Error!c.SEXP {
    const T = @TypeOf(value);
    if (comptime T == void) return c.R_NilValue;
    if (comptime T == f64) return realScalarToSexp(stack, value);
    if (comptime T == i32) return integerScalarToSexp(stack, value);
    if (comptime T == i64) return integer64ToSexp(stack, &.{value});
    if (comptime T == []const i64 or T == []i64) return integer64ToSexp(stack, value);
    if (comptime T == bool) return logicalScalarToSexp(stack, value);
    if (comptime T == []const f64 or T == []f64) return realSliceToSexp(stack, value);
    if (comptime T == []const i32 or T == []i32) return integerSliceToSexp(stack, value);
    if (comptime T == []const bool or T == []bool) return logicalSliceToSexp(stack, value);
    if (comptime T == []const u8) return stringToSexp(stack, value);
    if (comptime T == []const []const u8 or T == [][]const u8) return stringSliceToSexp(stack, value);
    if (comptime T == []const na.Logical or T == []na.Logical) return logicalNaSliceToSexp(stack, value);
    if (comptime T == []const ?[]const u8 or T == []?[]const u8) return stringNaSliceToSexp(stack, value);
    if (comptime T == complex.Complex) return complexSliceToSexp(stack, &.{value});
    if (comptime T == []const complex.Complex or T == []complex.Complex) return complexSliceToSexp(stack, value);
    if (comptime T == complex.Raw) return rawToSexp(stack, value);
    if (comptime attributes.isAttributed(T)) return attributedToSexp(stack, ctx, value);
    if (comptime T == list.List) return listToSexp(stack, ctx, value);
    if (comptime record.isRecord(T)) return recordToSexp(stack, ctx, value);
    if (comptime T == record.Factor) return factorToSexp(stack, ctx, value);
    if (comptime external.isExternal(T)) return externalToSexp(stack, ctx, value);
    if (comptime T == sexp.Sexp) return stack.push(sexp.toRaw(value));
    if (comptime T == rcall.Function) return stack.push(value.object);

    return switch (@typeInfo(T)) {
        .optional => if (value) |present|
            toSexp(stack, ctx, present)
        else
            c.R_NilValue,
        else => @compileError(unsupportedReturnMessage(T)),
    };
}

fn attributedToSexp(stack: *protect.Stack, ctx: *Ctx, value: anytype) es.Error!c.SEXP {
    const metadata = value.metadata();
    const value_length = value.value.len;
    try validateAttributes(metadata, value_length);

    const result = try toSexp(stack, ctx, value.value);
    if (metadata.dim) |dimensions| try attachDim(stack, result, dimensions);
    if (metadata.row_names != null or metadata.column_names != null) {
        try attachDimnames(stack, result, metadata.row_names, metadata.column_names);
    }
    if (metadata.names) |names| try attachStringAttribute(stack, result, c.R_NamesSymbol, names);
    if (metadata.class) |classes| try attachStringAttribute(stack, result, c.R_ClassSymbol, classes);
    return result;
}

fn validateAttributes(metadata: attributes.Metadata, value_length: usize) es.Error!void {
    if (metadata.names) |names| {
        _ = try returnLength(names.len);
        if (names.len != value_length) {
            return es.raise(
                "rzig: `names` has length {d}, but the returned vector has length {d}",
                .{ names.len, value_length },
            );
        }
        try validateAttributeStrings(names, "names");
    }
    if (metadata.dim) |dimensions| {
        _ = try returnLength(dimensions.len);
        if (dimensions.len == 0) return es.raise("rzig: `dim` must contain at least one dimension", .{});
        var product: usize = 1;
        for (dimensions, 0..) |dimension, index| {
            if (dimension < 0) {
                return es.raise(
                    "rzig: `dim` value at position {d} must be non-negative; got {d}",
                    .{ index + 1, dimension },
                );
            }
            product = std.math.mul(usize, product, @intCast(dimension)) catch
                return es.raise("rzig: `dim` product exceeds Zig's size limit", .{});
        }
        if (product != value_length) {
            return es.raise(
                "rzig: `dim` describes {d} values, but the returned vector has length {d}",
                .{ product, value_length },
            );
        }
    }
    if (metadata.class) |classes| {
        if (classes.len == 0) return es.raise("rzig: `class` must contain at least one string", .{});
        _ = try returnLength(classes.len);
        try validateAttributeStrings(classes, "class");
    }
    if (metadata.row_names != null or metadata.column_names != null) {
        const dimensions = metadata.dim orelse
            return es.raise("rzig: `dimnames` needs `dim`; call setMatrix() or setDim() first", .{});
        if (dimensions.len != 2) {
            return es.raise("rzig: `dimnames` needs a two-dimensional `dim`; got {d} dimensions", .{dimensions.len});
        }
        if (metadata.row_names) |names| {
            if (names.len != @as(usize, @intCast(dimensions[0]))) {
                return es.raise("rzig: {d} row names for {d} rows", .{ names.len, dimensions[0] });
            }
            try validateAttributeStrings(names, "dimnames");
        }
        if (metadata.column_names) |names| {
            if (names.len != @as(usize, @intCast(dimensions[1]))) {
                return es.raise("rzig: {d} column names for {d} columns", .{ names.len, dimensions[1] });
            }
            try validateAttributeStrings(names, "dimnames");
        }
    }
}

fn validateAttributeStrings(values: []const []const u8, comptime attribute_name: []const u8) es.Error!void {
    for (values, 0..) |value, index| {
        if (!std.unicode.utf8ValidateSlice(value)) {
            return es.raise(
                "rzig: `{s}` string at position {d} is not valid UTF-8",
                .{ attribute_name, index + 1 },
            );
        }
        if (std.mem.indexOfScalar(u8, value, 0) != null) {
            return es.raise(
                "rzig: `{s}` string at position {d} contains an embedded NUL byte",
                .{ attribute_name, index + 1 },
            );
        }
        if (value.len > std.math.maxInt(c_int)) {
            return es.raise(
                "rzig: `{s}` string at position {d} exceeds R's string limit",
                .{ attribute_name, index + 1 },
            );
        }
    }
}

fn attachDim(stack: *protect.Stack, result: c.SEXP, dimensions: []const i32) es.Error!void {
    const attribute = stack.push(c.Rf_allocVector(c.INTSXP, try returnLength(dimensions.len)));
    if (dimensions.len > 0) @memcpy(c.INTEGER(attribute)[0..dimensions.len], dimensions);
    _ = c.Rf_setAttrib(result, c.R_DimSymbol, attribute);
    stack.pop(1);
}

fn attachDimnames(
    stack: *protect.Stack,
    result: c.SEXP,
    row_names: ?[]const []const u8,
    column_names: ?[]const []const u8,
) es.Error!void {
    const dimnames = stack.push(c.Rf_allocVector(c.VECSXP, 2));
    for ([_]?[]const []const u8{ row_names, column_names }, 0..) |maybe_names, index| {
        const names = maybe_names orelse continue;
        const strings = stack.push(c.Rf_allocVector(c.STRSXP, try returnLength(names.len)));
        for (names, 0..) |value, position| {
            const element = c.Rf_mkCharLenCE(value.ptr, @intCast(value.len), c.CE_UTF8);
            c.SET_STRING_ELT(strings, @intCast(position), element);
        }
        _ = c.SET_VECTOR_ELT(dimnames, @intCast(index), strings);
        stack.pop(1);
    }
    _ = c.Rf_setAttrib(result, c.R_DimNamesSymbol, dimnames);
    stack.pop(1);
}

fn attachStringAttribute(
    stack: *protect.Stack,
    result: c.SEXP,
    symbol: c.SEXP,
    values: []const []const u8,
) es.Error!void {
    const attribute = stack.push(c.Rf_allocVector(c.STRSXP, try returnLength(values.len)));
    for (values, 0..) |value, index| {
        const element = c.Rf_mkCharLenCE(value.ptr, @intCast(value.len), c.CE_UTF8);
        c.SET_STRING_ELT(attribute, @intCast(index), element);
    }
    _ = c.Rf_setAttrib(result, symbol, attribute);
    stack.pop(1);
}

/// A double vector with class `integer64` holding the bits of `value`.
fn integer64ToSexp(stack: *protect.Stack, value: []const i64) es.Error!c.SEXP {
    const length = try returnLength(value.len);
    const result = stack.push(c.Rf_allocVector(c.REALSXP, length));
    const target: [*]i64 = @ptrCast(@alignCast(c.REAL(result)));
    if (value.len > 0) @memcpy(target[0..value.len], value);
    const class = stack.push(c.Rf_mkString("integer64"));
    _ = c.Rf_setAttrib(result, c.R_ClassSymbol, class);
    stack.pop(1);
    return result;
}

fn realScalarToSexp(stack: *protect.Stack, value: f64) c.SEXP {
    const result = stack.push(c.Rf_allocVector(c.REALSXP, 1));
    c.REAL(result)[0] = value;
    return result;
}

fn integerScalarToSexp(stack: *protect.Stack, value: i32) c.SEXP {
    const result = stack.push(c.Rf_allocVector(c.INTSXP, 1));
    c.INTEGER(result)[0] = value;
    return result;
}

fn logicalScalarToSexp(stack: *protect.Stack, value: bool) c.SEXP {
    const result = stack.push(c.Rf_allocVector(c.LGLSXP, 1));
    c.LOGICAL(result)[0] = if (value) c.TRUE else c.FALSE;
    return result;
}

fn realSliceToSexp(stack: *protect.Stack, value: []const f64) es.Error!c.SEXP {
    const length = try returnLength(value.len);
    const result = stack.push(c.Rf_allocVector(c.REALSXP, length));
    if (value.len > 0) @memcpy(c.REAL(result)[0..value.len], value);
    return result;
}

fn integerSliceToSexp(stack: *protect.Stack, value: []const i32) es.Error!c.SEXP {
    const length = try returnLength(value.len);
    const result = stack.push(c.Rf_allocVector(c.INTSXP, length));
    if (value.len > 0) @memcpy(c.INTEGER(result)[0..value.len], value);
    return result;
}

fn logicalSliceToSexp(stack: *protect.Stack, value: []const bool) es.Error!c.SEXP {
    const length = try returnLength(value.len);
    const result = stack.push(c.Rf_allocVector(c.LGLSXP, length));
    for (value, c.LOGICAL(result)[0..value.len]) |source, *target| {
        target.* = if (source) c.TRUE else c.FALSE;
    }
    return result;
}

fn complexSliceToSexp(stack: *protect.Stack, value: []const complex.Complex) es.Error!c.SEXP {
    const length = try returnLength(value.len);
    const result = stack.push(c.Rf_allocVector(c.CPLXSXP, length));
    for (value, c.COMPLEX(result)[0..value.len]) |source, *target| target.* = .{ .r = source.re, .i = source.im };
    return result;
}

fn rawToSexp(stack: *protect.Stack, value: complex.Raw) es.Error!c.SEXP {
    const length = try returnLength(value.data.len);
    const result = stack.push(c.Rf_allocVector(c.RAWSXP, length));
    if (value.data.len > 0) @memcpy(c.RAW(result)[0..value.data.len], value.data);
    return result;
}

fn logicalNaSliceToSexp(stack: *protect.Stack, value: []const na.Logical) es.Error!c.SEXP {
    const length = try returnLength(value.len);
    const result = stack.push(c.Rf_allocVector(c.LGLSXP, length));
    for (value, c.LOGICAL(result)[0..value.len]) |source, *target| target.* = @intFromEnum(source);
    return result;
}

fn stringNaSliceToSexp(stack: *protect.Stack, value: []const ?[]const u8) es.Error!c.SEXP {
    _ = try returnLength(value.len);
    for (value, 0..) |maybe, index| {
        const text = maybe orelse continue;
        if (!std.unicode.utf8ValidateSlice(text)) {
            return es.raise("rzig: returned string at position {d} is not valid UTF-8", .{index + 1});
        }
        if (std.mem.indexOfScalar(u8, text, 0) != null) {
            return es.raise("rzig: returned string at position {d} contains an embedded NUL byte", .{index + 1});
        }
        if (text.len > std.math.maxInt(c_int)) {
            return es.raise("rzig: returned string at position {d} exceeds R's string limit", .{index + 1});
        }
    }
    const result = stack.push(c.Rf_allocVector(c.STRSXP, try returnLength(value.len)));
    for (value, 0..) |maybe, index| {
        const element = if (maybe) |text|
            c.Rf_mkCharLenCE(text.ptr, @intCast(text.len), c.CE_UTF8)
        else
            c.R_NaString;
        c.SET_STRING_ELT(result, @intCast(index), element);
    }
    return result;
}

fn stringToSexp(stack: *protect.Stack, value: []const u8) es.Error!c.SEXP {
    try validateReturnedString(value);

    const result = stack.push(c.Rf_allocVector(c.STRSXP, 1));
    const element = c.Rf_mkCharLenCE(value.ptr, @intCast(value.len), c.CE_UTF8);
    c.SET_STRING_ELT(result, 0, element);
    return result;
}

fn stringSliceToSexp(stack: *protect.Stack, value: []const []const u8) es.Error!c.SEXP {
    try validateReturnedStrings(value);

    const result = stack.push(c.Rf_allocVector(c.STRSXP, try returnLength(value.len)));
    for (value, 0..) |element_value, index| {
        const element = c.Rf_mkCharLenCE(
            element_value.ptr,
            @intCast(element_value.len),
            c.CE_UTF8,
        );
        c.SET_STRING_ELT(result, @intCast(index), element);
    }
    return result;
}

/// A named list, or a data frame with compact row names, from the fields.
fn recordToSexp(stack: *protect.Stack, ctx: *Ctx, value: anytype) es.Error!c.SEXP {
    const T = @TypeOf(value);
    const frame = comptime record.isDataFrame(T);
    const info = @typeInfo(T.rzig_record_inner).@"struct";
    const field_names = comptime compat.fieldNames(info);

    var rows: usize = 0;
    if (comptime frame) {
        inline for (field_names, 0..) |field_name, index| {
            const length = columnLength(@field(value.value, field_name)).?;
            if (index == 0) {
                rows = length;
            } else if (length != rows) {
                return es.raise(
                    "rzig: data frame column `" ++ field_name ++ "` has {d} values, but the first column has {d}",
                    .{ length, rows },
                );
            }
        }
        if (rows > std.math.maxInt(i32)) return es.raise("rzig: a data frame has at most 2147483647 rows", .{});
    }
    // Symbols first: installing one can allocate.
    const row_names_symbol: ?c.SEXP = if (comptime frame) c.Rf_install("row.names") else null;

    const result = stack.push(c.Rf_allocVector(c.VECSXP, @intCast(field_names.len)));
    const names = stack.push(c.Rf_allocVector(c.STRSXP, @intCast(field_names.len)));
    inline for (field_names, 0..) |field_name, index| {
        c.SET_STRING_ELT(names, index, c.Rf_mkCharLenCE(field_name.ptr, @intCast(field_name.len), c.CE_UTF8));
        const checkpoint = stack.count;
        const element = try toSexp(stack, ctx, @field(value.value, field_name));
        _ = c.SET_VECTOR_ELT(result, index, element);
        stack.pop(stack.count - checkpoint);
    }
    _ = c.Rf_setAttrib(result, c.R_NamesSymbol, names);
    stack.pop(1);
    if (comptime frame) {
        const class = stack.push(c.Rf_mkString("data.frame"));
        _ = c.Rf_setAttrib(result, c.R_ClassSymbol, class);
        stack.pop(1);
        const row_names = stack.push(c.Rf_allocVector(c.INTSXP, 2));
        c.INTEGER(row_names)[0] = c.NA_INTEGER;
        c.INTEGER(row_names)[1] = -@as(c_int, @intCast(rows));
        _ = c.Rf_setAttrib(result, row_names_symbol.?, row_names);
        stack.pop(1);
    }
    return result;
}

/// The R object for a value of `rzig.External`: a new external pointer for a
/// value created in this call, or the object an input value came from.
fn externalToSexp(stack: *protect.Stack, ctx: *Ctx, value: anytype) es.Error!c.SEXP {
    const T = @TypeOf(value).rzig_external_inner;
    const Holder = external.Holder(T);
    const class_name = comptime external.shortName(T);
    const holder: *Holder = @fieldParentPtr("value", value.ptr);
    if (ctx.externalObject(holder)) |object| return stack.push(@ptrCast(object));

    // Symbols first: installing one can allocate.
    const tag = Holder.tag();
    const result = stack.push(c.R_MakeExternalPtr(holder, tag, c.R_NilValue));
    c.R_RegisterCFinalizerEx(result, Holder.finalize, c.TRUE);
    if (!ctx.releaseExternal(holder)) {
        // Not created by this call and not one of its inputs: R must not own it.
        c.R_ClearExternalPtr(result);
        return es.raise(
            "rzig: a " ++ class_name ++ " can be returned only by the call that created it or received it",
            .{},
        );
    }
    const class = stack.push(c.Rf_allocVector(c.STRSXP, 2));
    c.SET_STRING_ELT(class, 0, c.Rf_mkCharLenCE(class_name.ptr, @intCast(class_name.len), c.CE_UTF8));
    c.SET_STRING_ELT(class, 1, c.Rf_mkCharLenCE("rzig_external", 13, c.CE_UTF8));
    _ = c.Rf_setAttrib(result, c.R_ClassSymbol, class);
    stack.pop(1);
    return result;
}

/// An integer vector with `levels` and class `factor`.
fn factorToSexp(stack: *protect.Stack, ctx: *Ctx, value: record.Factor) es.Error!c.SEXP {
    for (value.codes, 0..) |code, index| {
        if (code == c.NA_INTEGER) continue;
        if (code < 1 or code > value.levels.len) {
            return es.raise(
                "rzig: returned factor has code {d} at position {d}, outside its {d} levels",
                .{ code, index + 1, value.levels.len },
            );
        }
    }
    try validateReturnedStrings(value.levels);
    const levels_symbol = c.Rf_install("levels");
    const result = try integerSliceToSexp(stack, value.codes);
    const checkpoint = stack.count;
    const levels = try toSexp(stack, ctx, value.levels);
    _ = c.Rf_setAttrib(result, levels_symbol, levels);
    stack.pop(stack.count - checkpoint);
    const class = stack.push(c.Rf_mkString("factor"));
    _ = c.Rf_setAttrib(result, c.R_ClassSymbol, class);
    stack.pop(1);
    return result;
}

fn listToSexp(stack: *protect.Stack, ctx: *Ctx, value: list.List) es.Error!c.SEXP {
    const entries = value.items();
    const length = try returnLength(entries.len);

    // Check every recoverable condition before the first R allocation. Once
    // materialization begins, only R API failures can interrupt the pass, and
    // the enclosing R_UnwindProtect callback owns Zig-side cleanup.
    for (entries, 0..) |entry, index| {
        try validateListName(entry.name, index + 1);
        switch (entry.value) {
            .reals => |reals| _ = try returnLength(reals.len),
            .integers => |integers| _ = try returnLength(integers.len),
            .logicals => |logicals| _ = try returnLength(logicals.len),
            .string => |string| try validateListString(string, index + 1),
            .strings => |strings| {
                _ = try returnLength(strings.len);
                for (strings) |string| try validateListString(string, index + 1);
            },
            else => {},
        }
    }

    const result = stack.push(c.Rf_allocVector(c.VECSXP, length));
    if (entries.len == 0) return result;
    const names = stack.push(c.Rf_allocVector(c.STRSXP, length));

    for (entries, 0..) |entry, index| {
        const r_index: c.R_xlen_t = @intCast(index);
        const name = c.Rf_mkCharLenCE(entry.name.ptr, @intCast(entry.name.len), c.CE_UTF8);
        c.SET_STRING_ELT(names, r_index, name);

        const checkpoint = stack.count;
        const element = try listValueToSexp(stack, ctx, entry.value);
        _ = c.SET_VECTOR_ELT(result, r_index, element);
        stack.pop(stack.count - checkpoint);
    }

    _ = c.Rf_setAttrib(result, c.R_NamesSymbol, names);
    stack.pop(1);
    return result;
}

fn listValueToSexp(stack: *protect.Stack, ctx: *Ctx, value: list.Value) es.Error!c.SEXP {
    return switch (value) {
        .nil => c.R_NilValue,
        .real => |real| realScalarToSexp(stack, real),
        .integer => |integer| integerScalarToSexp(stack, integer),
        .logical => |logical| logicalScalarToSexp(stack, logical),
        .reals => |reals| realSliceToSexp(stack, reals),
        .integers => |integers| integerSliceToSexp(stack, integers),
        .logicals => |logicals| logicalSliceToSexp(stack, logicals),
        .string => |string| stringToSexp(stack, string),
        .strings => |strings| stringSliceToSexp(stack, strings),
        .sexp => |value_sexp| toSexp(stack, ctx, value_sexp),
    };
}

fn validateReturnedString(value: []const u8) es.Error!void {
    if (!std.unicode.utf8ValidateSlice(value)) {
        return es.raise("rzig: returned string is not valid UTF-8", .{});
    }
    if (std.mem.indexOfScalar(u8, value, 0) != null) {
        return es.raise("rzig: returned string contains an embedded NUL byte", .{});
    }
    if (value.len > std.math.maxInt(c_int)) {
        return es.raise("rzig: returned string has {d} bytes, exceeding R's limit", .{value.len});
    }
}

fn validateReturnedStrings(values: []const []const u8) es.Error!void {
    _ = try returnLength(values.len);
    for (values, 0..) |value, index| {
        if (!std.unicode.utf8ValidateSlice(value)) {
            return es.raise("rzig: returned string at position {d} is not valid UTF-8", .{index + 1});
        }
        if (std.mem.indexOfScalar(u8, value, 0) != null) {
            return es.raise("rzig: returned string at position {d} contains an embedded NUL byte", .{index + 1});
        }
        if (value.len > std.math.maxInt(c_int)) {
            return es.raise("rzig: returned string at position {d} exceeds R's string limit", .{index + 1});
        }
    }
}

fn validateListName(value: []const u8, position: usize) es.Error!void {
    if (!std.unicode.utf8ValidateSlice(value)) {
        return es.raise("rzig: list name at position {d} is not valid UTF-8", .{position});
    }
    if (std.mem.indexOfScalar(u8, value, 0) != null) {
        return es.raise("rzig: list name at position {d} contains an embedded NUL byte", .{position});
    }
    if (value.len > std.math.maxInt(c_int)) {
        return es.raise("rzig: list name at position {d} exceeds R's string limit", .{position});
    }
}

fn validateListString(value: []const u8, position: usize) es.Error!void {
    if (!std.unicode.utf8ValidateSlice(value)) {
        return es.raise("rzig: list string at position {d} is not valid UTF-8", .{position});
    }
    if (std.mem.indexOfScalar(u8, value, 0) != null) {
        return es.raise("rzig: list string at position {d} contains an embedded NUL byte", .{position});
    }
    if (value.len > std.math.maxInt(c_int)) {
        return es.raise("rzig: list string at position {d} exceeds R's string limit", .{position});
    }
}

fn returnLength(length: usize) es.Error!c.R_xlen_t {
    if (length > std.math.maxInt(c.R_xlen_t)) {
        return es.raise("rzig: returned vector length {d} exceeds R's limit", .{length});
    }
    return @intCast(length);
}

/// Compile-error text. Message quality is a first-class feature here - it is
/// most of what RZig offers over hand-written glue. Always name the parameter,
/// the type, the supported set, and the likely intended alternative.
fn unsupportedMessage(comptime T: type, comptime name: []const u8) []const u8 {
    return "rzig: parameter `" ++ name ++ "` has unsupported type '" ++ @typeName(T) ++ "'.\n" ++
        "  supported: f64, i32, bool, usize, ?T,\n" ++
        "             []const f64, []const i32, []const bool, []const u8, []const []const u8, rzig.Matrix,\n" ++
        "             rzig.Sexp (escape hatch)\n" ++
        "  nearest supported alternative: " ++ nearestInputAlternative(T) ++ "\n" ++
        "  for a mutable vector use rzig.Mut([]f64)\n" ++
        "  note []f64 is NOT accepted as an input: R inputs are borrowed and read-only";
}

fn unsupportedReturnMessage(comptime T: type) []const u8 {
    return "rzig: unsupported return type '" ++ @typeName(T) ++ "'.\n" ++
        "  supported: void, f64, i32, bool, atomic vector slices, []const u8, ?T, rzig.List,\n" ++
        "             rzig.Attributed(T), rzig.Sexp\n" ++
        "  nearest supported alternative: " ++ nearestReturnAlternative(T);
}

/// Human-readable R type name, for runtime error messages. Never say "SEXP" or
/// "REALSXP" to an R user.
pub fn typeName(x: c.SEXP) []const u8 {
    return std.mem.span(c.Rf_type2char(@intCast(c.TYPEOF(x))));
}
