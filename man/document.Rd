\name{document}
\alias{document}
\title{Generate R Bindings from Zig Exports}
\usage{
document(path = ".")
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
