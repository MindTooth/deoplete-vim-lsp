function! BenchPrimitive(kind, samples) abort
  let saved = getline(1, '$')
  let other = getline(1, '$')
  let times = []
  for i in range(a:samples + 4)
    let start = reltime()
    if a:kind ==# 'capture_getline'
      let value = getline(1, '$')
    elseif a:kind ==# 'capture_getbufline'
      let value = getbufline(bufnr('%'), 1, '$')
    elseif a:kind ==# 'compare'
      let value = saved ==# other
    else
      let value = getline(1, '$')
      let value[line('.') - 1] = 'pri' . strpart(getline('.'), col('.') - 1)
      let value = value ==# saved
    endif
    let elapsed = reltimefloat(reltime(start))
    if i >= 5
      call add(times, elapsed)
    endif
    unlet value
  endfor
  return times
endfunction

" Also runnable in native Vim: OUT=/tmp/primitives.json vim -Nu NONE -i NONE -n -es -S benchmarks/primitives.vim
if !empty($OUT)
  let results = {'editor': execute('version'), 'buffers': []}
  for buffer_lines in [100, 10000, 100000]
    %delete _
    call setline(1, map(range(buffer_lines), {_, i -> printf('    "key_%06d": "', i) . repeat('x', 60) . '",'}))
    call setline(buffer_lines / 2 + 1, 'pri tail')
    call cursor(buffer_lines / 2 + 1, 4)
    let row = {'lines': buffer_lines}
    for kind in ['capture_getline', 'capture_getbufline', 'compare', 'capture_compare']
      let row[kind] = BenchPrimitive(kind, 100)
    endfor
    call add(results.buffers, row)
  endfor
  call writefile([json_encode(results)], $OUT)
  qa!
endif
