# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-07-08

### Added

- Initial release of `lsz`
- List directory contents, sorted alphabetically
- `-a` / `--all` flag to show hidden (dotfile) entries
- Output via injected writer (fixes stdout vs stderr issue with `std.debug.print`)
- tty detection to distinguish terminal vs piped output
- Multi-column, column-major layout in terminal mode, matching real `ls` fill order
- One-entry-per-line output when piped
