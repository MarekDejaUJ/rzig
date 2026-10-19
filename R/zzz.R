.onLoad <- function(libname, pkgname) {
  # Register the knitr engine `zig` now if knitr is loaded, and otherwise when
  # it loads.
  .rzig_register_knitr_engine()
  setHook(packageEvent("knitr", "onLoad"), .rzig_register_knitr_engine)
  invisible()
}
