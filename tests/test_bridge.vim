" Run: LAB=<temporary lab> vim -Nu NONE -i NONE -n -es -S tests/test_bridge.vim
set nocompatible encoding=utf-8
let &runtimepath = $VIMRUNTIME . ',' . $LAB . '/vim-lsp,' . fnamemodify(expand('<sfile>'), ':p:h:h')
runtime plugin/lsp.vim
runtime plugin/deoplete_vim_lsp.vim
runtime autoload/deoplete_vim_lsp.vim
call lsp#register_server({'name': 'test', 'cmd': {s->[]}, 'allowlist': ['json'], 'config': {'refresh_pattern': '\("\k*\|\k\+\)$'}})
let s:script = filter(getscriptinfo(), {i,v -> v.name =~ '/autoload/deoplete_vim_lsp.vim$'})[0]
let s:Handler = function('<SNR>' . s:script.sid . '_handle_completion')

function! s:check(line, edit_start, request_col, keyword_byte, expected, incomplete) abort
  call setline(1, a:line)
  call cursor(1, strlen(a:line))
  let item = {'label': 'matchDepTypes', 'insertTextFormat': 2, 'textEdit': {'range': {'start': {'line': 0, 'character': a:edit_start}, 'end': {'line': 0, 'character': a:request_col}}, 'newText': '"matchDepTypes"'}}
  let data = {'response': {'result': {'items': [item], 'isIncomplete': a:incomplete}}}
  call s:Handler(lsp#get_server_info('test'), {'line': 0, 'character': a:request_col}, a:keyword_byte, data)
  call assert_equal(a:expected, g:deoplete#source#vim_lsp#_items[0].word)
  call assert_equal(a:incomplete, g:deoplete#source#vim_lsp#_incomplete)
  call assert_equal(1, g:deoplete#source#vim_lsp#_done)
  let managed = lsp#omni#get_managed_user_data_from_completed_item(g:deoplete#source#vim_lsp#_items[0])
  call assert_equal(item, managed.completion_item)
endfunction

call s:check('  " ', 2, 3, 3, 'matchDepTypes"', 0)
call s:check('  "m ', 2, 4, 3, 'matchDepTypes"', 0)
" Byte offsets stay correct when preceding text contains multiple-byte characters.
call s:check('é "m ', 2, 4, 4, 'matchDepTypes"', 1)
call s:check('  m ', 2, 3, 2, '"matchDepTypes"', 0)
if !empty(v:errors)
  call writefile(v:errors, $LAB . '/bridge-errors.txt')
  cquit
endif
qa!
