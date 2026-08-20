\name{parallel_square}
\alias{parallel_square}
\title{Square a Numeric Vector on Pure Zig Worker Threads}
\usage{
parallel_square(x)
}
\arguments{
\item{x}{A numeric vector.}
}
\value{
The elementwise squares.
}
\description{
Squares a numeric vector using worker threads that receive only pure Zig data.
}
