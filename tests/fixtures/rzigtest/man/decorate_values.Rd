\name{decorate_values}
\alias{decorate_values}
\title{Attach Names and a Class to a Numeric Vector}
\usage{
decorate_values(x, labels)
}
\arguments{
\item{x}{A numeric vector.}
\item{labels}{A character vector with one label per value.}
}
\value{
A named numeric vector with class \code{rzig_values}.
}
\description{
Returns a numeric vector with copied \code{names} and \code{class} attributes.
}
