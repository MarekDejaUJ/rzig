gc_stress <- identical(Sys.getenv("RZIG_GC_STRESS"), "true")
if (gc_stress) gctorture(FALSE)

library(testthat)
library(rzigtest)

large_n <- if (gc_stress) 10000L else 1000000L

call_native <- function(name, ...) {
  symbol <- get(paste0("C_", name), envir = asNamespace("rzigtest"))
  if (gc_stress) {
    gctorture(TRUE)
    on.exit(gctorture(FALSE), add = TRUE)
  }
  .Call(symbol, ...)
}

echo_f64 <- function(x) call_native("echo_f64", x)
echo_i32 <- function(x) call_native("echo_i32", x)
echo_bool <- function(x) call_native("echo_bool", x)
echo_usize <- function(x) call_native("echo_usize", x)
echo_optional <- function(x) call_native("echo_optional", x)
echo_reals <- function(x) call_native("echo_reals", x)
integer_length <- function(x) call_native("integer_length", x)
logical_count <- function(x) call_native("logical_count", x)
echo_string <- function(x) call_native("echo_string", x)
string_count <- function(x) call_native("string_count", x)
identity_sexp <- function(x) call_native("identity_sexp", x)
add_vectors <- function(a, b) call_native("add_vectors", a, b)
named_summary <- function(x) call_native("named_summary", x)
scale_in_place <- function(x, factor) call_native("scale_in_place", x, factor)
decorate_values <- function(x, labels) call_native("decorate_values", x, labels)
reshape_values <- function(x, nrow) call_native("reshape_values", x, nrow)
matrix_trace <- function(x) call_native("matrix_trace", x)

expect_error_live <- function(call, patterns = character()) {
  condition <- tryCatch(call(), error = identity)
  expect_s3_class(condition, "error")
  message <- conditionMessage(condition)
  for (pattern in patterns) expect_match(message, pattern, fixed = TRUE)
  expect_identical(echo_i32(7L), 7L)
  invisible(message)
}

test_that("supported scalar conversions preserve values and missingness", {
  expect_identical(echo_f64(1.25), 1.25)
  expect_identical(echo_f64(2L), 2)
  expect_identical(echo_f64(TRUE), 1)
  expect_true(is.nan(echo_f64(NaN)))
  expect_identical(echo_f64(Inf), Inf)

  expect_identical(echo_i32(-7L), -7L)
  expect_identical(echo_i32(42), 42L)
  expect_identical(echo_i32(TRUE), 1L)
  expect_identical(echo_bool(TRUE), TRUE)
  expect_identical(echo_bool(FALSE), FALSE)
  expect_identical(echo_usize(17L), 17L)
  expect_identical(echo_usize(17), 17L)

  expect_null(echo_optional(NULL))
  expect_null(echo_optional(NA_real_))
  expect_null(echo_optional(NA_integer_))
  expect_null(echo_optional(NA))
  expect_identical(echo_optional(3.5), 3.5)
})

test_that("borrowed vectors cover empty, missing, large, and ALTREP inputs", {
  expect_identical(echo_reals(numeric()), numeric())
  expect_identical(echo_reals(c(1, NA_real_, NaN, Inf)), c(1, NA_real_, NaN, Inf))
  expect_identical(integer_length(integer()), 0L)
  expect_identical(integer_length(c(1L, NA_integer_)), 2L)
  expect_identical(integer_length(factor(c("a", "b"))), 2L)
  expect_identical(logical_count(logical()), 0L)
  expect_identical(logical_count(c(TRUE, FALSE, TRUE)), 2L)

  large_real <- as.numeric(seq_len(large_n))
  large_real_result <- echo_reals(large_real)
  expect_identical(length(large_real_result), large_n)
  expect_identical(large_real_result[c(1L, large_n)], c(1, as.double(large_n)))
  expect_identical(integer_length(seq_len(large_n)), large_n)
  expect_identical(logical_count(rep_len(c(TRUE, FALSE), large_n)), large_n %/% 2L)
})

test_that("strings are normalized to UTF-8 and copied safely", {
  astral <- "\U0001F600"
  latin1 <- iconv("caf\u00e9", from = "UTF-8", to = "latin1")
  expect_identical(echo_string("alpha"), "alpha")
  expect_identical(echo_string(astral), astral)
  expect_identical(enc2utf8(echo_string(latin1)), enc2utf8(latin1))
  expect_identical(string_count(character()), 0L)
  expect_identical(string_count(c("alpha", astral, latin1)), 3L)
})

test_that("the explicit Sexp escape hatch round-trips arbitrary R values", {
  values <- list(
    NULL,
    list(alpha = 1, beta = "two"),
    factor(c("a", "b")),
    matrix(1:4, 2),
    new.env(parent = emptyenv())
  )
  for (value in values) expect_identical(identity_sexp(value), value)
})

test_that("real-vector results and user errors cross the complete boundary", {
  expect_identical(add_vectors(c(1, 2, 3), c(10, 20, 30)), c(11, 22, 33))
  expect_identical(add_vectors(numeric(), numeric()), numeric())
  expect_true(is.na(add_vectors(NA_real_, 1)))
  left <- as.numeric(seq_len(large_n))
  result <- add_vectors(left, rep(1, length(left)))
  expect_identical(result[c(1L, large_n)], c(2, as.double(large_n + 1L)))
  expect_error_live(
    function() add_vectors(c(1, 2), c(1, 2, 3)),
    c("lengths differ", "2", "3")
  )
})

test_that("named list results survive allocation and GC stress", {
  expect_identical(
    named_summary(c(1.5, 2.5)),
    list(values = c(1.5, 2.5), count = 2L)
  )
  expect_identical(named_summary(numeric()), list(values = numeric(), count = 0L))
})

