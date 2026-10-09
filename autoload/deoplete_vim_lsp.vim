function! deoplete_vim_lsp#log(...) abort
    if !empty(g:deoplete#sources#vim_lsp#log)
        call writefile([strftime('%c') . ':' . json_encode(a:000)], g:deoplete#sources#vim_lsp#log, 'a')
    endif
endfunction

let s:timer = -1

function! deoplete_vim_lsp#request(server_name, complete_position, request_id) abort
    let l:server = lsp#get_server_info(a:server_name)
    let l:request = {
        \ 'id': a:request_id,
        \ 'bufnr': bufnr('%'),
        \ 'position': lsp#get_position(),
        \ 'complete_position': a:complete_position,
        \ 'input': strpart(getline('.'), 0, col('.') - 1),
        \ }
    call timer_stop(s:timer)
    let s:timer = timer_start(1000, function('s:finish_request', [a:request_id, [], 1]))
    call lsp#send_request(a:server_name, {
        \ 'method': 'textDocument/completion',
        \ 'params': {
        \   'textDocument': lsp#get_text_document_identifier(),
        \   'position': l:request.position,
        \ },
        \ 'on_notification': function('s:handle_completion', [l:server, l:request]),
        \ })
endfunction

function! s:finish_request(request_id, items, incomplete, ...) abort
    if a:request_id != g:deoplete#source#vim_lsp#_request_id
        return
    endif
    call timer_stop(s:timer)
    let g:deoplete#source#vim_lsp#_items = a:items
    let g:deoplete#source#vim_lsp#_incomplete = a:incomplete
    let g:deoplete#source#vim_lsp#_done = 1
    " Invalidate this request so a response after timeout cannot revive it.
    let g:deoplete#source#vim_lsp#_request_id += 1
    if index(['i', 'ic', 'ix'], mode()) >= 0
        call deoplete#auto_complete()
    endif
endfunction

function! s:handle_completion(server, request, data) abort
    if a:request.id != g:deoplete#source#vim_lsp#_request_id
        return
    endif
    if a:request.bufnr != bufnr('%') || a:request.position.line != line('.') - 1
        \ || stridx(strpart(getline('.'), 0, col('.') - 1), a:request.input) != 0
        \ || lsp#client#is_error(a:data) || !has_key(a:data, 'response')
        \ || !has_key(a:data.response, 'result')
        call s:finish_request(a:request.id, [], 1)
        return
    endif

    try
        let l:options = {
            \ 'server': a:server,
            \ 'position': a:request.position,
            \ 'response': a:data['response'],
            \ }
        let l:completion = lsp#omni#get_vim_completion_items(l:options)
        " Only remove leading text that Deoplete already keeps before its keyword start.
        let l:offset = max([0, a:request.complete_position - (l:completion['startcol'] - 1)])
        let l:prefix = strpart(getline('.'), l:completion['startcol'] - 1, l:offset)
        let l:items = map(l:completion['items'], 'extend(v:val, {"word": stridx(v:val.word, l:prefix) == 0 ? strpart(v:val.word, l:offset) : v:val.word})')
        call s:finish_request(a:request.id, l:items, l:completion['incomplete'])
    catch
        call s:finish_request(a:request.id, [], 1)
        call deoplete_vim_lsp#log('handle error', v:exception, v:throwpoint)
    endtry
endfunction
