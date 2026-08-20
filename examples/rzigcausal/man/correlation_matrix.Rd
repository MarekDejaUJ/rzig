\name{correlation_matrix}
\alias{correlation_matrix}
\title{Compute a Pearson Correlation Matrix in Zig}
\usage{
correlation_matrix(data)
}
\arguments{
\item{data}{A double matrix with observations in rows and variables in columns.}
}
\value{
A symmetric variable-by-variable double matrix.
}
\description{
Standardizes each column and computes pairwise Pearson correlations using pure
Zig worker threads. R API access remains on the calling thread.
}
