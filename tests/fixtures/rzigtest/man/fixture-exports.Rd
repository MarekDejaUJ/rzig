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
\alias{sexp_describe}
\alias{sexp_sum_entry}
\alias{sexp_attribute_length}
\alias{sexp_element_kinds}
\alias{counter_new}
\alias{counter_add}
\alias{counter_same}
\alias{counters_released_count}
\alias{counter_fail_after_create}
\alias{other_new}
\alias{rmath_eval}
\alias{rmath_draws}
\alias{csc_column_sums}
\alias{csc_times_vector}
\alias{optim_rosenbrock}
\alias{optim_failing}
\alias{integrate_gaussian}
\alias{integrate_inverse}
\alias{parallel_sum}
\alias{parallel_uniforms}
\alias{parallel_out_of_bounds}
\alias{parallel_count}
\alias{call_numeric}
\alias{call_named}
\alias{call_literals}
\alias{call_with_object}
\alias{call_with_function}
\alias{call_optional}
\alias{call_with_cleanup}
\alias{call_cleanups}
\alias{call_or_default}
\alias{call_or_raise}
\alias{warn_then_call}
\alias{rng_around_call}
\alias{optim_r}
\alias{integrate_r}
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
sexp_describe(value)
sexp_sum_entry(value, name)
sexp_attribute_length(value, name)
sexp_element_kinds(value)
counter_new(step)
counter_add(counter)
counter_same(counter)
counters_released_count()
counter_fail_after_create()
other_new()
rmath_eval(kind, name, x, values, lower, log)
rmath_draws(name, count, values)
csc_column_sums(values)
csc_times_vector(values, x)
optim_rosenbrock(method, start, with_gradient, lower, upper)
optim_failing(start)
integrate_gaussian(mean, sd, lower, upper)
integrate_inverse(lower, upper)
parallel_sum(values)
parallel_uniforms(count)
parallel_out_of_bounds(values)
parallel_count(count)
call_numeric(f, x)
call_named(f, x)
call_literals(f)
call_with_object(f, object)
call_with_function(outer, inner)
call_optional(f)
call_with_cleanup(f)
call_cleanups()
call_or_default(f, fallback)
call_or_raise(f)
warn_then_call(f)
rng_around_call(f)
optim_r(f, gr, start, method)
integrate_r(f, lower, upper)
}
\arguments{
\item{count}{A non-negative count.}
\item{width}{The number of characters to print.}
\item{total}{The number of steps.}
\item{show}{Whether to draw the progress bar.}
\item{values}{A vector or matrix of the type the function reads; the parameters
of a distribution.}
\item{step}{The amount to add.}
\item{nrow, ncol}{The dimensions of the result.}
\item{row_names, column_names}{Character vectors of names; empty for none.}
\item{label}{A string, \code{NA}, or \code{NULL}.}
\item{a, b}{Complex scalars.}
\item{bytes}{A raw vector.}
\item{key}{A byte value from 0 to 255.}
\item{value}{A 64-bit integer, \code{NA}, or \code{NULL}; any R object for the
\code{sexp_} functions.}
\item{options}{A named list of fitting options.}
\item{data}{A data frame with columns \code{value} and \code{group}.}
\item{name}{The name of a list entry, an attribute or a distribution.}
\item{counter}{A counter made by \code{counter_new()}.}
\item{kind}{\code{"d"}, \code{"p"} or \code{"q"}.}
\item{x}{The value or probability.}
\item{lower, log}{The tail and the scale of probabilities; \code{lower} is also a
bound.}
\item{method}{The name of an \code{optim()} method.}
\item{start}{Starting values.}
\item{with_gradient}{Whether the objective has an analytic gradient.}
\item{upper}{Upper bounds or limits.}
\item{mean, sd}{Parameters of a normal density.}
\item{f, gr, outer, inner}{R functions.}
\item{object}{Any R object.}
\item{fallback}{The value returned when \code{f} fails.}
}
\value{
The value each function computes; the tests of the package describe them.
}
\description{
Functions that exercise the parameter and return types, console output,
progress bars and thread limits of the boundary in the package tests.
}
