# Create a package that uses RZig

Creates a new package at `path`: a `DESCRIPTION`, the RZig scaffold of
[`use_rzig()`](https://marekdejauj.github.io/rzig/reference/use_rzig.md)
with its `hello_zig()` example and help page, and, by default, a
testthat suite with one test of `hello_zig()`. The package builds with
`R CMD INSTALL` once a supported Zig compiler is available (see
[`find_zig()`](https://marekdejauj.github.io/rzig/reference/find_zig.md))
and passes `R CMD check` as created.

## Usage

``` r
create_rzig_package(path, fields = list(), tests = TRUE, ci = FALSE)
```

## Arguments

- path:

  The directory to create. It must not exist or must be empty.

- fields:

  A named list of `DESCRIPTION` fields that replace or extend the
  defaults.

- tests:

  If `TRUE`, add `tests/testthat.R` and a test of `hello_zig()`, with
  testthat in `Suggests`.

- ci:

  If `TRUE`, add the GitHub Actions workflow of
  [`use_rzig_ci()`](https://marekdejauj.github.io/rzig/reference/use_rzig_ci.md).

## Value

The normalized path of the package, invisibly.

## Details

The package name is the last component of `path`. The default
`DESCRIPTION` fields are placeholders for the title, the description and
the author; `fields` replaces or adds fields, for example
`fields = list(Title = "Fast Rank Statistics", "Authors@R" = 'person("Ada", "Lovelace", email = "ada@example.org", role = c("aut", "cre"))')`.
The license is GPL-3, the license of the framework sources the package
contains (another field value is the package author's choice).

## Examples

``` r
package_path <- file.path(tempdir(), "zigstats")
create_rzig_package(package_path)
#> Created package zigstats at /tmp/Rtmpj2bSj2/zigstats
#> Write Zig functions in src/rzig/src/main.zig, then run rzig::document(path) and rzig::build_zig(path)
list.files(package_path, recursive = TRUE)
#>  [1] "DESCRIPTION"                              
#>  [2] "NAMESPACE"                                
#>  [3] "R/rzig-wrappers.R"                        
#>  [4] "cleanup"                                  
#>  [5] "cleanup.win"                              
#>  [6] "configure"                                
#>  [7] "configure.win"                            
#>  [8] "man/hello_zig.Rd"                         
#>  [9] "src/Makevars.in"                          
#> [10] "src/Makevars.win.in"                      
#> [11] "src/entry.c"                              
#> [12] "src/rzig/build.zig"                       
#> [13] "src/rzig/build.zig.zon"                   
#> [14] "src/rzig/c_libraries.zon"                 
#> [15] "src/rzig/framework/alloc.zig"             
#> [16] "src/rzig/framework/attributes.zig"        
#> [17] "src/rzig/framework/boundary.zig"          
#> [18] "src/rzig/framework/c/abi.zig"             
#> [19] "src/rzig/framework/callable.zig"          
#> [20] "src/rzig/framework/class.zig"             
#> [21] "src/rzig/framework/compat.zig"            
#> [22] "src/rzig/framework/complex.zig"           
#> [23] "src/rzig/framework/convert.zig"           
#> [24] "src/rzig/framework/error_state.zig"       
#> [25] "src/rzig/framework/external.zig"          
#> [26] "src/rzig/framework/generated/arity.zig"   
#> [27] "src/rzig/framework/generated/manifest.zig"
#> [28] "src/rzig/framework/interrupt.zig"         
#> [29] "src/rzig/framework/io.zig"                
#> [30] "src/rzig/framework/lapack.zig"            
#> [31] "src/rzig/framework/list.zig"              
#> [32] "src/rzig/framework/matrix.zig"            
#> [33] "src/rzig/framework/na.zig"                
#> [34] "src/rzig/framework/optimize.zig"          
#> [35] "src/rzig/framework/panic.zig"             
#> [36] "src/rzig/framework/parallel.zig"          
#> [37] "src/rzig/framework/progress.zig"          
#> [38] "src/rzig/framework/protect.zig"           
#> [39] "src/rzig/framework/rcall.zig"             
#> [40] "src/rzig/framework/record.zig"            
#> [41] "src/rzig/framework/register.zig"          
#> [42] "src/rzig/framework/rmath.zig"             
#> [43] "src/rzig/framework/rng.zig"               
#> [44] "src/rzig/framework/rzig.zig"              
#> [45] "src/rzig/framework/sexp.zig"              
#> [46] "src/rzig/framework/sparse.zig"            
#> [47] "src/rzig/framework/thread_identity.zig"   
#> [48] "src/rzig/framework/unwind.zig"            
#> [49] "src/rzig/src/main.zig"                    
#> [50] "src/rzig/tools/fetch_zig.R"               
#> [51] "src/rzig/tools/imports.R"                 
#> [52] "src/rzig/tools/repack_macos_archive.sh"   
#> [53] "tests/testthat.R"                         
#> [54] "tests/testthat/test-hello-zig.R"          
unlink(package_path, recursive = TRUE)
```
