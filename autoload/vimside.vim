" ============================================================================
" vimside.vim
"
" File:          vimside.vim
" Summary:       VimSIde top level file
" Author:        Richard Emberson <richard.n.embersonATgmailDOTcom>
" Last Modified: 2012
" Version:       0.2
" Modifications:
"
" Tested on vim 7.3 on Linux
"
" Depends upon: NONE
"
" ============================================================================
" Intro: {{{1
" ============================================================================


function! vimside#version()
  return '0.2'
endfunction

let s:LOG = function("vimside#log#log")
let s:ERROR = function("vimside#log#error")

let g:vimside = {} 
let g:vimside.started = 0
let g:vimside.errors = []
let g:vimside.warns = []

let g:vimside.ensime = {} 
let g:vimside.ensime.info = {} 

" actions to be invoked on next ping (then cleared from list)
let g:vimside.ping = {}
" XXXXXXXXXXXXX
" let g:vimside.ping.actions = []
let g:vimside.ping.info = {}
let g:vimside.ping.info.read_timeout = 0
let g:vimside.ping.info.updatetime = 500
let g:vimside.ping.info.char_count = 10

" will hold
"   info
"   scala_notes
"   java_notes
let g:vimside.project = {} 
" will hold
"   name
"   source_roots
let g:vimside.project.info = {} 
" will hold
let g:vimside.project.scala_notes = []
let g:vimside.project.java_notes = []
" [bufnum, [0, lnum, col, offset]]
let g:vimside.project.positions = []


" waiting for a response
" ping-info: expecting/not-expecting rpc and/or event
let g:vimside.swank = {} 
let g:vimside.swank.rpc = {} 
" waiting = { id: rr }
let g:vimside.swank.rpc.waiting = {} 
let g:vimside.swank.events = '0'


" how often each event has been recieved
let g:vimside.status = {} 
" default handlers are in autoload/swank/rpc/
let g:vimside.event_handlers = {} 
let g:vimside.debug_event_handlers = {} 
let g:vimside.event_trigger = {} 
let g:vimside.debug_trigger = {} 


function! g:ResponsePending()
  return ! empty(g:vimside.rpc.waiting)
endfunction
let g:vimside.ResponsePending = function('g:ResponsePending')

function! g:CompilerReady()
  " defined in vimside/ensime/swank
  return g:vimside.status.compiler_ready
endfunction
let g:vimside.CompilerReady = function('g:CompilerReady')

function! g:IndexerReady()
  " defined in vimside/ensime/swank
  return g:vimside.status.indexer_ready
endfunction
let g:vimside.IndexerReady = function('g:IndexerReady')





function! vimside#StartEnsime()
  if ! g:vimside.started 
    " let msg = "Starting Ensime Engine ..."
    " call vimside#cmdline#Display(msg)


    " Ok, are all of the plugins we need avaiable
    call vimside#plugins#Check()

    if len(g:vimside.errors) != 0
      throw "Plugin Error: ". string(g:vimside.errors)
    endif

    " Next, load options
    call vimside#options#manager#Load()

    if len(g:vimside.errors) != 0
      throw "Option Load Errors: ". string(g:vimside.errors)
    endif


    " Next, load event handlers
    call vimside#ensime#swank#load_handlers()

    if len(g:vimside.errors) != 0
      throw "Load Handlers Errors: ". string(g:vimside.errors)
    endif

    " Now, load rpc and event ping info
    call vimside#ensime#swank#load_ping_info()

    if len(g:vimside.errors) != 0
      throw "Load Ping Info Errors: ". string(g:vimside.errors)
    endif

    call vimside#StartEnsimeServer()
    let g:vimside.started = 1

sleep 4

    call vimside#GetPortEnsime()

    let l:name = "ping_ensime_server"
    let l:Func = function("vimside#PingEnsimeServer")
    let l:sec = 1
    let l:msec = 0
    let l:charcnt = 200
    let l:repeat = 1
    call vimside#scheduler#AddJob(l:name, l:Func, l:sec, l:msec, l:charcnt, l:repeat)

