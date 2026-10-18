test_that("external values keep state between calls", {
  counter <- counter_new(2L)
  expect_identical(class(counter), c("Counter", "rzig_external"))
  expect_identical(typeof(counter), "externalptr")
  expect_identical(counter_add(counter), 2L)
  expect_identical(counter_add(counter), 4L)
  expect_identical(counter_same(counter), counter)
  expect_identical(counter_add(counter), 6L)
})

test_that("garbage collection and failed calls release external values", {
  # Collect counters of earlier tests first.
  invisible(gc())
  before <- counters_released_count()
  local({
    counter <- counter_new(1L)
    counter_add(counter)
  })
  invisible(gc())
  invisible(gc())
  expect_identical(counters_released_count(), before + 1L)
  before <- counters_released_count()
  expect_error(counter_fail_after_create(), "failed after creating a counter")
  expect_identical(counters_released_count(), before + 1L)
})

test_that("external values of other types, other objects and restored values are rejected", {
  expect_error(counter_add(other_new()), "must be a Counter made by this package")
  expect_error(counter_add(1), "must be a Counter made by this package; got double")
  expect_error(counter_add(NULL), "must be a Counter")
  restored <- unserialize(serialize(counter_new(1L), NULL))
  expect_error(counter_add(restored), "lost when R saved and restored it")
})
