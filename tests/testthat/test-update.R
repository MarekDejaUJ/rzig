template_fixture <- function(name) fixture_path("templates", name)

test_that("update_rzig refreshes the framework and keeps the author's files", {
  path <- local_package("updatepkg")
  suppressMessages(use_rzig(path))
  zig_dir <- file.path(path, "src", "rzig")
  cat("// stale\n", file = file.path(zig_dir, "framework", "na.zig"), append = TRUE)
  main <- file.path(zig_dir, "src", "main.zig")
  cat("// written by the package author\n", file = main, append = TRUE)
  writeLines("pub const two = 2;", file.path(zig_dir, "src", "helpers.zig"))
  writeLines("notes", file.path(zig_dir, "NOTES.txt"))
  writeLines("// mine", file.path(zig_dir, "framework", "extra.zig"))
  cat("# package-specific setting\n", file = file.path(path, "src", "Makevars.in"), append = TRUE)
  file.copy(template_fixture("configure-0.3.0"), file.path(path, "configure"), overwrite = TRUE)
  dir.create(file.path(zig_dir, "tools"), showWarnings = FALSE)
  file.copy(template_fixture("scan-0.2.zig"), file.path(zig_dir, "tools", "scan.zig"))
  unlink(file.path(path, "cleanup.win"))

  result <- suppressMessages(update_rzig(path))
  expect_s3_class(result, "rzig_update")
  action <- function(file) result$actions$action[result$actions$file == file]
  expect_identical(action("src/rzig/framework/na.zig"), "refreshed")
  expect_identical(action("configure"), "updated")
  expect_identical(action("cleanup.win"), "added")
  expect_identical(action("src/Makevars.in"), "kept")
  expect_identical(action("src/rzig/tools/scan.zig"), "removed")
  expect_identical(action("src/entry.c"), "current")
  expect_identical(result$unknown, "src/rzig/framework/extra.zig")

  expect_identical(utils::tail(readLines(main), 1L), "// written by the package author")
  expect_true(file.exists(file.path(zig_dir, "src", "helpers.zig")))
  expect_true(file.exists(file.path(zig_dir, "NOTES.txt")))
  expect_true(file.exists(file.path(zig_dir, "framework", "extra.zig")))
  expect_identical(utils::tail(readLines(file.path(path, "src", "Makevars.in")), 1L), "# package-specific setting")
  expect_false(file.exists(file.path(zig_dir, "tools", "scan.zig")))
  expect_true(rzig:::.rzig_same_text(file.path(path, "configure"),
    system.file("templates", "configure", package = "rzig")))
  expect_length(rzig:::.rzig_check_scaffold(path, "updatepkg")$problems, 0L)
  expect_output(print(result), "customized build files kept")

  forced <- suppressMessages(update_rzig(path, force = TRUE))
  expect_identical(forced$actions$action[forced$actions$file == "src/Makevars.in"], "replaced")
  expect_true(rzig:::.rzig_same_text(file.path(path, "src", "Makevars.in"),
    system.file("templates", "Makevars", package = "rzig")))
  again <- suppressMessages(update_rzig(path))
  expect_true(all(again$actions$action == "current"))
  expect_output(print(again), "everything matches")
})

test_that("an unmodified template of an older rzig is updated", {
  path <- local_package("oldtemplatepkg")
  suppressMessages(use_rzig(path))
  file.copy(template_fixture("Makevars-0.3.0"), file.path(path, "src", "Makevars.in"), overwrite = TRUE)
  result <- suppressMessages(update_rzig(path))
  expect_identical(result$actions$action[result$actions$file == "src/Makevars.in"], "updated")
  expect_true(any(grepl("$(STATLIB): FORCE", readLines(file.path(path, "src", "Makevars.in")), fixed = TRUE)))
})

test_that("use_rzig(overwrite = TRUE) stops on customized build files unless forced", {
  path <- local_package("overwritepkg")
  suppressMessages(use_rzig(path))
  makevars <- file.path(path, "src", "Makevars.in")
  cat("# package-specific setting\n", file = makevars, append = TRUE)
  writeLines("notes", file.path(path, "src", "rzig", "NOTES.txt"))
  cat("// stale\n", file = file.path(path, "src", "rzig", "framework", "na.zig"), append = TRUE)
  expect_error(use_rzig(path, overwrite = TRUE), "update_rzig(path) keeps them", fixed = TRUE)
  expect_identical(utils::tail(readLines(makevars), 1L), "# package-specific setting")
  expect_identical(utils::tail(readLines(file.path(path, "src", "rzig", "framework", "na.zig")), 1L), "// stale")
  suppressMessages(use_rzig(path, overwrite = TRUE, force = TRUE))
  expect_true(rzig:::.rzig_same_text(makevars, system.file("templates", "Makevars", package = "rzig")))
  expect_true(file.exists(file.path(path, "src", "rzig", "NOTES.txt")))
  expect_error(use_rzig(path), "update_rzig(path)", fixed = TRUE)
})

test_that("update_rzig needs an existing scaffold", {
  path <- local_package("noscaffoldpkg")
  expect_error(update_rzig(path), "use_rzig")
})

test_that("the hash list knows the installed templates", {
  table <- rzig:::.rzig_build_file_table()
  for (index in seq_len(nrow(table))) {
    text <- rzig:::.rzig_read_text(table$template[[index]])
    expect_true(
      rzig:::.rzig_text_md5(text) %in% rzig:::.rzig_known_template_hashes[[table$key[[index]]]],
      info = table$file[[index]]
    )
  }
})
