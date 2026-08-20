//! Finds public Zig functions marked with `/// @export` and emits generated bindings.

const std = @import("std");

const max_source_bytes = 16 * 1024 * 1024;

const Export = struct {
    name: []u8,
    identifier: []u8,
    doc: []u8,
    parameters: []const []u8,

    fn deinit(self: Export, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.identifier);
        allocator.free(self.doc);
        for (self.parameters) |parameter| allocator.free(parameter);
        allocator.free(self.parameters);
    }
};

pub fn main(init: std.process.Init) !void {
    var args = try std.process.Args.iterateAllocator(init.minimal.args, init.gpa);
    defer args.deinit();
    _ = args.next();
    const input_path = args.next() orelse return error.MissingInputPath;
    const manifest_path = args.next() orelse return error.MissingManifestPath;
    const wrappers_path = args.next();
    const namespace_path = if (wrappers_path != null)
        args.next() orelse return error.MissingNamespacePath
    else
        null;
    const package = if (wrappers_path != null)
        args.next() orelse return error.MissingPackageName
    else
        null;
    if (args.next() != null) return error.UnexpectedArgument;

    const source = try std.Io.Dir.cwd().readFileAllocOptions(
        init.io,
        input_path,
        init.gpa,
        .limited(max_source_bytes),
        .of(u8),
        0,
    );
    defer init.gpa.free(source);

    const exports = try scanExports(init.gpa, source);
    defer freeExports(init.gpa, exports);

    const manifest = try renderManifestFromExports(init.gpa, exports);
    defer init.gpa.free(manifest);
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = manifest_path, .data = manifest });

    if (wrappers_path) |path| {
        const wrappers = try renderRWrappersFromExports(init.gpa, exports);
        defer init.gpa.free(wrappers);
        try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = path, .data = wrappers });

        const namespace = try renderNamespaceFromExports(init.gpa, exports, package.?);
        defer init.gpa.free(namespace);
        try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = namespace_path.?, .data = namespace });
    }
}

fn scanExports(allocator: std.mem.Allocator, source: [:0]const u8) ![]Export {
    var tree = try std.zig.Ast.parse(allocator, source, .zig);
    defer tree.deinit(allocator);
    if (tree.errors.len != 0) return error.InvalidZigSource;

    var exports: std.ArrayList(Export) = .empty;
    errdefer {
        for (exports.items) |item| item.deinit(allocator);
        exports.deinit(allocator);
    }

    for (tree.rootDecls()) |decl| {
        var buffer: [1]std.zig.Ast.Node.Index = undefined;
        const proto = tree.fullFnProto(&buffer, decl) orelse continue;
        if (proto.visib_token == null) continue;
        const name_token = proto.name_token orelse continue;
        const doc_start = firstDocToken(&tree, proto.firstToken()) orelse continue;
        const doc_end = proto.firstToken() - 1;
        if (!hasExportMarker(&tree, doc_start, doc_end)) continue;

        const identifier = tree.tokenSlice(name_token);
        const display_name = try identifierName(allocator, identifier);
        defer if (display_name.owned) |owned| allocator.free(owned);

        var doc: std.ArrayList(u8) = .empty;
        defer doc.deinit(allocator);
        try collectDocumentation(allocator, &doc, &tree, doc_start, doc_end);

        var parameters: std.ArrayList([]u8) = .empty;
        errdefer {
            for (parameters.items) |parameter| allocator.free(parameter);
            parameters.deinit(allocator);
        }
        var iterator = proto.iterate(&tree);
        var parameter_index: usize = 0;
        while (iterator.next()) |parameter| : (parameter_index += 1) {
            if (parameter_index == 0 and isContextParameter(&tree, parameter)) continue;
            const parameter_token = parameter.name_token orelse return error.UnnamedExportParameter;
            const raw_parameter = tree.tokenSlice(parameter_token);
            const parameter_name = try identifierName(allocator, raw_parameter);
            defer if (parameter_name.owned) |owned| allocator.free(owned);
            const owned_parameter = try allocator.dupe(u8, parameter_name.bytes);
            parameters.append(allocator, owned_parameter) catch |err| {
                allocator.free(owned_parameter);
                return err;
            };
        }

        const owned_parameters = try parameters.toOwnedSlice(allocator);
        errdefer {
            for (owned_parameters) |parameter| allocator.free(parameter);
            allocator.free(owned_parameters);
        }
        const owned_name = try allocator.dupe(u8, display_name.bytes);
        errdefer allocator.free(owned_name);
        const owned_identifier = try allocator.dupe(u8, identifier);
        errdefer allocator.free(owned_identifier);
        const owned_doc = try doc.toOwnedSlice(allocator);
        errdefer allocator.free(owned_doc);

        try exports.append(allocator, .{
            .name = owned_name,
            .identifier = owned_identifier,
            .doc = owned_doc,
            .parameters = owned_parameters,
        });
    }

    return exports.toOwnedSlice(allocator);
}

