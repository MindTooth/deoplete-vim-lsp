"""Run with PYTHONPATH=<deoplete.nvim>/rplugin/python3 python3 -m unittest discover -s tests."""
import importlib.util
import re
from pathlib import Path
from types import SimpleNamespace
import unittest

from deoplete.child import Child

spec = importlib.util.spec_from_file_location(
    'vim_lsp', Path(__file__).parents[1] / 'rplugin/python3/deoplete/sources/vim_lsp.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class Vim:
    def __init__(self):
        self.vars = {'deoplete#sources#vim_lsp#log': ''}
        self.requests = []
        self.triggers = ['"', ':', '[', '.']

    def call(self, name, *args):
        if name == 'lsp#get_allowed_servers':
            return ['test']
        if name == 'lsp#get_server_status':
            return 'running'
        if name == 'lsp#get_server_capabilities':
            return {'completionProvider': {'triggerCharacters': self.triggers}}
        if name == 'deoplete_vim_lsp#request':
            self.requests.append(args)
        if name == 'deoplete#custom#_get_option':
            return {'auto_complete': True, 'auto_complete_popup': 'auto'}[args[0]]
        if name == 'getbufvar':
            return 0


def context(text, line=1, bufnr=1):
    return {'input': text, 'position': [0, line, len(text)+1, 0],
            'complete_position': re.search(r'\w*$|$', text).start(),
            'bufnr': bufnr, 'filetypes': ['json'], 'event': 'TextChangedI'}


class SourceTests(unittest.TestCase):
    def setUp(self):
        self.vim = Vim()
        self.source = module.Source(self.vim)
        self.source.min_pattern_length = 1

    def respond(self, incomplete=False):
        self.vim.vars['deoplete#source#vim_lsp#_items'] = [{'word': 'matchDepTypes"'}]
        self.vim.vars['deoplete#source#vim_lsp#_done'] = True
        self.vim.vars['deoplete#source#vim_lsp#_incomplete'] = incomplete

    def test_complete_quote_response_survives_prefix_without_request(self):
        self.source.gather_candidates(context('  "'))
        self.respond()
        for text in ['  "', '  "m', '  "ma', '  "match']:
            self.assertEqual(self.source.gather_candidates(context(text)), [{'word': 'matchDepTypes"'}])
        self.assertEqual(self.vim.requests, [('test', 3, 2)])

    def test_incomplete_response_refreshes_only_on_changed_input(self):
        self.source.gather_candidates(context('fmt.'))
        self.respond(True)
        self.assertTrue(self.source.gather_candidates(context('fmt.')))
        self.assertEqual(self.source.gather_candidates(context('fmt.P')), [])
        self.assertEqual(len(self.vim.requests), 2)
        self.respond(True)
        self.assertEqual(self.source.gather_candidates(context('fmt.Pr')), [])
        self.assertEqual(len(self.vim.requests), 3)

    def test_changed_anchor_line_and_backspace_invalidate(self):
        self.source.requested_context = context('  "ma')
        for text in ['other "match', '  "m', '  "max;other', '  "mb']:
            self.assertFalse(self.source.match_context(context(text)), text)
        self.assertFalse(self.source.match_context(context('  "match', 2)))
        self.assertTrue(self.source.match_context(context('  "match')))

    def test_new_negotiated_trigger_refreshes(self):
        self.source.gather_candidates(context('fmt'))
        self.respond()
        self.assertEqual(self.source.gather_candidates(context('fmt.')), [])
        self.assertEqual(len(self.vim.requests), 2)

    def test_buffer_entry_clears_items_and_invalidates_pending_request(self):
        self.source.gather_candidates(context('pri'))
        request_id = self.vim.requests[-1][-1]
        self.respond()
        self.source.on_event({'event': 'BufEnter'})
        self.assertEqual(self.vim.vars['deoplete#source#vim_lsp#_items'], [])
        self.assertGreater(self.vim.vars['deoplete#source#vim_lsp#_request_id'], request_id)
        self.assertEqual(self.source.gather_candidates(context('pri', bufnr=2)), [])
        self.assertEqual(len(self.vim.requests), 2)

    def test_buffer_identity_prevents_reuse_without_event(self):
        self.source.gather_candidates(context('pri'))
        self.respond()
        self.assertEqual(self.source.gather_candidates(context('pri', bufnr=2)), [])
        self.assertEqual(len(self.vim.requests), 2)

    def test_changed_pending_context_sends_new_request(self):
        for new_context in [context('other'), context('pr'), context('pri', line=2)]:
            with self.subTest(context=new_context):
                self.source.clean_state()
                self.source.gather_candidates(context('pri'))
                request_id = self.vim.requests[-1][-1]
                self.assertEqual(self.source.gather_candidates(new_context), [])
                self.assertGreater(self.vim.requests[-1][-1], request_id)

    def test_failed_request_retries_when_typing_resumes(self):
        self.source.gather_candidates(context('pri'))
        self.respond(incomplete=True)
        self.vim.vars['deoplete#source#vim_lsp#_items'] = []
        self.assertEqual(self.source.gather_candidates(context('pri')), [])
        self.assertEqual(len(self.vim.requests), 1)
        self.assertEqual(self.source.gather_candidates(context('prin')), [])
        self.assertEqual(len(self.vim.requests), 2)

    def test_real_deoplete_minimum_and_trigger_gate(self):
        child = SimpleNamespace(_vim=self.vim)
        for minimum in [1, 2]:
            self.source.min_pattern_length = minimum
            for text, prefix, expected in [('  "', '', False), ('  "m', 'm', minimum > 1),
                                           ('  "ma', 'ma', False), ('  ;', '', True), ('  ', '', True)]:
                ctx = dict(context(text), complete_str=prefix)
                self.assertEqual(Child._is_skip(child, ctx, self.source), expected, (minimum, text))

    def test_unadvertised_dot_and_pattern_override(self):
        self.vim.triggers = ['"', '[']
        self.assertNotRegex('fmt.', self.source.get_input_pattern('go'))
        self.source.input_pattern = r'!$'
        self.assertEqual(self.source.get_input_pattern('go'), r'!$')
        self.source.input_patterns = {'go': r'\?$'}
        self.assertEqual(self.source.get_input_pattern('go'), r'\?$')


if __name__ == '__main__':
    unittest.main()
