# Contributing

## Building

```sh
zig build
zig build test
```

Requires Zig 0.13 or later.

## Guidelines

- One change per commit. Small focused diffs.
- Commit messages: `component: short description` (e.g. `query: fix pipe with empty input`)
- New filters need a test in `src/query_test.zig`
- No dependencies outside the Zig standard library

## Reporting bugs

Use the bug report template. Include the exact input JSON and query string that triggers the issue.