fn freeExports(allocator: std.mem.Allocator, exports: []Export) void {
    for (exports) |item| item.deinit(allocator);
    allocator.free(exports);
}

fn renderManifest(allocator: std.mem.Allocator, source: [:0]const u8) ![]u8 {
    const exports = try scanExports(allocator, source);
    defer freeExports(allocator, exports);
    return renderManifestFromExports(allocator, exports);
}

fn renderManifestFromExports(allocator: std.mem.Allocator, exports: []const Export) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    try out.appendSlice(allocator,
        \\//! GENERATED by tools/scan.zig - do not edit.
        \\//! Regenerate with `zig build gen` or `rzig::document()`.
        \\
        \\/// Bind exported function names to the package's root Zig module.
        \\pub fn Bind(comptime root: type) type {
        \\    return struct {
        \\        const bound_root = root;
        \\
        \\        /// Metadata for public functions exposed through RZig.
        \\        pub const exports = .{
        \\
    );

    for (exports) |item| {
        try out.print(allocator,
            \\            .{{
            \\                .name = "{f}",
            \\                .func = bound_root.{s},
            \\                .doc = "{f}",
            \\                .parameters = .{{
        , .{
            std.zig.fmtString(item.name),
            item.identifier,
            std.zig.fmtString(item.doc),
        });
        for (item.parameters, 0..) |parameter, index| {
            if (index != 0) try out.appendSlice(allocator, ", ");
            try out.print(allocator, "\"{f}\"", .{std.zig.fmtString(parameter)});
        }
        try out.appendSlice(allocator,
            \\},
            \\            },
            \\
        );
    }

    try out.appendSlice(allocator,
        \\        };
        \\    };
        \\}
        \\
    );
    return out.toOwnedSlice(allocator);
}

fn renderRWrappers(allocator: std.mem.Allocator, source: [:0]const u8) ![]u8 {
    const exports = try scanExports(allocator, source);
    defer freeExports(allocator, exports);
    return renderRWrappersFromExports(allocator, exports);
}

fn renderRWrappersFromExports(allocator: std.mem.Allocator, exports: []const Export) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    try out.appendSlice(allocator, "# Generated by rzig::document(). Do not edit.\n");

    for (exports, 0..) |item, index| {
        const alias = try nativeAlias(allocator, exports, index);
        defer allocator.free(alias);

        try out.appendSlice(allocator, "\n");
        try appendRoxygenBlock(allocator, &out, item);
        try appendRIdentifier(allocator, &out, item.name);
        try out.appendSlice(allocator, " <- function(");
        for (item.parameters, 0..) |parameter, parameter_index| {
            if (parameter_index != 0) try out.appendSlice(allocator, ", ");
            try appendRIdentifier(allocator, &out, parameter);
        }
        try out.appendSlice(allocator, ") {\n  .Call(");
        try out.appendSlice(allocator, alias);
        for (item.parameters) |parameter| {
            try out.appendSlice(allocator, ", ");
            try appendRIdentifier(allocator, &out, parameter);
        }
        try out.appendSlice(allocator, ")\n}\n");
    }

    return out.toOwnedSlice(allocator);
}

fn appendRoxygenBlock(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    item: Export,
) !void {
    if (item.doc.len == 0 or firstDocumentationLineIsTag(item.doc)) {
        try out.appendSlice(allocator, "#' Call ");
        try appendRIdentifier(allocator, out, item.name);
        try out.appendSlice(allocator, " in Zig.\n");
    }
    if (item.doc.len > 0) {
        var lines = std.mem.splitScalar(u8, item.doc, '\n');
        while (lines.next()) |line| {
            try out.appendSlice(allocator, "#'");
            if (line.len > 0) {
                try out.append(allocator, ' ');
                try out.appendSlice(allocator, line);
            }
            try out.append(allocator, '\n');
        }
    }

    try out.appendSlice(allocator, "#'\n");
    for (item.parameters) |parameter| {
        if (documentationHasParameter(item.doc, parameter)) continue;
        try out.appendSlice(allocator, "#' @param ");
        try appendRIdentifier(allocator, out, parameter);
        try out.appendSlice(allocator, " A value passed to the Zig implementation.\n");
    }
    if (!documentationHasTag(item.doc, "@return")) {
        try out.appendSlice(allocator, "#' @return The value returned by the Zig implementation.\n");
    }
    try out.appendSlice(allocator, "#' @export\n");
}

