Decision: **optimize the bulk RPC transfer and obsolete snapshot retention; retain
exact full-buffer snapshots and comparisons.** The measured regressions are
meaningful at 100,000 lines. The implementation keeps one shared Vim request
snapshot, returns only a boolean to Python, and clears the previous request's
lines on replacement or source cleanup. It adds one reference to the existing
request dictionary in place of Python's separate snapshot; it adds no validation
cache, per-buffer pool, change listener, or hash.

Reviewed PR #29 at `cc0dd3836788c707f0e9d68f079872ba7f5537c1`, confirmed as the
remote HEAD again after implementation. The comparison is `01c80c3`, immediately
before the snapshot commit, rather than the PR's original base. That version lacks
the Task 2 stale-context protections and is a performance reference only.

Measurements were taken on 2026-10-17, Linux x86-64, AMD EPYC 9V74 (three visible
vCPUs), Python 3.12.14, pynvim 0.6.0, Neovim 0.11.5, Vim 9.2.1202, Deoplete
`e5a47d4`, and vim-lsp `977e704`. The three buffers contain approximately 8 KiB,
801 KiB, and 7.82 MiB of text. Each path has five warmups and 100 samples (300
prefix-growth observations). Tables report **median / p95 in milliseconds**.
Reproduction commands and timing boundaries are in [README.md](README.md).

The isolated operations show that serialization, transfer, decoding, and Python
list/string allocation dominate the snapshot cost. `getbufline` and `getline`
have similar editor-side cost; changing between them would not address that
bottleneck. Equality alone is a small part of total validation cost.

| Lines | Neovim getline | Neovim getbufline | getbufline → Python RPC | Scalar RPC | Python equality | Vim-list equality |
| --- | --- | --- | --- | --- | --- | --- |
| 100 | 0.007 / 0.008 | 0.008 / 0.008 | 0.225 / 0.288 | 0.186 / 0.285 | 0.001 / 0.001 | 0.006 / 0.006 |
| 10000 | 0.318 / 0.392 | 0.311 / 0.409 | 4.453 / 4.982 | 0.188 / 0.355 | 0.108 / 0.154 | 0.110 / 0.172 |
| 100000 | 4.269 / 5.165 | 4.035 / 4.614 | 46.576 / 48.658 | 0.177 / 0.194 | 1.172 / 1.466 | 1.105 / 1.254 |

Native Vim confirms the linear capture/comparison costs independently of Python:

| Lines | Vim getline | Vim getbufline | Vim equality | Vim capture + normalize + equality |
| --- | --- | --- | --- | --- |
| 100 | 0.023 / 0.037 | 0.024 / 0.049 | 0.019 / 0.020 | 0.030 / 0.049 |
| 10000 | 0.550 / 0.795 | 0.569 / 0.780 | 0.217 / 0.326 | 1.001 / 1.266 |
| 100000 | 7.428 / 10.701 | 7.328 / 8.358 | 2.180 / 2.485 | 11.779 / 12.606 |

The controlled completion path calls the real source and bridge, delivers an
immediate fixture response through the real vim-lsp converter, and retrieves the
result through the source. It includes fixture-delivery RPC, but excludes LSP
server computation/transport, worker scheduling, and popup rendering. These are
completion-path costs, not keystroke-to-popup latencies.

| Lines | Pre-snapshot completion path | PR HEAD completion path | Optimized completion path |
| --- | --- | --- | --- |
| 100 | 3.567 / 3.836 | 3.184 / 4.095 | 3.866 / 4.392 |
| 10000 | 2.590 / 2.940 | 8.699 / 9.581 | 4.437 / 4.895 |
| 100000 | 3.360 / 3.581 | 60.884 / 78.001 | 12.812 / 14.858 |

Small buffers show no meaningful improvement: the 100-line completion path is
about 0.7 ms slower in this run, and cleanup adds a scalar RPC. The bridge
callback itself remains linear and is not faster; the large win is in source
request capture and prefix/poll validation. Large-buffer grown callback timing
varied by a few milliseconds between runs.

Request initiation alone, including capture and normal source/RPC housekeeping:

| Lines | Pre-snapshot request | PR HEAD request | Optimized request |
| --- | --- | --- | --- |
| 100 | 1.993 / 2.196 | 1.866 / 2.398 | 2.272 / 2.617 |
| 10000 | 1.476 / 1.718 | 7.201 / 7.952 | 2.928 / 3.273 |
| 100000 | 1.860 / 1.966 | 59.348 / 76.413 | 11.357 / 13.512 |

Prefix growth checks normalize the current line back to the original typed
prefix and compare every line, including text after the cursor. The separate
callback measurement covers its own validation and conversion after three edits.

