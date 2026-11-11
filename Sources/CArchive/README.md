# System libarchive header bridge

This target contains public headers only. It links Apple's system `libarchive`
and does not contain, build, or bundle a libarchive implementation or use Homebrew.

The public headers and original `COPYING` are unmodified files from Apple's
open-source distribution, tag `libarchive-167.120.3`, commit
`bd801c53e444038cf4bfed8318033e3b5cbce341`:

- https://github.com/apple-oss-distributions/libarchive/tree/bd801c53e444038cf4bfed8318033e3b5cbce341/libarchive
- `include/archive.h`: upstream version 3.7.4, SHA-256 `ef41e104bb8c2cbaaae8c5ad6a05290abb3bf552863d1bf76921be1b9009b3f2`
- `include/archive_entry.h`: SHA-256 `38820b6b4e85b4b8be02a397c5c2e2411bc772936a2c6e52ccb4ede85a3575a4`
- `include/COPYING`: SHA-256 `b2cdf763345de2de34cebf54394df3c61a105c3b71288603c251f2fa638200ba`

The BSD notices remain in the headers and `include/COPYING`.

The locally inspected Xcode macOS 27.0 SDK omits these headers but ships
`usr/lib/libarchive.2.tbd` and its `libarchive.tbd` symlink. Its export list
contains the read callbacks, seek callback, ZIP/TAR/7-Zip format registration,
`archive_read_data`, encrypted-entry checks, and entry metadata accessors used
by the preview reader. The local system library reports libarchive 3.7.4.
No newer, unexported API is required.
