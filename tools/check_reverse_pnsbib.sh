#!/bin/sh
# Reverse-dependency check (CI job reverse-pnsbib): update pnsbib, the largest
# known client package, to the rzig being tested, then build it and run its
# native and R tests. pnsbib is read from GitHub unless PNSBIB_SOURCE names a
# local copy. Needs rzig installed (R_LIBS) and a supported Zig on PATH or ZIG.
set -eu

work=$(mktemp -d "${TMPDIR:-/tmp}/rzig-reverse.XXXXXX")
trap 'rm -rf "$work"' EXIT
if test -n "${PNSBIB_SOURCE:-}"; then
    cp -R "$PNSBIB_SOURCE" "$work/pnsbib"
else
    git clone --quiet --depth 1 https://github.com/MarekDejaUJ/pnsbib.git "$work/pnsbib"
fi
cd "$work/pnsbib"
rm -rf src/rzig/.zig-cache src/rzig/.zig-global-cache src/rzig/zig-out src/*.o src/*.so src/Makevars

Rscript -e 'rzig::update_rzig(".")'
# pnsbib releases up to 0.2.1 restore two internal routines with a script;
# later releases mark them `/// @export internal`.
if test -f tools/sync-risk-bindings.R && ! grep -q '@export internal' src/rzig/src/main.zig; then
    Rscript tools/sync-risk-bindings.R .
fi
Rscript -e 'status <- rzig::rzig_status("."); print(status); structural <- c("DESCRIPTION", "Scaffold", "Zig source", "Exports"); stopifnot(all(status$ok[status$step %in% structural]))'

zig_bin=${ZIG:-$(command -v zig)}
if grep -q '"test"' src/rzig/build.zig; then
    (cd src/rzig && ZIG_GLOBAL_CACHE_DIR="$work/zig-cache" "$zig_bin" build test --cache-dir "$work/zig-local")
fi

mkdir -p "$work/lib"
R CMD INSTALL --no-multiarch --library="$work/lib" . > "$work/install.log" 2>&1 || {
    cat "$work/install.log"
    exit 1
}
R_LIBS="$work/lib${R_LIBS:+:$R_LIBS}" Rscript -e '
library(testthat)
library(pnsbib)
result <- as.data.frame(test_dir("tests/testthat", package = "pnsbib", load_package = "installed",
  reporter = "summary", stop_on_failure = FALSE))
cat(sprintf("pnsbib tests: %d failed, %d errors, %d skipped, %d expectations passed\n",
  sum(result$failed), sum(result$error), sum(result$skipped), sum(result$passed)))
stopifnot(sum(result$failed) == 0L, !any(result$error))
'
echo "pnsbib builds and passes its tests with this rzig"