sleep 2
call s:LOG("vimside#StartEnsime get connection") 
    let g:vimside['socket'] = vimside#GetConnectionSocketEnsime()

call s:LOG("vimside#StartEnsime call vimside#swank#rpc#connection_info#Run") 
    call vimside#swank#rpc#connection_info#Run()
call s:LOG("vimside#StartEnsime call vimside#swank#rpc#init_project#Run") 
    call vimside#swank#rpc#init_project#Run()
  else
    let msg = "Ensime Engine Already Running ..."
    call vimside#cmdline#Display(msg)
  endif
endfunction


function! vimside#StopEnsime()
  if g:vimside.started
" XXXXXXXXXXXXX
    " call vimside#RemoveAutoCmds()
    vimside#scheduler#ClearAuto()
    call vimside#swank#rpc#shutdown_server#Run()

    call vimside#ensime#io#close()
    let g:vimside.started = 0
  endif
endfunction

function! vimside#StartEnsimeServer()
  let [found, portfile] = g:vimside.GetOption('ensime-port-file-path')
  if ! found
    echoerr "Vimside: Option not found: "'ensime-port-file-path'"
  endif

call s:LOG("vimside#StartEnsimeServer portfile=" . portfile) 
  let [found, dpath] = g:vimside.GetOption('ensime-dist-path')
  if ! found
    echoerr "Vimside: Option not found: "'ensime-dist-path'"
  endif

  let cmd = 'cd ' . dpath . ' && ./bin/server ' . shellescape(portfile)

  let [s:found, l:log_enabled] = g:vimside.GetOption('ensime-log-enabled')
  if ! s:found
    echoerr "Vimside: Option not found: "'ensime-log-enabled'"
  endif

" echo "StartEnsimeServer: log_enabled=" . l:log_enabled
  if l:log_enabled
    let lines = [
      \ "##################################################################",
      \ "Title: Ensime Server log file",
      \ "Date: " . strftime("%Y%m%d %T"),
      \ "##################################################################"
      \ ]

    let [found, l:logfile] = g:vimside.GetOption('ensime-log-file-path')
    if ! found
      echoerr "Vimside: Option not found: "'ensime-log-file-path'"
    endif

    call writefile(lines, l:logfile)

    execute "silent !" . cmd . " &>> " . l:logfile . " &"

  else
    if has('win16') || has('win32') || has('win64')
      " Note: do not know if this is correct
      let l:logfile = "NUL"
    else
      let l:logfile = "/dev/null"
    endif

    execute "silent !" . cmd . " &> " . l:logfile . " &"
  endif

endfunction

function! vimside#GetPortEnsime()
call s:LOG("vimside#GetPortEnsime TOP") 
  let [found, portfile] = g:vimside.GetOption('ensime-port-file-path')
  if ! found
    echoerr "Vimside: Option not found: "'ensime-port-file-path'"
  endif

  " wait for port file to be created and written to
  let cnt = 0
  let [found, max_cnt] = g:vimside.GetOption('ensime-port-file-max-wait')
  if ! found
    echoerr "Vimside: Option not found: "'ensime-port-file-max-wait'"
  endif

call s:LOG("vimside#GetPortEnsime max_cnt=" . max_cnt) 
  while ! filereadable(portfile) && cnt < max_cnt
    sleep 1
    let cnt += 1
  endwhile

  if ! filereadable(portfile)
    echoerr "Vimside Failed to start Ensime Server port file does not exists"
  endif

  let portfile_lines = readfile(portfile)
  if len(portfile_lines) != 1
    echoerr "Vimside Ensime Server port file not single line: " . string(portfile_lines)
  endif

  let portstr = portfile_lines[0]
  let port = 0 + portstr
  call g:vimside.SetOption('ensime_port_number', port)
call s:LOG("vimside#GetPortEnsime BOTTOM") 
endfunction

