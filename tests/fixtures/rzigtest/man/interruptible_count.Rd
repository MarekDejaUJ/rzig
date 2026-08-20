\name{interruptible_count}
\alias{interruptible_count}
\title{Count with Periodic User-Interrupt Checks}
\usage{
interruptible_count(iterations)
}
\arguments{
\item{iterations}{A non-negative scalar iteration count.}
}
\value{
The completed iteration count.
}
\description{
Runs a Zig loop that checks safely for a pending R user interrupt every 100,000
iterations.
}
