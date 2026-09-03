\name{document}
\alias{document}
\title{Generate R Bindings from Zig Exports}
\usage{
document(path)
}
\arguments{
\item{path}{Path to a package previously initialized with \code{use_rzig()}.}
}
\value{
The normalized package path, invisibly.
}
\description{
Scans public Zig functions marked with \code{/// @export}, regenerates the Zig
manifest and R wrappers, and updates a managed block in \file{NAMESPACE}.
}
\examples{
\donttest{
local({
  package_path <- tempfile("rzig-document-", tmpdir = tempdir())
  dir.create(package_path)
  on.exit(unlink(package_path, recursive = TRUE), add = TRUE)
  writeLines(
    c("Package: examplepkg", "Version: 0.0.1"),
    file.path(package_path, "DESCRIPTION")
  )
  use_rzig(package_path)
  document(package_path)
  file.exists(file.path(package_path, "R", "rzig-wrappers.R"))
})
}
}
