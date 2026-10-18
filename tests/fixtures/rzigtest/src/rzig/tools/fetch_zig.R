# Download, verify and unpack a release of Zig. Used by rzig::install_zig()
# and by the configure scripts of packages built with rzig when
# RZIG_DOWNLOAD_ZIG=true. Base R only.
#
# Each archive is pinned to the size and SHA-256 that
# https://ziglang.org/download/index.json publishes; a download that differs
# is deleted before anything is extracted or run. Community mirrors
# (https://ziglang.org/download/community-mirrors.txt) are tried first, in an
# order that varies between processes, then ziglang.org, as the Zig Software
# Foundation asks of automated downloads.
#
# Command line: Rscript fetch_zig.R <version> <directory>
# prints the path of the verified zig executable.

rzig_fetch_pins <- list(
  "0.16.0" = list(
    "aarch64-macos" = c("b23d70deaa879b5c2d486ed3316f7eaa53e84acf6fc9cc747de152450d401489", "52238004"),
    "x86_64-macos" = c("0387557ed1877bc6a2e1802c8391953baddba76081876301c522f52977b52ba7", "57396836"),
    "aarch64-linux" = c("ea4b09bfb22ec6f6c6ceac57ab63efb6b46e17ab08d21f69f3a48b38e1534f17", "51211944"),
    "x86_64-linux" = c("70e49664a74374b48b51e6f3fdfbf437f6395d42509050588bd49abe52ba3d00", "55478392"),
    "aarch64-windows" = c("aee38316ee4111717900f45dd3130145c39289e105541d737eb8c5ed653c78ef", "93109828"),
    "x86_64-windows" = c("68659eb5f1e4eb1437a722f1dd889c5a322c9954607f5edcf337bc3684a75a7e", "97217739")
  ),
  "0.17.0" = list(
    "aarch64-macos" = c("b607e9b9234790a008116ae5bdb71c6243b84b9fb42a53a9e70fde41c06c536a", "53985220"),
    "x86_64-macos" = c("4f9a1c5269aa17ebda5e6d3c2b89d6cbf36f7d2b22a0306e9ab98f25f95529c6", "59317572"),
    "aarch64-linux" = c("9e8d11661d4ae3bd57702a3832781e23ad151dde5798e16a5ccd503f65234ff8", "52877280"),
    "x86_64-linux" = c("1cbe9df9f27e6b78d14ccbca43b6703a404ef79ef1c463de901d7f088d4e2026", "57332648"),
    "aarch64-windows" = c("0a59d91fa1cb40cf068e9b0954434ce973500c7a2ea749f1e01af62cdab52d26", "95992853"),
    "x86_64-windows" = c("b5663f69581dcf391293fbf16c06cb80d81d806545ce618b4d0bab7f0eb8c428", "100268137")
  )
)

# The platform key of Zig's download index for this R, such as "aarch64-macos".
rzig_fetch_platform <- function(sysname = Sys.info()[["sysname"]], machine = R.version$arch) {
  os <- switch(tolower(sysname), darwin = "macos", linux = "linux", windows = "windows",
    stop("rzig downloads Zig for macOS, Linux and Windows only; this is ", sysname, call. = FALSE))
  arch <- switch(tolower(machine), arm64 = , aarch64 = "aarch64", x86_64 = , amd64 = , x64 = "x86_64",
    stop("rzig downloads Zig for aarch64 and x86_64 only; this R is ", machine, call. = FALSE))
  paste(arch, os, sep = "-")
}

rzig_fetch_spec <- function(version, platform = rzig_fetch_platform()) {
  pins <- rzig_fetch_pins[[version]]
  if (is.null(pins)) {
    stop(sprintf("rzig can download Zig %s; Zig %s is not one of them",
      paste(names(rzig_fetch_pins), collapse = " and "), version), call. = FALSE)
  }
  pin <- pins[[platform]]
  if (is.null(pin)) stop("no pinned Zig ", version, " archive for ", platform, call. = FALSE)
  windows <- endsWith(platform, "-windows")
  top <- paste0("zig-", platform, "-", version)
  list(
    version = version, platform = platform, top = top,
    file = paste0(top, if (windows) ".zip" else ".tar.xz"),
    executable = if (windows) "zig.exe" else "zig",
    sha256 = pin[[1L]], size = as.numeric(pin[[2L]])
  )
}

