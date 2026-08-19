const DllInfo = opaque {};

extern fn R_registerRoutines(
    dll: *DllInfo,
    c_methods: ?*const anyopaque,
    call_methods: ?*const anyopaque,
    fortran_methods: ?*const anyopaque,
    external_methods: ?*const anyopaque,
) callconv(.c) c_int;
extern fn R_useDynamicSymbols(dll: *DllInfo, value: c_int) callconv(.c) c_int;
extern fn R_forceSymbols(dll: *DllInfo, value: c_int) callconv(.c) c_int;

/// Hand control to the generated R routine registrar.
export fn rzig_init(dll: *DllInfo) void {
    _ = R_registerRoutines(dll, null, null, null, null);
    _ = R_useDynamicSymbols(dll, 0);
    _ = R_forceSymbols(dll, 1);
}
