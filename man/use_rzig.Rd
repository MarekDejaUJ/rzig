\name{use_rzig}
\alias{use_rzig}
\title{Add RZig to an R Package}
\usage{
use_rzig(path = ".", overwrite = FALSE)
}
\arguments{
\item{path}{Path to the package root.}
\item{overwrite}{Replace files previously managed by RZig.}
}
\value{
The normalized package path, invisibly.
}
\description{
Creates a Zig source tree, portable build files, a generated native entry
stub, and a working \code{hello_zig()} example in an existing R package.
}
\examples{
package <- tempfile("rzig-example-")
dir.create(package)
writeLines(
    c("Package: examplepkg", "Version: 0.0.1"),
    file.path(package, "DESCRIPTION")
)
use_rzig(package)
file.exists(file.path(package, "src", "rzig", "src", "main.zig"))
unlink(package, recursive = TRUE)
}
