" Run: LAB=<temporary lab> vim -Nu NONE -i NONE -n -es -S tests/test_bridge.vim
set nocompatible encoding=utf-8
let &runtimepath = $VIMRUNTIME . ',' . $LAB . '/vim-lsp,' . fnamemodify(expand('<sfile>'), ':p:h:h')
runtime plugin/lsp.vim
runtime plugin/deoplete_vim_lsp.vim
runtime autoload/deoplete_vim_lsp.vim
call lsp#register_server({'name': 'test', 'cmd': {s->[]}, 'allowlist': ['json'], 'config': {'refresh_pattern': '\("\k*\|\k\+\)$'}})
let s:script = filter(getscriptinfo(), {i,v -> v.name =~ '/autoload/deoplete_vim_lsp.vim$'})[0]
let s:Handler = function('<SNR>' . s:script.sid . '_handle_completion')

function! s:request(position, complete_position) abort
  let g:deoplete#source#vim_lsp#_request_id = get(g:, 'deoplete#source#vim_lsp#_request_id', 0) + 1
  let g:deoplete#source#vim_lsp#_done = 0
  let g:deoplete#source#vim_lsp#_items = []
  let g:deoplete#source#vim_lsp#_incomplete = 0
  return {'id': g:deoplete#source#vim_lsp#_request_id, 'bufnr': bufnr('%'), 'position': a:position, 'complete_position': a:complete_position, 'input': strpart(getline('.'), 0, col('.') - 1), 'changedtick': b:changedtick, 'lines': getline(1, '$')}
endfunction

function! s:check(line, edit_start, request_col, keyword_byte, expected, incomplete, ...) abort
  call setline(1, a:line)
  call cursor(1, strlen(a:line))
  let item = {'label': 'matchDepTypes', 'insertTextFormat': 2, 'textEdit': {'range': {'start': {'line': 0, 'character': a:edit_start}, 'end': {'line': 0, 'character': a:request_col}}, 'newText': get(a:000, 0, '"matchDepTypes"')}}
  let data = {'response': {'result': {'items': [item], 'isIncomplete': a:incomplete}}}
  call s:Handler(lsp#get_server_info('test'), s:request({'line': 0, 'character': a:request_col}, a:keyword_byte), data)
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
  call s:Handler(lsp#get_server_info('test'), s:request({'line': 0, 'character': 3}, 0), {'response': {'result': [item]}})
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
call s:Handler(lsp#get_server_info('test'), s:request({'line': 0, 'character': 2}, 1), {'response': {'result': {'items': s:items, 'isIncomplete': v:false}}})
call assert_equal(['red', 'rgb'], map(copy(g:deoplete#source#vim_lsp#_items), 'v:val.word'))

" Exercise the real request/timer path without launching a language server.
execute 'source ' . fnameescape(fnamemodify(expand('<sfile>'), ':p:h') . '/fixtures/autoload/lsp.vim')
let g:test_lsp_requests = []
call setline(1, 'pri ')
call cursor(1, 4)
let s:old = s:request({'line': 0, 'character': 3}, 0)
call deoplete_vim_lsp#request('test', 0, s:old.id)
let s:new = s:request({'line': 0, 'character': 3}, 0)
call deoplete_vim_lsp#request('test', 0, s:new.id)
call assert_equal('textDocument/completion', g:test_lsp_requests[1].method)
call assert_equal({'line': 0, 'character': 3}, g:test_lsp_requests[1].params.position)
call call(g:test_lsp_requests[0].on_notification, [{'response': {'result': [{'label': 'old'}]}}])
call assert_equal(0, g:deoplete#source#vim_lsp#_done)
call call(g:test_lsp_requests[1].on_notification, [{'response': {'result': [{'label': 'new'}]}}])
call assert_equal('new', g:deoplete#source#vim_lsp#_items[0].word)
call call(g:test_lsp_requests[0].on_notification, [{'response': {'result': [{'label': 'old'}]}}])
call assert_equal('new', g:deoplete#source#vim_lsp#_items[0].word)

for data in [{'response': {'error': {'code': -32603, 'message': 'failed'}}}, {}, {'response': {'result': {'items': []}}}]
  call s:Handler(lsp#get_server_info('test'), s:request({'line': 0, 'character': 3}, 0), data)
  call assert_equal(1, g:deoplete#source#vim_lsp#_done)
  call assert_equal([], g:deoplete#source#vim_lsp#_items)
  call assert_equal(1, g:deoplete#source#vim_lsp#_incomplete)
endfor

let s:pending = s:request({'line': 0, 'character': 3}, 0)
call deoplete_vim_lsp#request('test', 0, s:pending.id)
sleep 1100m
call assert_equal(1, g:deoplete#source#vim_lsp#_done)
call assert_equal([], g:deoplete#source#vim_lsp#_items)
call assert_equal(1, g:deoplete#source#vim_lsp#_incomplete)
call call(g:test_lsp_requests[-1].on_notification, [{'response': {'result': [{'label': 'too_late'}]}}])
call assert_equal([], g:deoplete#source#vim_lsp#_items)

let s:pending = s:request({'line': 0, 'character': 3}, 0)
noautocmd new
call setline(1, 'pri ')
call cursor(1, 4)
call s:Handler(lsp#get_server_info('test'), s:pending, {'response': {'result': [{'label': 'wrong_buffer'}]}})
call assert_equal([], g:deoplete#source#vim_lsp#_items)
call assert_equal(1, g:deoplete#source#vim_lsp#_done)

let s:pending = s:request({'line': 0, 'character': 3}, 0)
call setline(1, 'other ')
call cursor(1, 6)
call s:Handler(lsp#get_server_info('test'), s:pending, {'response': {'result': [{'label': 'wrong_anchor'}]}})
call assert_equal([], g:deoplete#source#vim_lsp#_items)

" Valid prefix growth still accepts the response to the original request.
call setline(1, 'pri ')
call cursor(1, 4)
let s:pending = s:request({'line': 0, 'character': 3}, 0)
call setline(1, 'prin ')
call cursor(1, 5)
call s:Handler(lsp#get_server_info('test'), s:pending, {'response': {'result': [{'label': 'print'}]}})
call assert_equal('print', g:deoplete#source#vim_lsp#_items[0].word)

" Capture real request closures for lifecycle regressions, including duplicate delivery.
function! s:start() abort
  let request = s:request({'line': line('.') - 1, 'character': col('.') - 1}, 0)
  call deoplete_vim_lsp#request('test', 0, request.id)
  return g:test_lsp_requests[-1].on_notification
endfunction

function! s:success(Callback, label) abort
  call call(a:Callback, [{'response': {'result': [{'label': a:label}]}}])
endfunction

function! s:recovered() abort
  let Callback = s:start()
  call s:success(Callback, 'recovered')
  call assert_equal('recovered', g:deoplete#source#vim_lsp#_items[0].word)
  let generation = g:deoplete#source#vim_lsp#_request_id
  call s:success(Callback, 'duplicate')
  call assert_equal('recovered', g:deoplete#source#vim_lsp#_items[0].word)
  call assert_equal(generation, g:deoplete#source#vim_lsp#_request_id)
endfunction

" Editing elsewhere must invalidate even when the completion prefix also grows.
for grow in [0, 1]
  call setline(1, ['header', 'pri tail'])
  call cursor(2, 4)
  let s:Callback = s:start()
  call setline(1, 'changed header')
  if grow
    call setline(2, 'prin tail')
    call cursor(2, 5)
  endif
  call assert_equal(0, deoplete_vim_lsp#matches_context(bufnr('%'), line('.'), strpart(getline('.'), 0, col('.') - 1)))
  call s:success(s:Callback, 'stale')
  call assert_equal([], g:deoplete#source#vim_lsp#_items)
  call assert_equal(1, g:deoplete#source#vim_lsp#_incomplete)
  call s:recovered()
endfor

" Prefix replacement, deletion, line changes, and edits after the cursor are stale.
for change in ['replace', 'delete', 'line', 'tail']
  call setline(1, ['header', 'pri tail'])
  call cursor(2, 4)
  let s:Callback = s:start()
  if change ==# 'line'
    call cursor(1, 4)
  else
    call setline(2, change ==# 'replace' ? 'pro tail' : change ==# 'delete' ? 'pr tail' : 'pri changed tail')
    call cursor(2, change ==# 'delete' ? 3 : 4)
  endif
  call s:success(s:Callback, 'stale')
  call assert_equal([], g:deoplete#source#vim_lsp#_items, change)
  call assert_equal(1, g:deoplete#source#vim_lsp#_done, change)
  call s:recovered()
endfor

" Multiple edits growing a prefix (also multibyte) must not fail a strict tick check.
for prefix in ['pri', 'pré']
  call setline(1, ['header', prefix . ' tail'])
  call cursor(2, strlen(prefix) + 1)
  let s:Callback = s:start()
  for suffix in ['n', 'nt']
    call setline(2, prefix . suffix . ' tail')
    call cursor(2, strlen(prefix . suffix) + 1)
  endfor
  call s:success(s:Callback, 'print')
  call assert_equal('print', g:deoplete#source#vim_lsp#_items[0].word)
endfor

" Bad envelopes must finish immediately, and bad results must remain retryable.
for data in [v:null, [], {}, {'response': v:null}, {'response': []},
      \ {'response': {'result': 42}}, {'response': {'result': 'invalid'}},
      \ {'response': {'result': {'items': {}, 'isIncomplete': v:false}}},
      \ {'response': {'result': {'items': []}}},
      \ {'response': {'result': [{'textEdit': {}}]}},
      \ {'response': {'error': {'code': -32800, 'message': 'cancelled'}}}]
  let s:Callback = s:start()
  let s:threw = ''
  try
    call call(s:Callback, [data])
  catch
    let s:threw = v:exception
  endtry
  call assert_equal('', s:threw, string(data))
  call assert_equal(1, g:deoplete#source#vim_lsp#_done, string(data))
  call assert_equal([], g:deoplete#source#vim_lsp#_items, string(data))
  call assert_equal(1, g:deoplete#source#vim_lsp#_incomplete, string(data))
  call s:recovered()
  call s:success(s:Callback, 'failed_request_replayed')
  call assert_equal('recovered', g:deoplete#source#vim_lsp#_items[0].word)
endfor

" A null result is valid LSP, unlike a malformed result.
let s:Callback = s:start()
call call(s:Callback, [{'response': {'result': v:null}}])
call assert_equal(1, g:deoplete#source#vim_lsp#_done)
call assert_equal([], g:deoplete#source#vim_lsp#_items)
call assert_equal(0, g:deoplete#source#vim_lsp#_incomplete)

" Cancellation invalidates ownership even when no replacement has started yet.
let s:Callback = s:start()
let s:cancelled_id = g:deoplete#source#vim_lsp#_request_id
let g:deoplete#source#vim_lsp#_request_id += 1
call s:success(s:Callback, 'cancelled')
call assert_equal(0, g:deoplete#source#vim_lsp#_done)
call assert_equal([], g:deoplete#source#vim_lsp#_items)
call s:recovered()

" A pending request must not publish into another buffer, even before BufEnter is processed.
let s:Callback = s:start()
noautocmd new
call setline(1, 'pri ')
call cursor(1, 4)
call s:success(s:Callback, 'wrong_buffer')
call assert_equal([], g:deoplete#source#vim_lsp#_items)
call assert_equal(1, g:deoplete#source#vim_lsp#_done)
call s:recovered()

" Fire the timeout immediately before its response, then replay it after a newer request.
let s:Finish = function('<SNR>' . s:script.sid . '_finish_request')
let s:Callback = s:start()
let s:expired_id = g:deoplete#source#vim_lsp#_request_id
call s:Finish(s:expired_id, [], 1)
call s:success(s:Callback, 'late')
call assert_equal([], g:deoplete#source#vim_lsp#_items)
let s:NewCallback = s:start()
let s:timers = map(timer_info(), 'v:val.id')
call s:Finish(s:expired_id, [], 1)
call s:success(s:Callback, 'late')
call assert_equal(0, g:deoplete#source#vim_lsp#_done)
call assert_equal(s:timers, map(timer_info(), 'v:val.id'))
call s:success(s:NewCallback, 'newest')
call assert_equal('newest', g:deoplete#source#vim_lsp#_items[0].word)
call s:Finish(s:expired_id, [], 1)
call assert_equal('newest', g:deoplete#source#vim_lsp#_items[0].word)
call s:recovered()

" Source and callback share one exact snapshot, including after validated growth.
for prefix in ['pri', 'pré']
  call setline(1, ['header', prefix . ' tail'])
  call cursor(2, strlen(prefix) + 1)
  let s:Callback = s:start()
  let s:Captured = get(s:Callback, 'args')[1]
  for suffix in ['n', 'nt']
    call setline(2, prefix . suffix . ' tail')
    call cursor(2, strlen(prefix . suffix) + 1)
    call assert_equal(1, deoplete_vim_lsp#matches_context(bufnr('%'), 2, prefix . suffix))
    call assert_equal(['header', prefix . ' tail'], s:Captured.lines)
    " Repeated polling after growth remains compatible.
    call assert_equal(1, deoplete_vim_lsp#matches_context(bufnr('%'), 2, prefix . suffix))
  endfor
  call s:success(s:Callback, 'print')
  call assert_equal('print', g:deoplete#source#vim_lsp#_items[0].word)
  " Completed results also retain the snapshot and reject a later unrelated edit.
  call assert_equal(1, deoplete_vim_lsp#matches_context(bufnr('%'), 2, prefix . 'nt'))
  call setline(1, 'changed header')
  call assert_equal(0, deoplete_vim_lsp#matches_context(bufnr('%'), 2, prefix . 'nt'))
endfor

" Cursor movement can change the normalized suffix without changing changedtick.
call setline(1, ['header', 'pri tail'])
call cursor(2, 4)
let s:Callback = s:start()
call setline(2, 'printf tail')
call cursor(2, 7)
call assert_equal(1, deoplete_vim_lsp#matches_context(bufnr('%'), 2, 'printf'))
call cursor(2, 5)
call assert_equal(0, deoplete_vim_lsp#matches_context(bufnr('%'), 2, 'prin'))
call s:success(s:Callback, 'stale_cursor')
call assert_equal([], g:deoplete#source#vim_lsp#_items)

" A successful source check cannot hide subsequent stale edits from the callback.
for change in ['header', 'tail', 'line_count']
  call setline(1, ['header', 'pri tail'])
  call cursor(2, 4)
  let s:Callback = s:start()
  call setline(2, 'prin tail')
  call cursor(2, 5)
  call assert_equal(1, deoplete_vim_lsp#matches_context(bufnr('%'), 2, 'prin'))
  if change ==# 'header'
    call setline(1, 'changed header')
  elseif change ==# 'tail'
    call setline(2, 'prin changed tail')
  else
    call append(2, 'added line')
  endif
  call assert_equal(0, deoplete_vim_lsp#matches_context(bufnr('%'), 2, 'prin'))
  call s:success(s:Callback, 'stale')
  call assert_equal([], g:deoplete#source#vim_lsp#_items)
  call s:recovered()
endfor

" Old transport closures keep their ownership metadata but release buffer contents.
let s:Callback = s:start()
let s:Captured = get(s:Callback, 'args')[1]
call assert_false(empty(s:Captured.lines))
let s:NewCallback = s:start()
call assert_equal([], s:Captured.lines)
call s:success(s:Callback, 'old')
call assert_equal(0, g:deoplete#source#vim_lsp#_done)
call s:success(s:NewCallback, 'new')
call assert_equal('new', g:deoplete#source#vim_lsp#_items[0].word)
let s:Captured = get(s:NewCallback, 'args')[1]
let g:deoplete#source#vim_lsp#_request_id += 1
call deoplete_vim_lsp#clear()
call assert_equal([], s:Captured.lines)
call assert_equal(0, deoplete_vim_lsp#matches_context(bufnr('%'), line('.'), 'prin'))
call s:success(s:NewCallback, 'cleared')
call assert_equal('new', g:deoplete#source#vim_lsp#_items[0].word)

if !empty(v:errors)
  call writefile(v:errors, $LAB . '/bridge-errors.txt')
  cquit
endif
qa!
