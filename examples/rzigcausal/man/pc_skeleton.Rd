\name{pc_skeleton}
\alias{pc_skeleton}
\title{Estimate a Gaussian PC-Stable Skeleton}
\usage{
pc_skeleton(data, alpha, max_depth)
}
\arguments{
\item{data}{A double matrix with observations in rows and variables in columns.}
\item{alpha}{A finite two-sided conditional-independence level strictly between zero and one.}
\item{max_depth}{A non-negative integer conditioning-set limit no greater than five.}
}
\value{
A symmetric zero-one adjacency matrix with a zero diagonal.
}
\description{
Runs the undirected adjacency-search portion of Gaussian PC-stable. Conditional
independence is assessed with Fisher-z tests derived from partial correlations.
The function does not orient edges.
}
\references{
Kalisch, M. and Buehlmann, P. (2007). Estimating high-dimensional directed
acyclic graphs with the PC-algorithm. \emph{Journal of Machine Learning
Research}, 8, 613--636.

Colombo, D. and Maathuis, M. H. (2014). Order-independent constraint-based
causal structure learning. \emph{Journal of Machine Learning Research}, 15,
3921--3962.
}
