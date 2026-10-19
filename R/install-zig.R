#' Download and install a supported Zig compiler
#'
#' Downloads the Zig release `version` for this platform, verifies the
#' archive against the size and SHA-256 that
#' <https://ziglang.org/download/index.json> publishes (pinned in rzig), and
#' unpacks it into `dir`. [find_zig()] and the `configure` scripts of
#' packages created with [use_rzig()] find compilers installed in
#' `zig_home()`, so `R CMD INSTALL` of such a package needs no further setup.
#'
#' The archive (about 55 MB, about 300 MB unpacked) comes from one of the
#' community mirrors of Zig, tried in an order that varies between sessions,
#' or else from ziglang.org, as the Zig Software Foundation asks of automated
#' downloads. A download whose size or SHA-256 differs from the pin is
#' deleted before anything is extracted or run. An existing installation of
#' the same version is reused. `uninstall_zig()` removes installations made by
#' `install_zig()`.
#'
#' `zig_home()` is the folder named by the environment variable
#' `RZIG_ZIG_HOME`, or `zig` in the user cache folder of rzig
#' ([tools::R_user_dir()]).
#'
#' @param version The Zig release: `"0.16.0"` or `"0.17.0"`.
#' @param dir The folder that holds the installations.
#' @param mirrors If `FALSE`, download from ziglang.org only.
#' @param quiet If `TRUE`, show no download progress.
#'
#' @return `install_zig()`: the path of the zig executable, invisibly.
#'   `uninstall_zig()`: the folders removed, invisibly. `zig_home()`: a path.
#' @examples
#' zig_home()
#' \dontrun{
#' install_zig("0.16.0")
#' find_zig()
#' }
#' @export
install_zig <- function(version = "0.16.0", dir = zig_home(), mirrors = TRUE, quiet = FALSE) {
  if (length(version) != 1L || !is.character(version) || is.na(version)) {
    stop("`version` must be one Zig release, for example \"0.16.0\"", call. = FALSE)
  }
  if (length(dir) != 1L || !is.character(dir) || is.na(dir) || !nzchar(dir)) {
    stop("`dir` must be one folder", call. = FALSE)
  }
  fetch <- .rzig_fetch()
  path <- fetch$rzig_fetch_install(version, dir, mirrors = isTRUE(mirrors), quiet = isTRUE(quiet))
  message(sprintf("Zig %s is installed at %s", version, path))
  invisible(path)
}

#' @rdname install_zig
#' @export
uninstall_zig <- function(version = NULL, dir = zig_home()) {
  receipt <- .rzig_fetch()$rzig_fetch_receipt
  folders <- if (dir.exists(dir)) list.dirs(dir, recursive = FALSE, full.names = TRUE) else character()
  ours <- folders[file.exists(file.path(folders, receipt))]
  if (!is.null(version)) ours <- ours[endsWith(basename(ours), paste0("-", version))]
  unlink(ours, recursive = TRUE, force = TRUE)
  if (length(ours)) message("Removed ", paste(basename(ours), collapse = ", "))
  invisible(ours)
}

#' @rdname install_zig
#' @export
zig_home <- function() {
  explicit <- Sys.getenv("RZIG_ZIG_HOME", unset = "")
  folder <- if (nzchar(explicit)) explicit else file.path(tools::R_user_dir("rzig", which = "cache"), "zig")
  normalizePath(folder, winslash = "/", mustWork = FALSE)
}

# The functions of inst/zig/tools/fetch_zig.R, the downloader that the
# configure scripts of packages created with use_rzig() run as well.
.rzig_fetch <- local({
  cached <- NULL
  function() {
    if (is.null(cached)) {
      script <- system.file("zig", "tools", "fetch_zig.R", package = "rzig")
      if (!nzchar(script)) stop("the installed rzig package is missing tools/fetch_zig.R", call. = FALSE)
      environment <- new.env(parent = baseenv())
      sys.source(script, envir = environment, keep.source = FALSE)
      cached <<- environment
    }
    cached
  }
})