rzig_fetch_sha256 <- function(file) {
  tools_namespace <- asNamespace("tools")
  if (exists("sha256sum", envir = tools_namespace, inherits = FALSE)) {
    return(unname(get("sha256sum", envir = tools_namespace)(file)))
  }
  if (requireNamespace("digest", quietly = TRUE)) {
    return(digest::digest(file = file, algo = "sha256"))
  }
  stop("verifying the Zig archive needs R 4.5.0 or later, or the digest package", call. = FALSE)
}

# The download sources: the community mirrors (when `mirrors` is TRUE and the
# list can be read), rotated by the process id and the clock so concurrent
# installations spread over them, then ziglang.org. The rotation leaves R's
# random number stream untouched.
rzig_fetch_sources <- function(spec, mirrors = TRUE, mirror_list = NULL) {
  official <- sprintf("https://ziglang.org/download/%s/%s", spec$version, spec$file)
  if (!isTRUE(mirrors)) return(official)
  if (is.null(mirror_list)) {
    mirror_list <- tryCatch({
      connection <- url("https://ziglang.org/download/community-mirrors.txt")
      on.exit(close(connection), add = TRUE)
      readLines(connection, warn = FALSE)
    }, error = function(error) character(), warning = function(warning) character())
  }
  mirror_list <- sub("/+$", "", mirror_list[grepl("^https://[^[:space:]]+$", mirror_list)])
  if (length(mirror_list) > 1L) {
    start <- (Sys.getpid() + as.integer(as.numeric(Sys.time()) %% 100000)) %% length(mirror_list)
    mirror_list <- mirror_list[c(seq.int(start + 1L, length(mirror_list)), seq_len(start))]
  }
  c(sprintf("%s/%s?source=r-rzig", mirror_list, spec$file), official)
}

rzig_fetch_download <- function(url, destination, quiet) {
  old <- options(timeout = max(600, getOption("timeout", 60)))
  on.exit(options(old), add = TRUE)
  status <- tryCatch(
    suppressWarnings(utils::download.file(url, destination, mode = "wb", quiet = quiet, method = "libcurl")),
    error = function(error) 1L
  )
  identical(as.integer(status), 0L) && file.exists(destination)
}

# Archive members must stay inside the single top-level folder.
rzig_fetch_check_members <- function(members, top) {
  members <- sub("/+$", "", members)
  unsafe <- !length(members) || anyNA(members) || any(grepl("\\\\", members)) ||
    any(grepl("(^|/)\\.\\.(/|$)|^/|^[A-Za-z]:", members)) ||
    any(!(members == top | startsWith(members, paste0(top, "/"))))
  if (unsafe) stop("the Zig archive contains unexpected paths; nothing was extracted", call. = FALSE)
  invisible(TRUE)
}

rzig_fetch_version <- function(executable) {
  out <- tryCatch(suppressWarnings(system2(executable, "version", stdout = TRUE, stderr = TRUE, timeout = 60)),
    error = function(error) character())
  if (!is.null(attr(out, "status")) || length(out) != 1L) return("")
  trimws(out)
}

rzig_fetch_receipt <- ".rzig-zig.dcf"

