# Changelog

## v0.3.0 (2026-01-18)

- Added `select(expr)` filter for conditional output
- Added `has(key)` builtin for object membership
- Added `not` filter for boolean negation
- Added `tonumber` and `tostring` coercion builtins
- Arena allocator for query evaluation (lower peak memory on large inputs)
- Added `--version` flag

## v0.2.0 (2025-03-08)

- Added `-c` flag for compact (non-pretty) output
- Added `-r` flag for raw string output (no quotes)
- Added recursive descent operator `..`
- Improved unicode escape handling in strings
- Fixed integer vs float distinction in output

## v0.1.0 (2025-01-22)

Initial release.

- Dot-access: `.field`, `.a.b.c`
- Array index: `.[0]`, `.[-1]`
- Pipe: `.users | .[0]`
- Builtins: `keys`, `length`
- Reads from stdin or file argument
