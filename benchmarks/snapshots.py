#!/usr/bin/env python3
"""Snapshot/completion microbenchmark; see benchmarks/README.md. Requires pynvim."""
import argparse
import gc
import importlib.util
import json
import math
import os
from pathlib import Path
import statistics
import sys
import time

import pynvim


def summary(values):
    values = sorted(values)
    return {'median_ms': round(statistics.median(values) * 1000, 4),
            'p95_ms': round(values[math.ceil(len(values) * .95) - 1] * 1000, 4)}


def measure(fn, samples):
    values = []
    for _ in range(5):
        fn()
    for _ in range(samples):
        start = time.perf_counter()
        result = fn()
        elapsed = time.perf_counter() - start
        values.append(elapsed)
        del result  # Destruction of a transferred list is outside the timer.
    return summary(values)


def rss(pid):
    for line in Path(f'/proc/{pid}/status').read_text().splitlines():
        if line.startswith('VmRSS:'):
            return int(line.split()[1]) * 1024


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--lab', type=Path, default=Path(os.environ.get('LAB', '/nonexistent')))
    parser.add_argument('--nvim', default=os.environ.get('NVIM', 'nvim'))
    parser.add_argument('--samples', type=int, default=100)
    parser.add_argument('--lines', type=int, nargs='+', default=[100, 10000, 100000])
    args = parser.parse_args()
    sys.path.insert(0, str(args.lab / 'deoplete.nvim/rplugin/python3'))
    spec = importlib.util.spec_from_file_location('vim_lsp_bench', args.root / 'rplugin/python3/deoplete/sources/vim_lsp.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    out = {'root': str(args.root), 'python': sys.version, 'samples': args.samples, 'buffers': []}
    for count in args.lines:
        vim = pynvim.attach('child', argv=[args.nvim, '--embed', '--headless', '-u', 'NONE', '-i', 'NONE', '-n'])
        try:
            def q(path):
                return "'" + str(path).replace("'", "''") + "'"
            vim.command('let &rtp = $VIMRUNTIME . ' + q(',' + str(args.lab / 'vim-lsp') + ',' + str(args.root)))
            vim.command('runtime plugin/lsp.vim')
            vim.command('runtime plugin/deoplete_vim_lsp.vim')
            vim.command('runtime autoload/deoplete_vim_lsp.vim')
            vim.command("call lsp#register_server({'name':'test','cmd':{s->[]},'allowlist':['json']})")
            vim.command('source ' + str(Path(__file__).resolve().parents[1] / 'tests/fixtures/autoload/lsp.vim'))
            vim.command('let g:test_lsp_requests = []')
            vim.command('set virtualedit=onemore')
            vim.current.buffer[:] = [f'    "key_{i:06d}": "' + 'x' * 60 + '",' for i in range(count)]
            index = count // 2
            vim.current.buffer[index] = 'pri tail'
            vim.current.window.cursor = (index + 1, 3)
            bufnr = vim.current.buffer.number
            source = module.Source(vim)
            source.server_capabilities = {'test': {'completionProvider': {'triggerCharacters': ['.']}}}
            vim.command('source ' + str(Path(__file__).resolve().parent / 'primitives.vim'))
            row = {'lines': count, 'text_bytes': sum(len(s) + 1 for s in vim.current.buffer[:]), 'timings': {}}
            timings = row['timings']
            for kind in ['capture_getline', 'capture_getbufline', 'compare', 'capture_compare']:
                timings['vim_' + kind] = summary(vim.call('BenchPrimitive', kind, args.samples))
            timings['rpc_noop'] = measure(lambda: vim.call('getbufvar', bufnr, 'changedtick'), args.samples)
            timings['rpc_snapshot'] = measure(lambda: vim.call('getbufline', bufnr, 1, '$'), args.samples)
            left = vim.call('getbufline', bufnr, 1, '$')
            right = vim.call('getbufline', bufnr, 1, '$')
            timings['python_compare'] = measure(lambda: left == right, args.samples)
            row['python_snapshot_bytes'] = sys.getsizeof(left) + sum(map(sys.getsizeof, left))
            del left, right
            gc.collect()
            def context(text='pri'):
                return {'input': text, 'position': [0, index + 1, len(text) + 1, 0],
                        'complete_position': 0, 'bufnr': bufnr,
                        'changedtick': vim.eval('b:changedtick')}
            ctx = context()
            def request():
                # Exercise the real source and bridge; only transport is a fixture.
                source.request_lsp_completion('test', ctx)
            request_times = []
            e2e_times = []
            for sample in range(args.samples + 5):
                vim.command('let g:test_lsp_requests = []')
                start = time.perf_counter()
                request()
                after_request = time.perf_counter()
                vim.command("call call(g:test_lsp_requests[-1].on_notification, [{'response': {'result': [{'label': 'print'}]}}])")
                result = source.async_completion('test', ctx)
                elapsed = time.perf_counter() - start
                assert result
                if sample >= 5:
                    request_times.append(after_request - start)
                    e2e_times.append(elapsed)
            timings['source_request'] = summary(request_times)
            timings['request_response_reuse'] = summary(e2e_times)
            growth_times, poll_times, callback_times = [], [], []
            for sample in range(args.samples + 5):
                vim.command('let g:test_lsp_requests = []')
                vim.current.buffer[index] = 'pri tail'
                vim.current.window.cursor = (index + 1, 3)
                ctx = context()
                request()
                for suffix in ['n', 'nt', 'ntf']:
                    text = 'pri' + suffix
                    vim.current.buffer[index] = text + ' tail'
                    vim.current.window.cursor = (index + 1, len(text))
                    grown = context(text)
                    start = time.perf_counter()
                    matched = source.match_context(grown)
                    elapsed = time.perf_counter() - start
                    assert matched
                    if sample >= 5:
                        growth_times.append(elapsed)
                start = time.perf_counter()
                matched = source.match_context(grown)
                elapsed = time.perf_counter() - start
                assert matched
                if sample >= 5:
                    poll_times.append(elapsed)
                start = time.perf_counter()
                vim.command("call call(g:test_lsp_requests[-1].on_notification, [{'response': {'result': [{'label': 'print'}]}}])")
                elapsed = time.perf_counter() - start
                assert vim.vars['deoplete#source#vim_lsp#_items']
                if sample >= 5:
                    callback_times.append(elapsed)
            timings['prefix_growth_match'] = summary(growth_times)
            timings['repeat_poll_match'] = summary(poll_times)
            timings['grown_response_callback'] = summary(callback_times)
            # Memory phase is separate from all timing. Keep old transport callbacks,
            # as vim-lsp can do for superseded requests awaiting server responses.
            vim.command('let g:test_lsp_requests = []')
            source.clean_state()
            before = rss(vim.call('getpid'))
            for _ in range(20):
                request()
            row['vim_rss_20_retained_requests_delta_bytes'] = rss(vim.call('getpid')) - before
            row['retained_callbacks'] = vim.eval('len(g:test_lsp_requests)')
            row['python_retained_snapshot_bytes'] = (sys.getsizeof(source.requested_lines) +
                sum(map(sys.getsizeof, source.requested_lines))) if hasattr(source, 'requested_lines') else 0
            row['vim_retained_snapshot_lines'] = vim.eval(
                'map(copy(g:test_lsp_requests), "len(get(get(v:val.on_notification, \'args\')[1], \'lines\', []))")')
            out['buffers'].append(row)
            out['nvim'] = vim.command_output('version').strip().splitlines()[0]
        finally:
            try:
                vim.command('qa!')
            except (EOFError, OSError):
                pass
            vim.close()
    print(json.dumps(out, indent=2))


if __name__ == '__main__':
    main()
