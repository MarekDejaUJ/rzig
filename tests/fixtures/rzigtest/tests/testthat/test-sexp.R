test_that("rzig.Sexp reports kinds, lengths, classes and names", {
  expect_identical(sexp_describe(c(a = 1, b = 2)), "double[2] class=- names=2 s4=false")
  expect_identical(sexp_describe(NULL), "nil[0] class=- names=0 s4=false")
  expect_identical(sexp_describe(factor(c("x", "y", "x"))), "integer[3] class=factor names=0 s4=false")
  expect_identical(sexp_describe(list(1, "a")), "list[2] class=- names=0 s4=false")
  expect_identical(sexp_describe(mean), "function[1] class=- names=0 s4=false")
  # The length of an environment is its number of bindings.
  expect_identical(sexp_describe(new.env()), "environment[0] class=- names=0 s4=false")
  probe <- methods::setClass("RzigSexpProbe", representation(values = "numeric"), where = environment())
  object <- probe(values = c(1, 2, 3))
  expect_identical(sexp_describe(object), "s4[1] class=RzigSexpProbe names=0 s4=true")
  expect_identical(sexp_attribute_length(object, "values"), 3L)
  expect_identical(sexp_attribute_length(object, "missing"), -1L)
  expect_error(sexp_attribute_length(data.frame(a = 1), "row.names"), "rzig.DataFrame")
})

test_that("rzig.Sexp walks lists and converts entries with get()", {
  values <- list(x = c(1, 2, 3), y = "text", z = list())
  expect_identical(sexp_sum_entry(values, "x"), 6)
  expect_error(sexp_sum_entry(values, "w"), "no entry `w`")
  expect_error(sexp_sum_entry(values, "y"), "the R value must be a numeric vector")
  expect_identical(sexp_element_kinds(values), c("double", "character", "list"))
  expect_identical(sexp_element_kinds(1:3), c("none", "none", "none"))
})
