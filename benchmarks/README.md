Run `snapshots.py` with Python plus pynvim and a dependency directory containing
`deoplete.nvim` and `vim-lsp`. No server, dotfiles, network access, or installed
plugin configuration is used. On Linux it also reports the editor's RSS.

```sh
export LAB=/workspace/.deoplete-env/deps
export NVIM=/workspace/.deoplete-env/nvim-linux-x86_64/bin/nvim
PY=/workspace/.deoplete-env/venv/bin/python

"$PY" benchmarks/snapshots.py --samples 100 > /tmp/optimized.json

# Compare immutable revisions without changing the working checkout.
BENCH_DIR=$(mktemp -d)
mkdir "$BENCH_DIR/head" "$BENCH_DIR/pre"
git archive cc0dd3836788c707f0e9d68f079872ba7f5537c1 | tar -x -C "$BENCH_DIR/head"
git archive 01c80c3 | tar -x -C "$BENCH_DIR/pre"
"$PY" benchmarks/snapshots.py --samples 100 --root "$BENCH_DIR/head" > /tmp/head.json
"$PY" benchmarks/snapshots.py --samples 100 --root "$BENCH_DIR/pre" > /tmp/pre.json

# Native Vim primitives; JSON contains individual samples in seconds.
OUT=/tmp/vim-primitives.json /workspace/scratch/vim-clean \
  -Nu NONE -i NONE -n -es -S benchmarks/primitives.vim
```

Replace these session-specific executable/dependency paths as needed. The native
Vim command can use an ordinary `vim`; this session's `vim-clean` wrapper selects
the extracted Vim AppImage and its matching Python library without loading the
development profile. Run revisions sequentially on an otherwise idle machine.
`--lines 100 10000 100000` selects buffer sizes; these are also the defaults.

Buffers contain distinct, approximately 81-byte ASCII JSON-like lines, with
completion in the middle. Each metric has five warmups and 100 measured samples;
prefix growth has three checks per sample (`pri` → `prin` → `print` → `printf`).
The reported p95 uses nearest rank. Native editor timings use `reltime()`;
Python/RPC timings use `perf_counter()`. Setup, editor edits, context acquisition,
fixture resets, assertions, statistics, JSON output, and memory observations stay
outside measured intervals. RPC primitives prefetch the buffer number. Python
snapshot equality uses independently captured lists. Captured RPC-list disposal
is excluded from the isolated capture metric; real source paths include their
normal allocation and disposal costs. Tiny timer/dispatch/function-call costs
remain, so microsecond differences on the smallest buffer are not actionable.

`request_response_reuse` measures the real source request, bridge snapshot, an
immediate fixture response through the real vim-lsp converter, and source result
reuse. It includes the RPC command used to deliver the fixture response. It
excludes server computation/transport, Deoplete worker scheduling, popup rendering,
and keypress handling, so it is a controlled completion-path latency measurement,
not a keystroke-to-popup measurement. `grown_response_callback` measures callback
validation after three edits, separately from the source's prefix checks. Complete
and incomplete result behavior is verified by the regression suite.

The memory phase deliberately retains 20 transport callbacks, modeling superseded
requests whose server responses have not arrived. It runs after timing and records
both retained snapshot line counts and incremental RSS from the warmed allocator.
Zero incremental RSS does not mean zero live memory. `python_snapshot_bytes` sizes
an isolated list plus its strings; `python_retained_snapshot_bytes` sizes the
actual source's persistent snapshot, when present. These sizes exclude interpreter,
transport buffers, and allocator overhead. The optimized implementation retains
one Vim snapshot for the active/cached context; obsolete callback dictionaries
retain no buffer lines.

Measured results and the decision are in [REPORT.md](REPORT.md); machine-readable
measurements are in [results/](results/).
