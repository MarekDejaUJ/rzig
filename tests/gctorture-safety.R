# Focused GC stress for non-local error recovery.

panic_message <- tryCatch(panic_bounds(), error = conditionMessage)
stopifnot(grepl("index out of bounds", panic_message, fixed = TRUE))

for (iteration in seq_len(2)) {
  leak_message <- tryCatch(allocate_then_error(), error = conditionMessage)
  stopifnot(grepl("intentional error", leak_message, fixed = TRUE))
}

stopifnot(identical(add_one(c(21, 34)), c(22, 35)))
