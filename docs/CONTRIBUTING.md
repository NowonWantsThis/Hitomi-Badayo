# Contributing

Contributions are welcome. By submitting a contribution, you agree that it may
be distributed under the project's MIT License.

## Development requirements

- Apple silicon Mac
- macOS 14 or later
- Xcode command-line tools

Build the application with:

```sh
./build.sh
```

Run the tests related to the files and sources you changed. Many checks under
`Tests/` are standalone Swift or shell regressions and document their expected
invocation in the script itself.

## Contribution rules

- Do not submit proprietary source, decompiled code, executable extracts, or
  assets copied from another application.
- Do not commit real cookies, credentials, browser databases, private URLs,
  account identifiers, download history, or downloaded media.
- Use synthetic fixtures and reserved example domains in tests.
- Keep source-specific changes isolated and add a focused regression test.
- Preserve cancellation, retry, output naming, and queue ordering semantics.
- Document third-party code or assets and include their required license text.
- Run `./Scripts/check-public-tree.sh` before preparing a commit.

The maintainer should review provenance and redistribution rights separately
from code quality before accepting any contribution.
