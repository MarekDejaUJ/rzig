# Safe Zig Bindings

RZig scaffolds packages backed by Zig and generates safe native bindings
for plain Zig functions. Each step of the workflow is a function:
[`find_zig`](https://marekdejauj.github.io/rzig/reference/find_zig.md)
locates a supported Zig compiler,
[`use_rzig`](https://marekdejauj.github.io/rzig/reference/use_rzig.md)
adds the build files and the framework sources to a package,
[`scan_exports`](https://marekdejauj.github.io/rzig/reference/scan_exports.md)
lists the exported Zig functions with their R arguments,
[`render_bindings`](https://marekdejauj.github.io/rzig/reference/render_bindings.md)
shows the generated manifest, R wrappers and `NAMESPACE` block,
[`document`](https://marekdejauj.github.io/rzig/reference/document.md)
writes them,
[`rzig_status`](https://marekdejauj.github.io/rzig/reference/rzig_status.md)
reports which steps are complete and which signatures the boundary
rejects, and
[`build_zig`](https://marekdejauj.github.io/rzig/reference/build_zig.md)
compiles and installs the package, reporting compiler errors by file and
line. The scan and the generated bindings are pure R; a Zig compiler of
the 0.16 or 0.17 release series is needed only to install a package
created with the scaffold.

## Author

Marek Deja