function! vimside#GetConnectionSocketEnsime()
call s:LOG("vimside#GetConnectionSocketEnsime TOP") 

  let [found, port] = g:vimside.GetOption('ensime_port_number')
  if ! found
    echoerr "Vimside: Option not found: "'ensime_port_number'"
  endif

  let [found, host] = g:vimside.GetOption('ensime-host-name')
  if ! found
    echoerr "Vimside: Option not found: "'ensime-host-name'"
  endif

call s:LOG("host:port=" . host .":". port) 

  let l:socket = vimside#ensime#io#open(host, port)
call s:LOG("socket=" . string(l:socket)) 
  return l:socket
endfunction

" ============================================================================
" Ping
" ============================================================================

function! vimside#PingEnsimeServer()
call s:LOG("vimside#PingEnsimeServer") 
  let timeout = g:vimside.ping.info.read_timeout
  let success = vimside#ensime#io#ping(timeout)
  while success
    let success = vimside#ensime#io#ping(timeout)
  endwhile
endfunction

if 0 " XXXXXXXXXXXXX

function! vimside#SetAutoCmds()
call s:LOG("vimside#SetAutoCmds TOP") 
  let s:ping_info_updatetime = g:vimside.ping.info.updatetime
  let &updatetime = s:ping_info_updatetime
  let s:max_ping_info_char_count = g:vimside.ping.info.char_count
  let s:ping_info_char_count = s:max_ping_info_char_count

  augroup VIMSIDE_CMD
    autocmd!
    autocmd CursorHold * call vimside#CursorHoldReadFromEnsimeServer()
    autocmd CursorHoldI * call vimside#CursorHoldReadFromEnsimeServer()
    autocmd CursorMoved * call vimside#CursorMoveReadFromEnsimeServer()
    autocmd CursorMovedI * call vimside#CursorMoveReadFromEnsimeServer()
  augroup END
endfunction

function! vimside#RemoveAutoCmds()
  augroup VIMSIDE_CMD
    autocmd!
  augroup END
endfunction

function! vimside#ResetAutoCmds()
  call vimside#RemoveAutoCmds()
  call vimside#SetAutoCmds()
endfunction


" let s:max_read_from_ensime_server = 10

"
"  updatetime option
"    sync command 
"      startup
"        shorten time (startup_time) lengthen after (startup_cnt)
"      normal
"        shorten time (normal_time) lengthen after (normal_cnt)
"  call feedkeys("f\e") 
"
function! vimside#CursorHoldReadFromEnsimeServer()
call s:LOG("CursorHoldReadFromEnsimeServer TOP ") 

  if s:ping_info_updatetime != g:vimside.ping.info.updatetime
call s:LOG("CursorHoldReadFromEnsimeServer from(". s:ping_info_updatetime. ")to(". g:vimside.ping.info.updatetime .")") 
    let s:ping_info_updatetime = g:vimside.ping.info.updatetime
    let &updatetime = s:ping_info_updatetime
  endif

  let timeout = g:vimside.ping.info.read_timeout
  let success = vimside#ensime#io#ping(timeout)
  while success
    let success = vimside#ensime#io#ping(timeout)
  endwhile

" call s:LOG("CursorHoldReadFromEnsimeServer feedkeys: updatetime=". &updatetime) 
  " call feedkeys("f\e", 'n') 
  " call feedkeys(a:keys, 'n') 
  if mode() == 'i'
    call feedkeys("a\<BS>", 'n')
  else
    call feedkeys("f\e", 'n')
  endif

endfunction

function! vimside#CursorMoveReadFromEnsimeServer()
" call s:LOG("CursorMoveReadFromEnsimeServer TOP") 
  if s:max_ping_info_char_count != g:vimside.ping.info.char_count
call s:LOG("CursorMoveReadFromEnsimeServer from(". s:max_ping_info_char_count . ")to(". g:vimside.ping.info.char_count .")") 
    let s:max_ping_info_char_count = g:vimside.ping.info.char_count
    let s:ping_info_char_count = s:max_ping_info_char_count
  endif

  if s:ping_info_char_count <= 0
    let timeout = 0
    let success = vimside#ensime#io#ping(timeout)
    while success
      let success = vimside#ensime#io#ping(timeout)
    endwhile

    let s:ping_info_char_count = s:max_ping_info_char_count
  else
    let s:ping_info_char_count -= 1
  endif
