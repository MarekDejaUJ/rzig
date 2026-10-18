#' Add one to each element of a numeric vector
#'
#' @param x A numeric vector.
#' @return A numeric vector of the same length as `x`.
#' @export
add_one <- function(x) {
  .Call(C_add_one, x)
}

#' Summarize a numeric vector as a named list
#'
#' @param x A numeric vector.
#' @return A list with `values` and `count` elements.
#' @export
named_summary <- function(x) {
  .Call(C_named_summary, x)
}

#' Scale a numeric vector without changing its R input
#'
#' @param x A numeric vector.
#' @param factor A numeric scalar multiplier.
#' @return A scaled duplicate of `x`.
#' @export
scale_in_place <- function(x, factor) {
  .Call(C_scale_in_place, x, factor)
}

#' Attach names and a class to a numeric vector
#'
#' @param x A numeric vector.
#' @param labels A character vector with one label per value.
#' @return A named numeric vector with class `rzig_values`.
#' @export
decorate_values <- function(x, labels) {
  .Call(C_decorate_values, x, labels)
}

#' Reshape a numeric vector
#'
#' @param x A numeric vector.
#' @param nrow A non-negative number of rows.
#' @return A numeric matrix.
#' @export
reshape_values <- function(x, nrow) {
  .Call(C_reshape_values, x, nrow)
}

#' Compute the trace of a numeric matrix
#'
#' @param x A double matrix.
#' @return The sum of the diagonal.
#' @export
matrix_trace <- function(x) {
  .Call(C_matrix_trace, x)
}

#' Count with periodic user-interrupt checks
#'
#' @param iterations A non-negative scalar iteration count.
#' @return The completed iteration count.
#' @export
interruptible_count <- function(iterations) {
  .Call(C_interruptible_count, iterations)
}

#' Square a numeric vector on pure Zig worker threads
#'
#' @param x A numeric vector.
#' @return The elementwise squares.
#' @export
sexp_describe <- function(value) {
  .Call(C_sexp_describe, value)
}

sexp_sum_entry <- function(value, name) {
  .Call(C_sexp_sum_entry, value, name)
}

sexp_attribute_length <- function(value, name) {
  .Call(C_sexp_attribute_length, value, name)
}

sexp_element_kinds <- function(value) {
  .Call(C_sexp_element_kinds, value)
}

rmath_eval <- function(kind, name, x, values, lower, log) {
  .Call(C_rmath_eval, kind, name, x, values, lower, log)
}

rmath_draws <- function(name, count, values) {
  .Call(C_rmath_draws, name, count, values)
}

counter_new <- function(step) {
  .Call(C_counter_new, step)
}

counter_add <- function(counter) {
  .Call(C_counter_add, counter)
}

counter_same <- function(counter) {
  .Call(C_counter_same, counter)
}

counters_released_count <- function() {
  .Call(C_counters_released_count)
}

counter_fail_after_create <- function() {
  .Call(C_counter_fail_after_create)
}

other_new <- function() {
  .Call(C_other_new)
}

record_options <- function(options) {
  .Call(C_record_options, options)
}

frame_group_means <- function(data) {
  .Call(C_frame_group_means, data)
}

factor_reverse_levels <- function(values) {
  .Call(C_factor_reverse_levels, values)
}

optional_length <- function(values) {
  .Call(C_optional_length, values)
}

int64_sum <- function(values) {
  .Call(C_int64_sum, values)
}

int64_double <- function(values) {
  .Call(C_int64_double, values)
}

int64_or_default <- function(value) {
  .Call(C_int64_or_default, value)
}

long_count <- function(count) {
  .Call(C_long_count, count)
}

complex_modulus <- function(values) {
  .Call(C_complex_modulus, values)
}

complex_conjugate <- function(values) {
  .Call(C_complex_conjugate, values)
}

complex_product <- function(a, b) {
  .Call(C_complex_product, a, b)
}

raw_xor <- function(bytes, key) {
  .Call(C_raw_xor, bytes, key)
}

logical_tally <- function(values) {
  .Call(C_logical_tally, values)
}

logical_not <- function(values) {
  .Call(C_logical_not, values)
}

upper_or_na <- function(values) {
  .Call(C_upper_or_na, values)
}

label_or_default <- function(label) {
  .Call(C_label_or_default, label)
}

na_real <- function() {
  .Call(C_na_real)
}

na_integer <- function() {
  .Call(C_na_integer)
}

na_logical <- function() {
  .Call(C_na_logical)
}

int_matrix_sum <- function(values) {
  .Call(C_int_matrix_sum, values)
}

bool_matrix_row_counts <- function(values) {
  .Call(C_bool_matrix_row_counts, values)
}

matrix_add_column_index <- function(values, step) {
  .Call(C_matrix_add_column_index, values, step)
}

int_matrix_negate_diagonal <- function(values) {
  .Call(C_int_matrix_negate_diagonal, values)
}

int_add_in_place <- function(values, step) {
  .Call(C_int_add_in_place, values, step)
}

named_matrix <- function(nrow, ncol, row_names, column_names) {
  .Call(C_named_matrix, nrow, ncol, row_names, column_names)
}

console_lines <- function(count) {
  invisible(.Call(C_console_lines, count))
}

console_wide <- function(width) {
  invisible(.Call(C_console_wide, width))
}

progress_steps <- function(total, show) {
  .Call(C_progress_steps, total, show)
}

parallel_thread_count <- function(count) {
  .Call(C_parallel_thread_count, count)
}

parallel_square <- function(x) {
  .Call(C_parallel_square, x)
}

#' Trigger a handled Zig bounds panic
#'
#' This fixture helper verifies that a ReleaseSafe panic becomes an R error.
#' @return This function always raises an error.
#' @export
panic_bounds <- function() {
  .Call(C_panic_bounds, c(0, 0))
}

#' Exercise cleanup during an R error
#'
#' This fixture helper allocates 10 MiB and then deliberately raises an error.
#' @return This function always raises an error.
#' @export
allocate_then_error <- function() {
  .Call(C_allocate_then_error)
}
