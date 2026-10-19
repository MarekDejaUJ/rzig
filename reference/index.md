# Package index

## Create and update a package

- [`create_rzig_package()`](https://marekdejauj.github.io/rzig/reference/create_rzig_package.md)
  : Create a package that uses RZig
- [`use_rzig()`](https://marekdejauj.github.io/rzig/reference/use_rzig.md)
  : Add RZig to a package
- [`update_rzig()`](https://marekdejauj.github.io/rzig/reference/update_rzig.md)
  : Update the rzig framework and build files of a package
- [`use_rzig_ci()`](https://marekdejauj.github.io/rzig/reference/use_rzig_ci.md)
  : Add a GitHub Actions workflow that checks the package with Zig

## Generate the bindings

Each step of the workflow is a function; document() runs them in order.

- [`scan_exports()`](https://marekdejauj.github.io/rzig/reference/scan_exports.md)
  : Scan the Zig source of a package for exported functions
- [`render_bindings()`](https://marekdejauj.github.io/rzig/reference/render_bindings.md)
  : Render the generated bindings for a set of exported functions
- [`document()`](https://marekdejauj.github.io/rzig/reference/document.md)
  : Generate R bindings from Zig exports
- [`rzig_status()`](https://marekdejauj.github.io/rzig/reference/rzig_status.md)
  : Report the state of a Zig-backed package

## Build and test

- [`find_zig()`](https://marekdejauj.github.io/rzig/reference/find_zig.md)
  : Locate a supported Zig compiler
- [`install_zig()`](https://marekdejauj.github.io/rzig/reference/install_zig.md)
  [`uninstall_zig()`](https://marekdejauj.github.io/rzig/reference/install_zig.md)
  [`zig_home()`](https://marekdejauj.github.io/rzig/reference/install_zig.md)
  : Download and install a supported Zig compiler
- [`build_zig()`](https://marekdejauj.github.io/rzig/reference/build_zig.md)
  : Compile and install a Zig-backed package, and report the first
  errors
- [`test_zig()`](https://marekdejauj.github.io/rzig/reference/test_zig.md)
  : Run the Zig tests of a package

## Zig from the R prompt

- [`zig_function()`](https://marekdejauj.github.io/rzig/reference/zig_function.md)
  [`zig_source()`](https://marekdejauj.github.io/rzig/reference/zig_function.md)
  [`zig_eval()`](https://marekdejauj.github.io/rzig/reference/zig_function.md)
  : Compile Zig code from the R prompt
- [`eng_zig()`](https://marekdejauj.github.io/rzig/reference/eng_zig.md)
  : A knitr engine for Zig chunks

## Package features

- [`use_rzig_lapack()`](https://marekdejauj.github.io/rzig/reference/use_rzig_lapack.md)
  : Link the LAPACK and BLAS libraries of R
- [`use_rzig_mixed()`](https://marekdejauj.github.io/rzig/reference/use_rzig_mixed.md)
  : Build C, C++ and Fortran sources next to the Zig code
- [`use_rzig_import()`](https://marekdejauj.github.io/rzig/reference/use_rzig_import.md)
  [`use_rzig_module()`](https://marekdejauj.github.io/rzig/reference/use_rzig_import.md)
  : Share Zig modules between R packages

## About

- [`rzig`](https://marekdejauj.github.io/rzig/reference/rzig-package.md)
  [`rzig-package`](https://marekdejauj.github.io/rzig/reference/rzig-package.md)
  : Safe Zig Bindings