fn firstDocumentationLineIsTag(doc: []const u8) bool {
    var lines = std.mem.splitScalar(u8, doc, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        return trimmed[0] == '@';
    }
    return false;
}

fn documentationHasTag(doc: []const u8, tag: []const u8) bool {
    var lines = std.mem.splitScalar(u8, doc, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (!std.mem.startsWith(u8, trimmed, tag)) continue;
        if (trimmed.len == tag.len or std.ascii.isWhitespace(trimmed[tag.len])) return true;
    }
    return false;
}

fn documentationHasParameter(doc: []const u8, parameter: []const u8) bool {
    var lines = std.mem.splitScalar(u8, doc, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (!std.mem.startsWith(u8, trimmed, "@param")) continue;
        if (trimmed.len == "@param".len or !std.ascii.isWhitespace(trimmed["@param".len])) continue;
        const declared = std.mem.trimStart(u8, trimmed["@param".len..], " \t");
        if (parameterNameMatches(declared, parameter)) return true;
    }
    return false;
}

fn parameterNameMatches(declared: []const u8, parameter: []const u8) bool {
    if (declared.len >= parameter.len and std.mem.eql(u8, declared[0..parameter.len], parameter)) {
        return declared.len == parameter.len or std.ascii.isWhitespace(declared[parameter.len]);
    }
    if (declared.len < parameter.len + 2 or declared[0] != '`') return false;
    if (!std.mem.eql(u8, declared[1 .. parameter.len + 1], parameter)) return false;
    if (declared[parameter.len + 1] != '`') return false;
    return declared.len == parameter.len + 2 or std.ascii.isWhitespace(declared[parameter.len + 2]);
}

fn renderNamespace(
    allocator: std.mem.Allocator,
    source: [:0]const u8,
    package: []const u8,
) ![]u8 {
    const exports = try scanExports(allocator, source);
    defer freeExports(allocator, exports);
    return renderNamespaceFromExports(allocator, exports, package);
}

fn renderNamespaceFromExports(
    allocator: std.mem.Allocator,
    exports: []const Export,
    package: []const u8,
) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    try out.appendSlice(allocator, "# Generated by rzig::document(): begin\nuseDynLib(");
    try appendRString(allocator, &out, package);
    for (exports, 0..) |item, index| {
        const alias = try nativeAlias(allocator, exports, index);
        defer allocator.free(alias);
        try out.appendSlice(allocator, ",\n  ");
        try out.appendSlice(allocator, alias);
        try out.appendSlice(allocator, " = ");
        try appendRString(allocator, &out, item.name);
    }
    try out.appendSlice(allocator, "\n)\n");
    for (exports) |item| {
        try out.appendSlice(allocator, "export(");
        try appendRString(allocator, &out, item.name);
        try out.appendSlice(allocator, ")\n");
    }
    try out.appendSlice(allocator, "# Generated by rzig::document(): end\n");
    return out.toOwnedSlice(allocator);
}

fn nativeAlias(
    allocator: std.mem.Allocator,
    exports: []const Export,
    index: usize,
) ![]u8 {
    const preferred = try std.fmt.allocPrint(allocator, "{s}_", .{exports[index].name});
    if (isRSyntacticName(preferred) and !hasExportName(exports, preferred)) return preferred;
    allocator.free(preferred);

    var ordinal = index + 1;
    while (true) : (ordinal += exports.len + 1) {
        const fallback = try std.fmt.allocPrint(allocator, ".rzig_symbol_{d}", .{ordinal});
        if (!hasExportName(exports, fallback)) return fallback;
        allocator.free(fallback);
    }
}

fn hasExportName(exports: []const Export, candidate: []const u8) bool {
    for (exports) |item| {
        if (std.mem.eql(u8, item.name, candidate)) return true;
    }
    return false;
}