test_that("mutable inputs are duplicated before Zig writes", {
  original <- c(1, 2, 3)
  alias <- original
  expect_identical(scale_in_place(alias, 3), c(3, 6, 9))
  expect_identical(alias, c(1, 2, 3))
  expect_identical(original, c(1, 2, 3))
  expect_identical(scale_in_place(numeric(), 3), numeric())
  expect_error_live(
    function() scale_in_place(1:3, 3),
    c("rzig.Mut([]f64)", "use as.numeric() in R")
  )
})

test_that("attributes and matrix views preserve R metadata", {
  decorated <- decorate_values(c(1.5, 2.5), c("left", "right"))
  expect_identical(as.numeric(decorated), c(1.5, 2.5))
  expect_identical(names(decorated), c("left", "right"))
  expect_identical(class(decorated), "rzig_values")
  expect_identical(reshape_values(as.numeric(1:6), 2L), matrix(as.numeric(1:6), 2L))
  expect_identical(matrix_trace(matrix(c(1, 2, 3, 4), 2L)), 5)
  expect_error_live(function() matrix_trace(c(1, 2)), c("without dimensions"))
  expect_error_live(function() matrix_trace(matrix(1:4, 2L)), c("storage.mode"))
})

test_that("malformed inputs always become R errors and the session stays alive", {
  cases <- list(
    list(function() echo_f64("a"), c("argument 1", "echo_f64")),
    list(function() echo_f64(NULL), c("argument 1", "echo_f64")),
    list(function() echo_f64(numeric()), c("length 0")),
    list(function() echo_f64(c(1, 2)), c("length 2")),
    list(function() echo_f64(NA_real_), c("cannot be NA")),

    list(function() echo_i32("a"), c("argument 1", "echo_i32")),
    list(function() echo_i32(NULL), c("argument 1", "echo_i32")),
    list(function() echo_i32(integer()), c("length 0")),
    list(function() echo_i32(c(1L, 2L)), c("length 2")),
    list(function() echo_i32(NA_integer_), c("cannot be NA")),
    list(function() echo_i32(1.5), c("whole number")),
    list(function() echo_i32(Inf), c("representable as i32")),
    list(function() echo_i32(2147483648), c("representable as i32")),

    list(function() echo_bool(1), c("logical vector")),
    list(function() echo_bool(1L), c("logical vector")),
    list(function() echo_bool(NULL), c("logical vector")),
    list(function() echo_bool(logical()), c("length 0")),
    list(function() echo_bool(c(TRUE, FALSE)), c("length 2")),
    list(function() echo_bool(NA), c("cannot be NA")),

    list(function() echo_usize("a"), c("argument 1", "echo_usize")),
    list(function() echo_usize(NULL), c("argument 1", "echo_usize")),
    list(function() echo_usize(integer()), c("length 0")),
    list(function() echo_usize(c(1L, 2L)), c("length 2")),
    list(function() echo_usize(NA_integer_), c("cannot be NA")),
    list(function() echo_usize(-1L), c("non-negative")),
    list(function() echo_usize(1.5), c("whole number")),
    list(function() echo_usize(2147483648), c("0 to 2147483647")),

    list(function() echo_optional("a"), c("argument 1", "echo_optional")),
    list(function() echo_optional(numeric()), c("length 0")),
    list(function() echo_optional(c(1, 2)), c("length 2")),

    list(function() echo_reals(1:3), c("use as.numeric()")),
    list(function() echo_reals(TRUE), c("numeric vector")),
    list(function() echo_reals("a"), c("numeric vector")),
    list(function() echo_reals(list(1)), c("numeric vector")),
    list(function() echo_reals(NULL), c("numeric vector")),

    list(function() integer_length(c(1, 2)), c("use as.integer()")),
    list(function() integer_length(TRUE), c("integer vector")),
    list(function() integer_length("a"), c("integer vector")),
    list(function() integer_length(list(1)), c("integer vector")),
    list(function() integer_length(NULL), c("integer vector")),

    list(function() logical_count(c(1, 0)), c("logical vector")),
    list(function() logical_count(c(1L, 0L)), c("logical vector")),
    list(function() logical_count("a"), c("logical vector")),
    list(function() logical_count(list(TRUE)), c("logical vector")),
    list(function() logical_count(NULL), c("logical vector")),
    list(function() logical_count(c(TRUE, NA)), c("position 2")),

    list(function() echo_string(character()), c("length 0")),
    list(function() echo_string(c("a", "b")), c("length 2")),
    list(function() echo_string(NA_character_), c("cannot be NA")),
    list(function() echo_string(1), c("character vector")),
    list(function() echo_string(NULL), c("character vector")),
    list(function() echo_string(list("a")), c("character vector")),

    list(function() string_count(1), c("character vector")),
    list(function() string_count(list("a")), c("character vector")),
    list(function() string_count(NULL), c("character vector")),
    list(function() string_count(c("ok", NA_character_)), c("position 2")),

    list(function() add_vectors(1:3, c(1, 2, 3)), c("use as.numeric()")),
    list(function() add_vectors("a", c(1, 2, 3)), c("numeric vector")),
    list(function() add_vectors(c(1, 2), c(1, 2, 3)), c("lengths differ"))
  )

  calls <- 0L
  for (round in seq_len(2)) {
    for (case in cases) {
      expect_error_live(case[[1L]], case[[2L]])
      calls <- calls + 1L
    }
  }
  expect_gte(calls, 100L)
})

test_that("byte-encoded strings fail safely if R cannot translate them", {
  bytes <- rawToChar(as.raw(255L))
  Encoding(bytes) <- "bytes"
  condition <- tryCatch(echo_string(bytes), error = identity)
  expect_s3_class(condition, "error")
  expect_identical(echo_i32(11L), 11L)
})