endfunction

endif " XXXXXXXXXXXXX

" ============================================================================
" Position Code
" ============================================================================
function!  vimside#ClearPosition()
  let g:vimside.project.positions = []
endfunction

function!  vimside#SetPosition()
  let bufnum = bufnr("%")
  let pos = getpos(".")
  let g:vimside.project.positions = [bufnum, pos]
endfunction

function!  vimside#PreviousPosition()
  let positions = g:vimside.project.positions
call s:LOG("vimside#PreviousPosition positions=". string(positions)) 
  let len = len(positions)
  if len > 0
    let [bufnum, pos] = positions

    call vimside#SetPosition()

    execute "buffer ". bufnum
    call setpos('.', pos)
  endif
endfunction

" ============================================================================
" Completion code
" ============================================================================
"
" 1) get completions
"   GetCompletions
" 2) display completions
"   DisplayCompletions
"
"

let s:completions_phase = 0
let g:completions_in_process = 0
let s:completions_start = 0
let g:completions_base = ''
let g:completions_results = []

function!  vimside#Completions(findstart, base)
call s:LOG("vimside#Completions findstart=". a:findstart .", base=". a:base) 
  if ! g:vimside.started
    return
  endif
call s:LOG("vimside#Completions completions_phase=". s:completions_phase) 

  if s:completions_phase == 0
    " Get Completions
    if a:findstart 
      let g:completions_in_process = 1
      w
      let line = getline('.')
      let pos = col('.') -1
      let bc = strpart(line,0,pos)
      let match_text = matchstr(bc, '\zs[^ \t#().[\]{}\''\";: ]*$')
call s:LOG("vimside#Completions match_text=". match_text) 
      let s:completions_start = len(bc)-len(match_text)
call s:LOG("vimside#Completions completions_start=". s:completions_start) 
      call vimside#StartAutoCmdCompletions()
      return s:completions_start 
    elseif ! g:completions_in_process
      return []
    else
      if len(a:base) > 0
        let g:completions_base = a:base
        let g:completions_results = []
        call vimside#swank#rpc#completions#Run()
        let s:completions_phase = 1
      else
        let s:completions_phase = 0
      endif
call s:LOG("vimside#Completions return []")
      return []
    endif
  elseif ! g:completions_in_process
    if a:findstart 
      return ''
    else
      return []
    endif
  else
    " Display Completions
    if a:findstart 
call s:LOG("vimside#Completions completions_start=". s:completions_start) 
      return s:completions_start
    else
      let s:completions_phase = 0
      let g:completions_base = ''
call s:LOG("vimside#Completions g:completions_results=". string(g:completions_results))
      let g:completions_in_process = 0
      call vimside#StopAutoCmdCompletions()
      return g:completions_results
    endif

  endif
endfunction

function!  vimside#AbortCompletions()
call s:LOG("vimside#AbortCompletions") 
  if pumvisible() == 0
    let s:completions_phase = 0
    let g:completions_in_process = 0
    call vimside#StopAutoCmdCompletions()
  endif
endfunction

function!  vimside#StartAutoCmdCompletions()
  augroup VIMSIDE_COMPLETIONS
    au!
    autocmd CursorMovedI,InsertLeave *.scala call vimside#AbortCompletions()
  augroup end
endfunction
function!  vimside#StopAutoCmdCompletions()
  augroup VIMSIDE_COMPLETIONS
    au!
  augroup END
endfunction

" ============================================================================
" Hover to Symbol code
" ============================================================================

let s:hover_save_updatetime = 0
let s:hover_updatetime = 600
let s:hover_time_name = 'hover_time_job'

let s:hover_save_max_mcounter = 0
let s:hover_max_mcounter = 0
let s:hover_motion_name = 'hover_motion_job'

let s:hover_start = 0
" let s:Hover_Stop = function("s:StopHoverToSymbol")

function! vimside#HoverToSymbol()
call s:LOG("vimside#HoverToSymbol") 
  if s:hover_start
    " call s:StopHoverToSymbol()
    call s:Hover_Stop()
  else
    if s:DoBalloon() && s:IsBalloonSupported()
call s:LOG("vimside#HoverToSymbol: DO BALLOON") 
      let s:Hover_Stop = function("s:StopBalloonHoverToSymbol")
      call s:StartBalloonHoverToSymbol()
    else
call s:LOG("vimside#HoverToSymbol: NO BALLOON") 
      let s:Hover_Stop = function("s:StopHoverToSymbol")
      call s:StartHoverToSymbol()
    endif
  endif
endfunction


function! g:HoverHandler_Ok(symbolinfo)
" call s:LOG("g:HoverHandler_Ok ". string(a:symbolinfo)) 
  let [found, dic] = vimside#sexp#Convert_KeywordValueList2Dictionary(a:symbolinfo)
  if ! found
    echoe "SymbolAtPoint ok: Badly formed Response"
    call s:ERROR("SymbolAtPoint ok: Badly formed Response: ". string(a:symbolinfo))
    return 0
  endif

" (:return 
" (:ok 
" (:name "bar_object1" 
" :type (:name "Bar" :type-id 1 :full-name "com.megaanum.Bar" :decl-as class :pos (:file "/home/emberson/.vim/data/vimside/src/main/scala/com/megaanum/Bar.scala" :offset 214)) 
" :decl-pos (:file "/home/emberson/.vim/data/vimside/src/main/scala/com/megaanum/Foo.scala" :offset 168) :owner-type-id 2)
" ) 3)
" 
" 
" (:return 
" (:ok 
" (:name "println" 
" :type (:name "(x: Any)Unit" :type-id 7 :arrow-type t :result-type 
" (:name "Unit" :type-id 8 :full-name "scala.Unit" :decl-as class) 
" :param-sections (
" (:params (("x" (:name "Any" :type-id 6 :full-name "scala.Any" :decl-as class))))
" )
" )
" :decl-pos (:file "/home/emberson/scala/scala-2.10.0-M7/src/library/scala/Predef.scala" :offset 13271) 
" :is-callable t 
" :owner-type-id 9)) 71)
"
" (:return 
" (:ok 
" (:name "getBar" 
" :type (:name "Bar" :type-id 5 :full-name "com.megaanum.Bar" :decl-as class :pos (:file "/home/emberson/.vim/data/vimside/src/main/scala/com/megaanum/Bar.scala" :offset 214)) 
" :decl-pos (:file "/home/emberson/.vim/data/vimside/src/main/scala/com/megaanum/Foo.scala" :offset 237) :owner-type-id 6)) 5)
" 

  echo ""
  if vimside#util#IsDictionary(dic)
    if has_key(dic, ":type")
      let tdic = dic[':type']
      if has_key(tdic, ":arrow-type") && tdic[':arrow-type'] 
        let name = dic[':name']
        let tname = tdic[':name']
          echo name . tname
      else
        if has_key(tdic, ":full-name")
          let value = tdic[':full-name']
          if value != "<none>.<none>"
            echo value
          endif
        endif
      endif
    endif
  endif

  call vimside#scheduler#SetUpdateTime(s:hover_save_updatetime)
  call vimside#scheduler#SetMaxMotionCounter(s:hover_max_mcounter)

  call vimside#scheduler#RemoveJob(s:hover_motion_name)
  let FuncMotion = function("g:JobMotionHoverToSymbol")
  let charcnt = 0
  let repeat = 0
  call vimside#scheduler#AddMotionJob(s:hover_motion_name, FuncMotion, charcnt, repeat)

  return 1
endfunction

function! g:JobTimeHoverToSymbol()
  let dic = {
        \ 'handler': {
        \ 'ok': function("g:HoverHandler_Ok")
        \ }
        \ }
  call vimside#swank#rpc#symbol_at_point#Run(dic)
endfunction

function! g:JobMotionHoverToSymbol()
  call vimside#scheduler#SetMaxMotionCounter(s:hover_save_max_mcounter)
  call vimside#scheduler#SetUpdateTime(s:hover_updatetime)

  call vimside#scheduler#RemoveJob(s:hover_time_name)
  let Func = function("g:JobTimeHoverToSymbol")
  let sec = 0
  let msec = 300
  let repeat = 0
  call vimside#scheduler#AddTimeJob(s:hover_time_name, Func, sec, msec, repeat)
endfunction

function! s:StartHoverToSymbol()
  " save currnet time/motion settings
  let s:hover_save_updatetime = vimside#scheduler#GetUpdateTime()
  let s:hover_save_max_mcounter = vimside#scheduler#GetMaxMotionCounter()

  call vimside#scheduler#SetUpdateTime(s:hover_updatetime)

  let FuncTime = function("g:JobTimeHoverToSymbol")
  let sec = 0
  let msec = 300
  let repeat = 0
  call vimside#scheduler#AddTimeJob(s:hover_time_name, FuncTime, sec, msec, repeat)

  let s:hover_start = 1
endfunction

function! s:StopHoverToSymbol()
  call vimside#scheduler#RemoveJob(s:hover_motion_name)
  call vimside#scheduler#RemoveJob(s:hover_time_name)
  
  call vimside#scheduler#SetUpdateTime(s:hover_save_updatetime)
  call vimside#scheduler#SetMaxMotionCounter(s:hover_save_max_mcounter)

  let s:hover_start = 0
endfunction

" ---------------------
" Hover Balloon code
" ---------------------

function! s:DoBalloon()
  " TODO make option
  return 1
endfunction

function! s:IsBalloonSupported()
  if has("balloon_eval")
    return 1
  else
    " NOTE: for now console is not supported
    return 0
  endif
endfunction

function! s:GetCurrentBalloonOffset()
  return line2byte(v:beval_lnum)+v:beval_col-1
endfunction

function! s:StopBalloonHoverToSymbol()
  let &ballooneval = 0
  let s:hover_start = 0
endfunction

function! s:StartBalloonHoverToSymbol()
" call s:LOG("s:StartBalloonHoverToSymbol") 
  set bexpr=g:HoverBalloonExpr()
  let &ballooneval = 1
  let s:hover_start = 1
endfunction

let s:hover_balloon_value = ''

function! g:HoverBalloonHandler_Ok(symbolinfo)
" call s:LOG("g:HoverBalloonHandler_Ok ". string(a:symbolinfo)) 
  let [found, dic] = vimside#sexp#Convert_KeywordValueList2Dictionary(a:symbolinfo)
  if ! found
    echoe "SymbolAtPoint ok: Badly formed Response"
    call s:ERROR("SymbolAtPoint ok: Badly formed Response: ". string(a:symbolinfo))
    return 0
  endif

  let s:hover_balloon_value = ''
  if vimside#util#IsDictionary(dic)
    if has_key(dic, ":type")
      let tdic = dic[':type']
      if has_key(tdic, ":arrow-type") && tdic[':arrow-type'] 
        let name = dic[':name']
        let tname = tdic[':name']
          let s:hover_balloon_value = name . tname
      else
        if has_key(tdic, ":full-name")
          let value = tdic[':full-name']
          if value != "<none>.<none>"
            let s:hover_balloon_value = value
          endif
        endif
      endif
    endif
  endif

  return 1
endfunction



function! g:HoverBalloonExpr()
" call s:LOG("g:HoverBalloonExpr") 
  " return "HoverBalloon: offset=". s:GetCurrentBalloonOffset()
  
  let dic = {
        \ 'handler': {
        \   'ok': function("g:HoverBalloonHandler_Ok")
        \ },
        \ 'args': {
        \   'offset': s:GetCurrentBalloonOffset()
        \ }
        \ }
  call vimside#swank#rpc#symbol_at_point#Run(dic)

  return s:hover_balloon_value
endfunction

