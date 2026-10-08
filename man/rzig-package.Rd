\name{rzig-package}
\alias{rzig}
\alias{rzig-package}
\docType{package}
\title{Safe Zig Bindings}
\description{
RZig scaffolds packages backed by Zig and generates safe native bindings for
plain Zig functions. Each step of the workflow is a function:
\code{\link{find_zig}} locates a supported Zig compiler,
\code{\link{use_rzig}} adds the build files and the framework sources to a
package, \code{\link{scan_exports}} lists the exported Zig functions with
their R arguments, \code{\link{render_bindings}} shows the generated manifest,
R wrappers and \code{NAMESPACE} block, \code{\link{document}} writes them,
and \code{\link{rzig_status}} reports which steps are complete. The scan and
the generated bindings are pure R; a Zig compiler of the 0.16 or 0.17
release series is needed only to install a package created with the scaffold.
}
\author{
Marek Deja
}
