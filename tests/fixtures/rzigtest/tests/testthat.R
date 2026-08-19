library(testthat)
library(rzigtest)

if (identical(Sys.getenv("RZIG_WINDOWS_SMOKE_ONLY"), "true")) {
  test_dir("testthat", filter = "ucrt-smoke")
} else {
  test_check("rzigtest")
}
