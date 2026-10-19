# integer64 vectors built without bit64: the bits of each 64-bit integer
# (little-endian) read back as a double.
int64 <- function(values) {
  bytes <- unlist(lapply(values, function(value) {
    low <- writeBin(as.integer(value), raw(), size = 4L, endian = "little")
    c(low, as.raw(if (value < 0) rep(0xff, 4L) else rep(0x00, 4L)))
  }))
  structure(readBin(bytes, "double", n = length(values), size = 8L, endian = "little"), class = "integer64")
}

int64_values <- function(x) {
  bytes <- writeBin(unclass(x), raw(), size = 8L, endian = "little")
  vapply(seq_along(x), function(index) {
    word <- bytes[(index - 1L) * 8L + 1:8]
    readBin(word[1:4], "integer", size = 4L, endian = "little")
  }, integer(1L))
}

test_that("integer64 vectors are read and returned through their bits", {
  values <- int64(c(1L, -2L, 3L))
  expect_identical(int64_values(int64_sum(values)), 2L)
  doubled <- int64_double(values)
  expect_s3_class(doubled, "integer64")
  expect_identical(int64_values(doubled), c(2L, -4L, 6L))
  expect_identical(int64_values(int64_or_default(int64(7L))), 7L)
  expect_identical(int64_values(int64_or_default(12L)), 12L)
  expect_identical(int64_values(int64_or_default(NULL)), -1L)
  expect_error(int64_sum(c(1, 2)), "bit64::as.integer64()", fixed = TRUE)
  expect_error(int64_or_default(1.5), "whole number")
})

test_that("bit64 values round-trip when bit64 is installed", {
  skip_if_not_installed("bit64")
  large <- bit64::as.integer64("9007199254740993")
  expect_identical(int64_or_default(large), large)
  expect_identical(int64_sum(bit64::as.integer64(c("4611686018427387904", "4611686018427387903"))),
    bit64::as.integer64("9223372036854775807"))
  expect_error(int64_sum(bit64::as.integer64(c("9223372036854775807", "1"))), "integer64 overflow")
  expect_identical(int64_or_default(bit64::NA_integer64_), bit64::as.integer64(-1L))
  expect_identical(int64_sum(bit64::as.integer64(c(NA, 5))), bit64::as.integer64(5L))
})

test_that("i64 carries counts beyond 2^31 - 1", {
  expect_identical(long_count(2^31), 2^31)
  expect_identical(long_count(2^53 - 1), 2^53 - 1)
  expect_error(long_count(2^53), "9007199254740991")
})
