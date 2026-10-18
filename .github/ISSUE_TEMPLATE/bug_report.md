---
name: Bug report
about: A package using rzig fails to build, to load or to compute correctly
labels: bug
---

**What happens**

A short description, and the error message or the wrong result.

**What should happen**

**Minimal example**

The exported Zig function (and the R call) that shows the problem:

```zig
/// @export
pub fn example(x: []const f64) f64 {
    ...
}
```

**Versions**

- Output of `rzig::rzig_status(path)` for the package:
- `packageVersion("rzig")`:
- `rzig::find_zig()`:
- `sessionInfo()` (R version and platform):
