# lsz

<p align="center">
  <img src="https://img.shields.io/badge/status-active%20development-2ea44f?style=for-the-badge" alt="Active Development">
</p>

![Zig](https://img.shields.io/badge/Zig-0.16.0-orange)
![Version](https://img.shields.io/github/v/tag/JourneyCodesAyush/lsz?label=latest&color=purple)

[`ls`](https://man7.org/linux/man-pages/man1/ls.1.html) in Zig — built from scratch to to calm the itch to build something.

## Features

- Lists directory contents, sorted alphabetically
- `-a` / `--all` to show hidden (dotfile) entries
- Multi-column, column-major layout in terminal mode (matches real `ls` fill order)
- One-entry-per-line output when piped (`lsz | grep`, `lsz > file.txt`)

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
```

---

## Project Structure

```
lsz/
│
├── src/
│   ├── main.zig     # Arg parsing, tty detection, output writer setup
│   └── list.zig     # PrintDirectoryContents: collects, sorts, and prints entries
│
├── build.zig
├── build.zig.zon
├── LICENSE          # MIT
└── README.md        # You're reading it!
```

---

## Notes

- Terminal width is currently hardcoded to 80 columns (matches GNU `ls`'s own fallback) until Windows console API support stabilizes in upstream Zig.

---

## License

MIT - See [LICENSE](LICENSE)
