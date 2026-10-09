" Run: LAB=<temporary lab> vim -Nu NONE -i NONE -n -es -S tests/test_bridge.vim
set nocompatible encoding=utf-8
let &runtimepath = $VIMRUNTIME . ',' . $LAB . '/vim-lsp,' . fnamemodify(expand('<sfile>'), ':p:h:h')
runtime plugin/lsp.vim
runtime plugin/deoplete_vim_lsp.vim
runtime autoload/deoplete_vim_lsp.vim
call lsp#register_server({'name': 'test', 'cmd': {s->[]}, 'allowlist': ['json'], 'config': {'refresh_pattern': '\("\k*\|\k\+\)$'}})
let s:script = filter(getscriptinfo(), {i,v -> v.name =~ '/autoload/deoplete_vim_lsp.vim$'})[0]
let s:Handler = function('<SNR>' . s:script.sid . '_handle_completion')

function! s:check(line, edit_start, request_col, keyword_byte, expected, incomplete, ...) abort
  call setline(1, a:line)
  call cursor(1, strlen(a:line))
  let item = {'label': 'matchDepTypes', 'insertTextFormat': 2, 'textEdit': {'range': {'start': {'line': 0, 'character': a:edit_start}, 'end': {'line': 0, 'character': a:request_col}}, 'newText': get(a:000, 0, '"matchDepTypes"')}}
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
" Replacement text may change the punctuation before Deoplete's keyword start.
call s:check('#r ', 0, 2, 1, 'rgb', 0, 'rgb(${1:})')
call s:check('#r ', 0, 2, 1, 'red', 0, 'red')

" Exercise ordinary items and InsertReplaceEdit through the real vim-lsp converter.
let s:range = {'start': {'line': 0, 'character': 0}, 'end': {'line': 0, 'character': 3}}
for item in [
      \ {'label': 'print'},
      \ {'label': 'print', 'insertText': 'print'},
      \ {'label': 'print', 'insertTextFormat': 2, 'textEdit': {'insert': s:range, 'replace': s:range, 'newText': 'print(${1:})'}},
      \ ]
  call setline(1, 'pri ')
  call cursor(1, 4)
  call s:Handler(lsp#get_server_info('test'), {'line': 0, 'character': 3}, 0, {'response': {'result': [item]}})
  call assert_equal('print', g:deoplete#source#vim_lsp#_items[0].word)
  call assert_equal(0, g:deoplete#source#vim_lsp#_incomplete)
  call assert_equal(item, lsp#omni#get_managed_user_data_from_completed_item(g:deoplete#source#vim_lsp#_items[0]).completion_item)
endfor

" Items can have different replacement starts; trim their shared text individually.
call setline(1, '#r ')
call cursor(1, 3)
let s:items = [
      \ {'label': 'red', 'textEdit': {'range': {'start': {'line': 0, 'character': 0}, 'end': {'line': 0, 'character': 2}}, 'newText': 'red'}},
      \ {'label': 'rgb', 'textEdit': {'range': {'start': {'line': 0, 'character': 1}, 'end': {'line': 0, 'character': 2}}, 'newText': 'rgb'}},
      \ ]
call s:Handler(lsp#get_server_info('test'), {'line': 0, 'character': 2}, 1, {'response': {'result': {'items': s:items, 'isIncomplete': v:false}}})
call assert_equal(['red', 'rgb'], map(copy(g:deoplete#source#vim_lsp#_items), 'v:val.word'))
if !empty(v:errors)
  call writefile(v:errors, $LAB . '/bridge-errors.txt')
  cquit
endif
qa!