fn isRSyntacticName(name: []const u8) bool {
    if (name.len == 0) return false;
    const first_ok = std.ascii.isAlphabetic(name[0]) or
        (name[0] == '.' and (name.len == 1 or !std.ascii.isDigit(name[1])));
    if (!first_ok) return false;
    for (name[1..]) |byte| {
        if (!std.ascii.isAlphanumeric(byte) and byte != '.' and byte != '_') return false;
    }
    return true;
}

fn appendRIdentifier(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    identifier: []const u8,
) !void {
    if (isRSyntacticName(identifier) and !isRReservedWord(identifier)) {
        try out.appendSlice(allocator, identifier);
        return;
    }
    try out.append(allocator, '`');
    for (identifier) |byte| {
        if (byte == '\\' or byte == '`') try out.append(allocator, '\\');
        try out.append(allocator, byte);
    }
    try out.append(allocator, '`');
}

fn appendRString(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    value: []const u8,
) !void {
    try out.append(allocator, '"');
    for (value) |byte| switch (byte) {
        '"', '\\' => {
            try out.append(allocator, '\\');
            try out.append(allocator, byte);
        },
        '\n' => try out.appendSlice(allocator, "\\n"),
        '\r' => try out.appendSlice(allocator, "\\r"),
        '\t' => try out.appendSlice(allocator, "\\t"),
        0...8, 11, 12, 14...31, 127 => return error.UnsupportedRString,
        else => try out.append(allocator, byte),
    };
    try out.append(allocator, '"');
}

fn isRReservedWord(name: []const u8) bool {
    const words = [_][]const u8{
        "if",            "else",  "repeat", "while", "function", "for", "in",          "next",     "break",
        "TRUE",          "FALSE", "NULL",   "Inf",   "NaN",      "NA",  "NA_integer_", "NA_real_", "NA_complex_",
        "NA_character_",
    };
    for (words) |word| {
        if (std.mem.eql(u8, name, word)) return true;
    }
    return false;
}

fn isContextParameter(tree: *const std.zig.Ast, parameter: std.zig.Ast.full.FnProto.Param) bool {
    const type_expr = parameter.type_expr orelse return false;
    return nodeTokensEqual(tree, type_expr, "*Ctx") or
        nodeTokensEqual(tree, type_expr, "*rzig.Ctx");
}

fn nodeTokensEqual(tree: *const std.zig.Ast, node: std.zig.Ast.Node.Index, expected: []const u8) bool {
    var expected_index: usize = 0;
    var token = tree.firstToken(node);
    const last = tree.lastToken(node);
    while (token <= last) : (token += 1) {
        const slice = tree.tokenSlice(token);
        if (!std.mem.startsWith(u8, expected[expected_index..], slice)) return false;
        expected_index += slice.len;
        if (expected_index > expected.len) return false;
    }
    return expected_index == expected.len;
}

fn firstDocToken(tree: *const std.zig.Ast, declaration_first: std.zig.Ast.TokenIndex) ?std.zig.Ast.TokenIndex {
    if (declaration_first == 0) return null;
    var token = declaration_first - 1;
    if (tree.tokenTag(token) != .doc_comment) return null;
    while (token > 0 and tree.tokenTag(token - 1) == .doc_comment) token -= 1;
    return token;
}

fn hasExportMarker(
    tree: *const std.zig.Ast,
    start: std.zig.Ast.TokenIndex,
    end: std.zig.Ast.TokenIndex,
) bool {
    var token = start;
    while (token <= end) : (token += 1) {
        if (std.mem.eql(u8, std.mem.trim(u8, docBody(tree.tokenSlice(token)), " \t\r"), "@export")) {
            return true;
        }
    }
    return false;
}

fn collectDocumentation(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    tree: *const std.zig.Ast,
    start: std.zig.Ast.TokenIndex,
    end: std.zig.Ast.TokenIndex,
) !void {
    var wrote_line = false;
    var token = start;
    while (token <= end) : (token += 1) {
        const line = docBody(tree.tokenSlice(token));
        if (std.mem.eql(u8, std.mem.trim(u8, line, " \t\r"), "@export")) continue;
        if (wrote_line) try out.append(allocator, '\n');
        try out.appendSlice(allocator, line);
        wrote_line = true;
    }
}

fn docBody(token: []const u8) []const u8 {
    const body = token[3..];
    return if (body.len > 0 and body[0] == ' ') body[1..] else body;
}

const IdentifierName = struct {
    bytes: []const u8,
    owned: ?[]u8 = null,
};

