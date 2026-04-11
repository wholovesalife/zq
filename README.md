# zq

Fast jq-like JSON query tool written in Zig. Zero dependencies, single static binary.

```
$ echo '{"name":"alice","age":30,"scores":[95,87,92]}' | zq '.name'
"alice"

$ echo '{"name":"alice","age":30,"scores":[95,87,92]}' | zq '.scores[1]'
87

$ cat users.json | zq '.[] | .email'
"alice@example.com"
"bob@example.com"
```

## Install

### Download binary

Grab the latest release from the [releases page](https://github.com/wholovesalife/zq/releases).

```sh
# Linux x86_64
curl -Lo zq https://github.com/wholovesalife/zq/releases/latest/download/zq-linux-x86_64
chmod +x zq
sudo mv zq /usr/local/bin/
```

### Build from source

Requires Zig 0.13+.

```sh
git clone https://github.com/wholovesalife/zq
cd zq
zig build -Doptimize=ReleaseFast
sudo cp zig-out/bin/zq /usr/local/bin/
```

## Install

Download the latest binary from [releases](https://github.com/wholovesalife/zq/releases) or build from source:

```sh
git clone https://github.com/wholovesalife/zq
cd zq
zig build -Doptimize=ReleaseFast
```

## Usage

```
zq [OPTIONS] <query> [file]
```

If no file is given, reads from stdin.

### Options

| Flag | Description |
|------|-------------|
| `-c` | Compact output (no pretty-print) |
| `-r` | Raw string output (no quotes around strings) |
| `-n` | Null input mode (use `null` as input) |

## Query syntax

### Identity

```sh
echo '{"a":1}' | zq '.'
# {"a": 1}
```

### Field access

```sh
echo '{"user":{"name":"bob","role":"admin"}}' | zq '.user.name'
# "bob"
```

### Array index

```sh
echo '[10,20,30]' | zq '.[1]'
# 20

# Negative index
echo '[10,20,30]' | zq '.[-1]'
# 30
```

### Array/object iterator

```sh
echo '[1,2,3]' | zq '.[]'
# 1
# 2
# 3
```

### Pipe

Chain filters with `|`:

```sh
echo '{"items":[{"id":1,"name":"foo"},{"id":2,"name":"bar"}]}' \
  | zq '.items | .[] | .name'
# "foo"
# "bar"
```

### `keys`

```sh
echo '{"b":2,"a":1,"c":3}' | zq 'keys'
# ["a","b","c"]
```

### `length`

```sh
echo '[1,2,3,4,5]' | zq 'length'
# 5

echo '"hello"' | zq 'length'
# 5

echo '{"a":1,"b":2}' | zq 'length'
# 2
```

### `type`

```sh
echo '42' | zq 'type'
# "number"
```

### `select(expr)`

Keep values where expr is truthy:

```sh
echo '[1,2,3,4,5]' | zq '.[] | select(. > 3)'
# Wait — comparison operators are on the roadmap. For now, select works with boolean paths:
echo '[{"active":true,"name":"a"},{"active":false,"name":"b"}]' \
  | zq '.[] | select(.active) | .name'
# "a"
```

### `has("key")`

```sh
echo '{"name":"alice","age":30}' | zq 'has("email")'
# false
```

### `to_entries`

```sh
echo '{"a":1,"b":2}' | zq 'to_entries'
# [{"key": "a","value": 1},{"key": "b","value": 2}]
```

### Recursive descent `..`

Emit every value in the document:

```sh
echo '{"a":{"b":{"c":42}}}' | zq '.. | .c' 2>/dev/null || \
echo '{"a":{"b":{"c":42}}}' | zq '..'
```

### `-r` raw strings

```sh
echo '{"name":"alice"}' | zq -r '.name'
# alice   (no quotes)
```

### `-c` compact

```sh
echo '{"a": 1, "b": [1, 2, 3]}' | zq -c '.'
# {"a":1,"b":[1,2,3]}
```

## Comparison with jq

| Feature | zq | jq |
|---------|----|----|
| Binary size | ~150 KB | ~1.5 MB |
| Dependencies | none | oniguruma |
| Startup time | ~1 ms | ~5–10 ms |
| Dot access | yes | yes |
| Array index | yes | yes |
| Pipe | yes | yes |
| `keys`, `length` | yes | yes |
| `select()` | partial | full |
| Math expressions | planned | yes |
| `env`, `$__loc__` | planned | yes |
| `@base64`, `@uri` | planned | yes |
| Streaming | planned | yes |

`zq` is faster on startup and produces smaller binaries. It's a good fit for scripts and CI where you just need to extract fields. For complex transformations, use jq.

### Benchmark

```
Benchmark: extract `.name` from 10,000-element array (repeated 1000×)

  zq:  0.31s total  (0.31 ms/call)
  jq:  1.82s total  (1.82 ms/call)

  ~5.9x faster (Apple M2, 10k records, query=.name)
```

## Planned

- Arithmetic and comparison in `select()`
- `map()`, `map_values()`, `reduce`
- `@base64`, `@uri`, `@csv`, `@tsv`
- `env` object
- `limit`, `first`, `last`, `range`
- Streaming parser for large files
<!-- -r (raw): only affects .string values; non-string values are printed normally -->
<!-- stdin: when no [file] argument is provided, zq reads from standard input until EOF -->
<!-- .. (recursive descent): emits values in pre-order — parent node before its children -->
<!-- binary size: zq strips to ~150 KB (ReleaseFast + strip=true); jq ships ~1.5 MB on most distros -->
<!-- exit codes: 0 on success, 1 on parse error or query error; stderr carries the message -->
<!-- select(expr): expr must evaluate to a boolean path; arithmetic comparisons are not yet supported -->
