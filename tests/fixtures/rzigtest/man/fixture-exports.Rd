\name{fixture-exports}
\alias{fixture-exports}
\alias{parallel_thread_count}
\alias{console_lines}
\alias{console_wide}
\alias{progress_steps}
\alias{int_matrix_sum}
\alias{bool_matrix_row_counts}
\alias{matrix_add_column_index}
\alias{int_matrix_negate_diagonal}
\alias{int_add_in_place}
\alias{named_matrix}
\alias{logical_tally}
\alias{logical_not}
\alias{upper_or_na}
\alias{label_or_default}
\alias{na_real}
\alias{na_integer}
\alias{na_logical}
\alias{complex_modulus}
\alias{complex_conjugate}
\alias{complex_product}
\alias{raw_xor}
\alias{int64_sum}
\alias{int64_double}
\alias{int64_or_default}
\alias{long_count}
\alias{record_options}
\alias{frame_group_means}
\alias{factor_reverse_levels}
\alias{optional_length}
\title{Fixture Functions for the Types and Services of the Boundary}
\usage{
parallel_thread_count(count)
console_lines(count)
console_wide(width)
progress_steps(total, show)
int_matrix_sum(values)
bool_matrix_row_counts(values)
matrix_add_column_index(values, step)
int_matrix_negate_diagonal(values)
int_add_in_place(values, step)
named_matrix(nrow, ncol, row_names, column_names)
logical_tally(values)
logical_not(values)
upper_or_na(values)
label_or_default(label)
na_real()
na_integer()
na_logical()
complex_modulus(values)
complex_conjugate(values)
complex_product(a, b)
raw_xor(bytes, key)
int64_sum(values)
int64_double(values)
int64_or_default(value)
long_count(count)
record_options(options)
frame_group_means(data)
factor_reverse_levels(values)
optional_length(values)
}
\arguments{
\item{count}{A non-negative count.}
\item{width}{The number of characters to print.}
\item{total}{The number of steps.}
\item{show}{Whether to draw the progress bar.}
\item{values}{A vector or matrix of the type the function reads.}
\item{step}{The amount to add.}
\item{nrow, ncol}{The dimensions of the result.}
\item{row_names, column_names}{Character vectors of names; empty for none.}
\item{label}{A string, \code{NA}, or \code{NULL}.}
\item{a, b}{Complex scalars.}
\item{bytes}{A raw vector.}
\item{key}{A byte value from 0 to 255.}
\item{value}{A 64-bit integer, \code{NA}, or \code{NULL}.}
\item{options}{A named list of fitting options.}
\item{data}{A data frame with columns \code{value} and \code{group}.}
}
\value{
The value each function computes; the tests of the package describe them.
}
\description{
Functions that exercise the parameter and return types, console output,
progress bars and thread limits of the boundary in the package tests.
}
