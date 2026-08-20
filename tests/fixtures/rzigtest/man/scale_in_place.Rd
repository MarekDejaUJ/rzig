\name{scale_in_place}
\alias{scale_in_place}
\title{Scale a Numeric Vector Without Changing Its R Input}
\usage{
scale_in_place(x, factor)
}
\arguments{
\item{x}{A numeric vector.}
\item{factor}{A numeric scalar multiplier.}
}
\value{
A scaled duplicate of \code{x}.
}
\description{
Duplicates a numeric vector before exposing writable storage to Zig.
}
