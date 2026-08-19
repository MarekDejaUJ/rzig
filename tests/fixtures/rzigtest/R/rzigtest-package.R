#' Add one to each element of a numeric vector
#'
#' @param x A numeric vector.
#' @return A numeric vector of the same length as `x`.
#' @export
add_one <- function(x) {
  .Call(C_add_one, x)
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
