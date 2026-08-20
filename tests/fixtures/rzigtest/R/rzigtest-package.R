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