fn identifierName(allocator: std.mem.Allocator, token: []const u8) !IdentifierName {
    if (std.mem.startsWith(u8, token, "@\"") and std.mem.endsWith(u8, token, "\"")) {
        const parsed = try std.zig.string_literal.parseAlloc(allocator, token[1..]);
        return .{ .bytes = parsed, .owned = parsed };
    }
    return .{ .bytes = token };
}

test "manifest contains exports, parameters, and documentation" {
    const source: [:0]const u8 =
        \\const rzig = @import("rzig");
        \\
        \\/// Add "values".
        \\/// Preserves \ paths.
        \\/// @export
        \\pub fn add_values(ctx: *rzig.Ctx, a: f64, b: f64) f64 {
        \\    _ = ctx;
        \\    return a + b;
        \\}
        \\
        \\/// @export
        \\fn private_helper() void {}
        \\
        \\/// Ordinary public helper.
        \\pub fn helper() void {}
        \\
    ;

    const manifest = try renderManifest(std.testing.allocator, source);
    defer std.testing.allocator.free(manifest);

    try std.testing.expect(std.mem.indexOf(u8, manifest, "pub fn Bind(comptime root: type) type") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, ".name = \"add_values\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, ".func = bound_root.add_values") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, ".doc = \"Add \\\"values\\\".\\nPreserves \\\\ paths.\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, ".parameters = .{\"a\", \"b\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "private_helper") == null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "bound_root.helper") == null);
}

test "R wrappers omit context and use registered symbol objects" {
    const source: [:0]const u8 =
        \\const rzig = @import("rzig");
        \\
        \\/// Add two values.
        \\/// @param left The left-hand value.
        \\/// @export
        \\pub fn add_values(ctx: *rzig.Ctx, left: f64, right: f64) f64 {
        \\    _ = ctx;
        \\    return left + right;
        \\}
        \\
    ;

    const wrappers = try renderRWrappers(std.testing.allocator, source);
    defer std.testing.allocator.free(wrappers);
    try std.testing.expect(std.mem.indexOf(u8, wrappers, "#' Add two values.") != null);
    try std.testing.expect(std.mem.indexOf(u8, wrappers, "#' @param left The left-hand value.") != null);
    try std.testing.expect(std.mem.indexOf(u8, wrappers, "#' @param right A value passed to the Zig implementation.") != null);
    try std.testing.expect(std.mem.indexOf(u8, wrappers, "#' @return The value returned by the Zig implementation.") != null);
    try std.testing.expect(std.mem.indexOf(u8, wrappers, "#' @export") != null);
    try std.testing.expect(std.mem.indexOf(u8, wrappers, "add_values <- function(left, right)") != null);
    try std.testing.expect(std.mem.indexOf(u8, wrappers, ".Call(add_values_, left, right)") != null);
    try std.testing.expect(std.mem.indexOf(u8, wrappers, "ctx") == null);

    const namespace = try renderNamespace(std.testing.allocator, source, "testpkg");
    defer std.testing.allocator.free(namespace);
    try std.testing.expect(std.mem.indexOf(u8, namespace, "useDynLib(\"testpkg\",") != null);
    try std.testing.expect(std.mem.indexOf(u8, namespace, ".registration") == null);
    try std.testing.expect(std.mem.indexOf(u8, namespace, "add_values_ = \"add_values\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, namespace, "export(\"add_values\")") != null);
}

test "generated R supports quoted Zig identifiers" {
    const source: [:0]const u8 =
        \\/// @export
        \\pub fn @"r-name"(@"x-value": f64) f64 {
        \\    return @"x-value";
        \\}
        \\
    ;

    const manifest = try renderManifest(std.testing.allocator, source);
    defer std.testing.allocator.free(manifest);
    try std.testing.expect(std.mem.indexOf(u8, manifest, ".name = \"r-name\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, ".func = bound_root.@\"r-name\"") != null);

    const wrappers = try renderRWrappers(std.testing.allocator, source);
    defer std.testing.allocator.free(wrappers);
    try std.testing.expect(std.mem.indexOf(u8, wrappers, "#' Call `r-name` in Zig.") != null);
    try std.testing.expect(std.mem.indexOf(u8, wrappers, "`r-name` <- function(`x-value`)") != null);
    try std.testing.expect(std.mem.indexOf(u8, wrappers, ".Call(.rzig_symbol_1, `x-value`)") != null);
}

test "invalid Zig source is rejected" {
    try std.testing.expectError(
        error.InvalidZigSource,
        renderManifest(std.testing.allocator, "pub fn broken(\x00"),
    );
}
