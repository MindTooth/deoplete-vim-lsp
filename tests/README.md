Run the source tests and editor acceptance tests with Python's existing unittest
discovery. `LAB` is a dependency directory containing checkouts (or symlinks) named
`deoplete.nvim` and `vim-lsp`. Python needs `pynvim`. The optional real Vim test
also needs `nvim-yarp` and `vim-hug-neovim-rpc` in `LAB`, Vim with `+python3`, and
permission to open the local socket used by its RPC adapter.

```sh
LAB=/path/to/dependencies \
NVIM=/path/to/nvim \
VIM_BIN=/path/to/vim \
PYTHONPATH=/path/to/dependencies/deoplete.nvim/rplugin/python3 \
python3 -m unittest discover -s tests -v

LAB=/path/to/dependencies vim -Nu NONE -i NONE -n -es -S tests/test_bridge.vim
LAB=/path/to/dependencies nvim -u NONE -i NONE --headless -n -S tests/test_bridge.vim
```

Acceptance tests skip when their editor or dependency directories are unavailable.
Use `VIM_BIN` to choose the Vim executable: Vim reserves `$VIM` for its installation
directory. When needed, use a wrapper that selects Vim's matching Python shared
library before starting the editor.

Verified dependencies: Deoplete `e5a47d4`, vim-lsp `8148119`, nvim-yarp `bb5f5e0`,
vim-hug-neovim-rpc `93ae387`, pynvim 0.6.0; Vim 9.2.1202 and Neovim 0.11.5.

The integration tests use a deterministic stdio language server, real Deoplete
workers, and real vim-lsp conversion and `CompleteDone` handling. They type into
Insert mode, wait for Deoplete to process each prefix, accept with Ctrl-N/Ctrl-Y,
and assert the resulting buffer after vim-lsp's deferred handler finishes.
Neovim tests also check original completion metadata and the resolve request.
The Vim test starts without a request-ID global, covering initialization through
the actual Vim RPC adapter. Existing bridge conversion and request-state fixtures
remain in `test_bridge.vim`.

The built-in vim-lsp snippet expander is covered. External snippet engines and
their jump mappings, supplementary Unicode characters requiring UTF-16 surrogate
pairs, differing `filterText`/inserted-text prefixes, multiple simultaneous
servers, and manual synchronous completion are outside these acceptance tests.
Real language servers and schema retrieval are not needed or exercised.
