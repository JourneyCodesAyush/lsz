# lsz

<p align="center">
  <img src="https://img.shields.io/badge/status-dormant-inactive?style=for-the-badge" alt="Dormant">
</p>

![Zig](https://img.shields.io/badge/Zig-0.16.0-orange)
![Version](https://img.shields.io/github/v/tag/JourneyCodesAyush/lsz?label=latest&color=purple)

[`ls`](https://man7.org/linux/man-pages/man1/ls.1.html) in Zig — built from scratch to scratch an itch.

## Features

- Lists directory contents, sorted alphabetically
- `-a` / `--all` to show hidden (dotfile) entries
- `-l` / `--long` long listing format: permissions, link count, size, modification time, and name
- Multi-column, column-major layout in terminal mode (matches real `ls` fill order)
- One-entry-per-line output when piped (`lsz | grep`, `lsz > file.txt`)
- Dynamic terminal width detection on Linux

---

## Build

Requires Zig 0.16.0.

```bash
zig build
```

---

## Usage

```bash
lsz [path]
lsz -a [path]
lsz -l [path]
lsz -la [path]
```

---

## Project Structure

```
lsz/
│
├── src/
│   ├── main.zig     # Arg parsing, tty detection, output writer setup
│   ├── list.zig     # PrintDirectoryContents: collects, sorts, and prints entries
│   └── utils.zig    # Terminal width detection, rata-die date conversion for -l
│
├── build.zig
├── build.zig.zon
├── LICENSE          # MIT
└── README.md        # You're reading it!
```

---

## Notes

- Terminal width is dynamically detected on Linux via `ioctl(TIOCGWINSZ)`. Other platforms currently fall back to a hardcoded 80 columns (matches GNU `ls`'s own fallback) — macOS support is deferred pending testing access, and Windows console API support is unresolved upstream in Zig 0.16.
- `-l` currently omits owner/group columns and the `total` summary line real `ls -l` prints; these may be added later.

---

## License

MIT - See [LICENSE](LICENSE)