# Install Zig `version` into `directory`/zig-<platform>-<version> and return
# the path of the executable. An existing installation with a matching
# receipt and version is reused.
rzig_fetch_install <- function(version, directory, platform = rzig_fetch_platform(), mirrors = TRUE,
                               quiet = FALSE, download = rzig_fetch_download, mirror_list = NULL,
                               inform = message) {
  spec <- rzig_fetch_spec(version, platform)
  directory <- path.expand(directory)
  target <- file.path(directory, spec$top)
  binary <- file.path(target, spec$executable)
  if (dir.exists(target)) {
    receipt <- file.path(target, rzig_fetch_receipt)
    fields <- if (file.exists(receipt)) tryCatch(read.dcf(receipt), error = function(error) NULL)
    if (is.null(fields) || !"Archive-SHA256" %in% colnames(fields) ||
        !identical(unname(fields[1L, "Archive-SHA256"]), spec$sha256) ||
        !identical(rzig_fetch_version(binary), version)) {
      stop("the folder ", target, " is not a complete Zig ", version,
        " installation by rzig; remove it and install again", call. = FALSE)
    }
    return(normalizePath(binary, winslash = "/", mustWork = TRUE))
  }
  if (!dir.exists(directory) && !dir.create(directory, recursive = TRUE, showWarnings = FALSE)) {
    stop("cannot create ", directory, call. = FALSE)
  }
  lock <- paste0(target, ".lock")
  if (!dir.create(lock, showWarnings = FALSE)) {
    stop("another installation of Zig ", version, " into ", directory, " is running; if none is, remove ",
      lock, call. = FALSE)
  }
  on.exit(unlink(lock, recursive = TRUE, force = TRUE), add = TRUE)
  stage <- tempfile("rzig-zig-", tmpdir = directory)
  dir.create(stage)
  on.exit(unlink(stage, recursive = TRUE, force = TRUE), add = TRUE)

  archive <- file.path(stage, spec$file)
  verified <- FALSE
  attempts <- character()
  for (source in rzig_fetch_sources(spec, mirrors, mirror_list)) {
    host <- sub("^https://([^/]+).*$", "\\1", source)
    unlink(archive)
    if (!download(source, archive, quiet)) {
      attempts <- c(attempts, paste(host, "(download failed)"))
      next
    }
    size <- file.info(archive)$size
    if (!identical(as.numeric(size), spec$size) || !identical(rzig_fetch_sha256(archive), spec$sha256)) {
      attempts <- c(attempts, paste(host, "(size or SHA-256 differs from the pinned archive)"))
      next
    }
    verified <- TRUE
    inform(sprintf("Downloaded and verified %s from %s", spec$file, host))
    break
  }
  unlink(if (!verified) archive)
  if (!verified) {
    stop("no source provided the pinned archive ", spec$file, ": ", paste(attempts, collapse = ", "),
      call. = FALSE)
  }

  unpack <- file.path(stage, "unpacked")
  dir.create(unpack)
  if (endsWith(spec$file, ".zip")) {
    rzig_fetch_check_members(utils::unzip(archive, list = TRUE)$Name, spec$top)
    utils::unzip(archive, exdir = unpack)
  } else {
    rzig_fetch_check_members(utils::untar(archive, list = TRUE, tar = "internal"), spec$top)
    status <- utils::untar(archive, exdir = unpack, tar = "internal")
    if (!identical(as.integer(status), 0L)) stop("could not extract ", spec$file, call. = FALSE)
  }
  unlink(archive)
  extracted <- file.path(unpack, spec$top)
  executable <- file.path(extracted, spec$executable)
  if (!file.exists(executable) || !identical(rzig_fetch_version(executable), version)) {
    stop("the verified archive ", spec$file, " did not provide a working zig ", version, call. = FALSE)
  }
  write.dcf(data.frame(
    Version = version, Platform = spec$platform, Archive = spec$file, "Archive-SHA256" = spec$sha256,
    check.names = FALSE
  ), file.path(extracted, rzig_fetch_receipt), width = 200L)
  if (!file.rename(extracted, target)) stop("could not move Zig into ", target, call. = FALSE)
  normalizePath(binary, winslash = "/", mustWork = TRUE)
}

if (sys.nframe() == 0L) {
  arguments <- commandArgs(trailingOnly = TRUE)
  tryCatch({
    if (length(arguments) != 2L) stop("usage: Rscript fetch_zig.R <version> <directory>", call. = FALSE)
    path <- rzig_fetch_install(arguments[[1L]], arguments[[2L]], quiet = TRUE,
      inform = function(...) message(...))
    cat(path, "\n", sep = "")
  }, error = function(error) {
    message("rzig: ", conditionMessage(error))
    quit(save = "no", status = 1L)
  })
}
