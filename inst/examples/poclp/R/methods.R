#' @export
print.poc_bounds <- function(x, digits = 4, ...) {
  bounds <- matrix(unclass(x), ncol = 2, byrow = TRUE,
    dimnames = list(c("PNS", "PN", "PS"), c("lower", "upper")))
  print(round(bounds, digits))
  invisible(x)
}
