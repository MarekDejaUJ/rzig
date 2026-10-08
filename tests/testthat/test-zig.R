test_that("find_zig reports a supported compiler of the 0.16 series", {
  with_fake_zig("0.16.3", {
    compiler <- find_zig()
    expect_s3_class(compiler, "rzig_compiler")
    expect_true(compiler$supported)
    expect_identical(compiler$version, "0.16.3")
    expect_identical(compiler$series, "0.16.x or 0.17.x")
    expect_output(print(compiler), "supported")
  })
})

test_that("find_zig accepts the 0.17 series", {
  with_fake_zig("0.17.0", {
    compiler <- find_zig()
    expect_true(compiler$supported)
    expect_identical(compiler$version, "0.17.0")
  })
})

test_that("find_zig rejects other release series", {
  with_fake_zig("0.18.0-dev.1234+abcdef", {
    compiler <- find_zig(required = FALSE)
    expect_false(compiler$supported)
    expect_match(compiler$problem, "0.18.0-dev.1234+abcdef", fixed = TRUE)
    expect_match(compiler$problem, "0.16.x or 0.17.x", fixed = TRUE)
    expect_error(find_zig(), "0.16.x or 0.17.x")
  })
  with_fake_zig("0.15.2", {
    expect_false(find_zig(required = FALSE)$supported)
  })
})

test_that("find_zig reports a ZIG value that is not executable", {
  old <- Sys.getenv("ZIG", unset = NA)
  Sys.setenv(ZIG = file.path(tempdir(), "no-such-zig"))
  on.exit(if (is.na(old)) Sys.unsetenv("ZIG") else Sys.setenv(ZIG = old), add = TRUE)
  compiler <- find_zig(required = FALSE)
  expect_false(compiler$supported)
  expect_match(compiler$problem, "does not name an executable")
  expect_error(find_zig(), "does not name an executable")
})

test_that("find_zig without any compiler describes what is needed", {
  old <- Sys.getenv(c("ZIG", "PATH", "HOME"), unset = NA)
  Sys.unsetenv("ZIG")
  Sys.setenv(PATH = tempdir(), HOME = tempdir())
  on.exit({
    for (name in names(old)) {
      if (is.na(old[[name]])) Sys.unsetenv(name) else do.call(Sys.setenv, as.list(old[name]))
    }
  }, add = TRUE)
  compiler <- find_zig(required = FALSE)
  expect_null(compiler$path)
  expect_match(compiler$problem, "no Zig compiler found")
  expect_output(print(compiler), "not found")
})

test_that("the version rule accepts only the supported series", {
  expect_true(rzig:::.rzig_zig_supported("0.16.0"))
  expect_true(rzig:::.rzig_zig_supported("0.16.12"))
  expect_true(rzig:::.rzig_zig_supported("0.17.0"))
  expect_true(rzig:::.rzig_zig_supported("0.17.4"))
  expect_false(rzig:::.rzig_zig_supported("0.15.2"))
  expect_false(rzig:::.rzig_zig_supported("0.18.0"))
  expect_false(rzig:::.rzig_zig_supported("1.0.0"))
  expect_false(rzig:::.rzig_zig_supported("nonsense"))
})