| Lines | Pre-snapshot growth | PR HEAD growth | Optimized growth | PR HEAD repeat poll | Optimized repeat poll | PR HEAD grown callback | Optimized grown callback |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 100 | 0.482 / 0.560 | 0.745 / 0.953 | 0.689 / 0.886 | 0.741 / 1.012 | 0.694 / 0.940 | 0.524 / 0.636 | 0.493 / 0.679 |
| 10000 | 0.378 / 0.495 | 5.167 / 6.315 | 1.508 / 1.805 | 5.202 / 6.124 | 1.624 / 1.835 | 1.617 / 2.063 | 1.583 / 1.809 |
| 100000 | 0.374 / 0.451 | 51.724 / 59.484 | 10.366 / 11.885 | 51.705 / 58.042 | 11.807 / 13.063 | 10.510 / 12.145 | 13.083 / 14.795 |

`changedtick` avoids the full comparison when the buffer still has the original
request tick. Once a prefix grows, checks continue comparing against the original
snapshot, including repeated polls with no further edit. This remains intentional.
Rebasing only the tick would lose protection against cursor movement at the same
tick: `printf tail` with the cursor after `prin` has a different normalized suffix
than with the cursor after `printf`. Avoiding those scans safely would require
additional validated-input/cursor state. The measured improvement comes from
removing bulk transfer and duplication; no extra cache was needed.

The memory test holds 20 callbacks without responding, modeling superseded
requests still retained by transport. At PR HEAD each callback retains its own
full snapshot despite the bridge stopping its previous timer. In the inspected
vim-lsp client, callbacks are retained in `on_notifications` until response handling
removes them (`autoload/lsp/client.vim`, send and response paths). The bridge's
one-second timeout invalidates ownership but does not remove these transport
references. This is a retention stress case, not a claim that 20 requests are
normally outstanding.

| Lines | Python persistent snapshot, HEAD | Python persistent snapshot, optimized | Vim RSS added for 20 callbacks, HEAD | Vim RSS added for 20 callbacks, optimized | Retained Vim snapshot lines, HEAD → optimized |
| --- | --- | --- | --- | --- | --- |
| 100 | 0.012 MiB | 0 | 0.281 MiB | 0.039 MiB | 2,000 → 100 |
| 10000 | 1.245 MiB | 0 | 24.762 MiB | 0.000 MiB | 200,000 → 10,000 |
| 100000 | 12.399 MiB | 0 | 245.715 MiB | 0.000 MiB | 2,000,000 → 100,000 |

RSS is incremental from a warmed allocator. Zero added RSS in the optimized
case means freed allocations could be reused, not that snapshots consume no
memory. One active/cached Vim snapshot remains O(buffer size), and comparisons
still allocate a temporary list. PR HEAD additionally retains a Python snapshot
and builds another Python list for each changed-tick check; each 100,000-line
Python list plus strings is approximately 12.4 MiB, excluding transport and
allocator overhead. After optimization, old callback dictionaries retain only
small request metadata while the latest callback owns the single shared snapshot.
The snapshot remains available after completion/timeout so source reuse validation
can still reject subsequent unrelated edits.

The local change preserves exact text equality rather than replacing it with a
strict tick check or a hash. Generation guards still run before obsolete callbacks
can access discarded snapshots. Existing keyword/trigger rules, incomplete-result
refresh, malformed-response recovery, timeouts, and completion metadata conversion
remain in place. Added bridge regressions cover the shared source/callback check,
multiple ASCII/multibyte prefix edits, unrelated and trailing edits after a valid
check, added lines, cursor-only movement, cached-result invalidation, old-closure
snapshot release, and explicit cleanup. Source tests exercise validation success
and failure for both pending and cached results without fetching buffer lines.

Validation passed: **13 source tests, 10 Neovim acceptance tests, and 1 Vim
acceptance test (24 total, no skips)**; expanded bridge fixtures in both editors;
and `git diff --check`. The Vim acceptance test exercised the real Vim RPC adapter.
The initial development-profile wrapper loaded a cached duplicate Deoplete
manifest; clean editor paths avoided that contamination. Native Vim also required
pynvim on its embedded Python path and local-socket access.

Exact session regression commands (the dependency directory has symlinks to the
four dependencies described in `tests/README.md`):

```sh
export LAB=/workspace/scratch/review-lab
export NVIM=/workspace/.deoplete-env/nvim-linux-x86_64/bin/nvim
export VIM_BIN=/workspace/scratch/vim-clean
export PATH=/workspace/.deoplete-env/nvim-linux-x86_64/bin:$PATH
export PYTHONPATH=/workspace/.deoplete-env/venv/lib/python3.12/site-packages:/workspace/.deoplete-env/deps/deoplete.nvim/rplugin/python3
/workspace/.deoplete-env/venv/bin/python -m unittest discover -s tests -v
"$NVIM" -u NONE -i NONE --headless -n -S tests/test_bridge.vim
"$VIM_BIN" -Nu NONE -i NONE -n -es -S tests/test_bridge.vim
git diff --check
```

The repeatable benchmark and machine-readable results accompany this change.
Remaining costs are the one exact snapshot,
linear local comparisons, and existing source RPC housekeeping. Further caching
or incremental buffer tracking would add state and complexity beyond the measured
bulk-transfer/retention fix.
