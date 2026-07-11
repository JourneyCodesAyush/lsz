# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v0.2.0 - 2026-07-11

### Added

- `-l` / `--long` long listing format: permissions, link count, size,
  modification time, and name columns.
- Modification-time formatting follows `ls` convention: `Mon DD HH:MM`
  for entries modified within ~6 months, `Mon DD  YYYY` otherwise.
- Terminal width detection on Linux via `ioctl(TIOCGWINSZ)`, replacing
  the previous hardcoded 80-column fallback (still used on other
  platforms).
- Doc comments (`//!`, `///`) added throughout for Zig autodoc.

### Fixed

- Sort now runs before visible-entry extraction, preventing misaligned
  pointers in grid layout after sorting.
- Directory reopening in long format now tracks the actual listed
  directory (`root`) instead of assuming cwd, fixing `FileNotFound`
  when listing non-cwd paths with `-l`.

### Known limitations

- Owner/group columns not implemented.
- No `total` summary line in long format.
- Directory `/` suffix is included in sort comparison, which can
  diverge from real `ls` ordering.

## [0.1.0] - 2026-07-08

### Added

- Initial release of `lsz`
- List directory contents, sorted alphabetically
- `-a` / `--all` flag to show hidden (dotfile) entries
- Output via injected writer (fixes stdout vs stderr issue with `std.debug.print`)
- tty detection to distinguish terminal vs piped output
- Multi-column, column-major layout in terminal mode, matching real `ls` fill order
- One-entry-per-line output when piped
