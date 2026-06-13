" ============================================================================
" Vundle initialization
" Avoid modify this section, unless you are very sure of what you are doing

" no vi-compatible
set nocompatible

" Setting up Vundle - the vim plugin bundler
let s:vundle_autoload=expand('~/.vim/bundle/vundle/autoload/vundle.vim')
if filereadable(s:vundle_autoload)
    filetype off

    set rtp+=~/.vim/bundle/vundle/
    call vundle#rc()

    " let Vundle manage Vundle
    Bundle 'VundleVim/Vundle.vim'

    " ============================================================================
    " Active plugins
    " You can disable or add new ones here:

    " Better file browser
    Bundle 'scrooloose/nerdtree'
    " Vim NERDTree Tabs
    Bundle 'jistr/vim-nerdtree-tabs'
    " Code commenter
    Bundle 'scrooloose/nerdcommenter'
    " Code and files fuzzy finder
    Bundle 'ctrlpvim/ctrlp.vim'
    " Git integration
    Bundle 'tpope/vim-fugitive'
    " A Vim plugin which shows a git diff in the gutter (sign column)
    Bundle 'airblade/vim-gitgutter'
    " Airline
    Bundle 'vim-airline/vim-airline'
    " Airline Themes
    Bundle 'vim-airline/vim-airline-themes'
    " Terminal Vim with 256 colors colorscheme
    Bundle 'fisadev/fisa-vim-colorscheme'
    " Surround
    Bundle 'tpope/vim-surround'
    " auto-pairs
    Bundle 'jiangmiao/auto-pairs'
    " highlight intendation
    Bundle 'nathanaelkane/vim-indent-guides'
    " Window chooser
    Bundle 't9md/vim-choosewin'
    " zoom panes
    Bundle 'regedarek/ZoomWin'
    " python virtualenv integration
    Bundle 'jmcantrell/vim-virtualenv'
    " Search results counter
    Bundle 'IndexedSearch'
    " XML/HTML tags navigation
    Bundle 'matchit.zip'
    " Yank history navigation
    Bundle 'YankRing.vim'
endif

" ============================================================================

" Vim settings and mappings
" You can edit them as you wish

" allow plugins by file type (required for plugins!)
filetype plugin on
filetype indent on

" tabs and spaces handling
set expandtab
set tabstop=4
set softtabstop=4
set shiftwidth=4

" always show status bar
set ls=2

" incremental search
set incsearch

" highlighted search results
set hlsearch

" syntax highlight on
syntax on

" show line numbers
set nu

" enable mouse scrolling
set mouse=a

" disable line break
set nowrap

" set Leader Key
let mapleader=","

" set timeout for waiting on commands like <Leader>...
set timeout
set timeoutlen=1000

" allow backspace in insert mode
:set backspace=indent,eol,start

" faster safe and close shortcuts
map <Leader>s <Esc>:w<CR>
inoremap <Leader>s <Esc>:w<CR>a
map <Leader>S <Esc>:w !sudo tee %<CR>
inoremap <Leader>S <Esc>:w !sudo tee %<CR>a
map <Leader>q <Esc>:q<CR>
map <Leader>Q <Esc>:q!<CR>
map <Leader>a <Esc>:qa<CR>
map <Leader>A <Esc>:qa!<CR>
map <Leader>x <Esc>:x<CR>
map <Leader>X <Esc>:x!<CR>
inoremap <Leader>x <Esc>:x<CR>

" clipboard management
function Paste_from_clipboard()
    set paste
    normal! "+p
    startinsert
    stopinsert
    set nopaste
endfunction

autocmd InsertLeave * set nopaste

vnoremap <Leader>y "+y
map <Leader>p :call Paste_from_clipboard()<CR>


" buffer next/prev
map <C-l> :bn<CR>
map <C-h> :bp<CR>
" close buffer
map <Leader>d :bd<CR>

"windows
map <Leader>- :split<CR>
map <Leader>\ :vsplit<CR>

" window and buffer management
map <Leader>c <Esc>:hide<CR>

" navigate windows with leader + (h,j,k,l)
map <Leader>h <C-w>h
map <Leader>j <C-w>j
map <Leader>k <C-w>k
map <Leader>l <C-w>l

" reorder windows with leader + (H,J,K,L)
map <Leader>H <C-w>H
map <Leader>J <C-w>J
map <Leader>K <C-w>K
map <Leader>L <C-w>L

" toggle zoom window with leader + o
map <Leader>o <C-w>o

" don't use ESC anymore
inoremap jj <Esc>l

" make < > shifts keep selection
vnoremap < <gv
vnoremap > >gv

" toggle NERDTree - default open NT is caused by vim-nerdtree-tabs
map <Leader>n <plug>NERDTreeTabsToggle<CR>

" This unsets the 'last search pattern' register by hitting return
nnoremap <Space> :noh<CR>

" leave visual mode by hitting the space key
vnoremap <Space> <ESC>

" set highlighted cursorline
set cursorline
hi CursorLine ctermbg=235

" swap v and Ctrl-v, because block mode is more useful than visual mode
nnoremap    v   <C-V>
nnoremap <C-V>     v

vnoremap    v   <C-V>
vnoremap <C-V>     v

" move lines up and down with shift and arrow keys
nnoremap <S-Up> mz:m .-2<CR>`z
nnoremap <S-Down> mz:m .+1<CR>`z
inoremap <S-Up> <Esc>:m .-2<CR>==gi
inoremap <S-Down> <Esc>:m .+1<CR>==gi
vnoremap <S-Up> :m '<-2<CR>gv=gv
vnoremap <S-Down> :m '>+1<CR>gv=gv

" intendation colors
colorscheme default
let g:indent_guides_enable_on_vim_startup = 1 
let g:indent_guides_auto_colors = 0
let g:indent_guides_guide_size = 1
let g:indent_guides_start_level = 2
autocmd VimEnter,Colorscheme * :hi IndentGuidesOdd  ctermbg=236
autocmd VimEnter,Colorscheme * :hi IndentGuidesEven ctermbg=236


" use 256 colors when possible
if &term =~? 'mlterm\|xterm\|xterm-256\|screen-256'
	let &t_Co = 256
    colorscheme fisa
else
    colorscheme delek
endif

" colors for gvim
if has('gui_running')
    colorscheme wombat
endif

" when scrolling, keep cursor 8 lines away from screen border
set scrolloff=8

" autocompletion of files and commands behaves like shell
" (complete only the common part, list the options that match)
set wildmode=list:longest

" better backup, swap and undos storage
set directory=~/.vim/dirs/tmp     " directory to place swap files in
set backup                        " make backup files
set backupdir=~/.vim/dirs/backups " where to put backup files
if has('persistent_undo')
    set undofile                  " persistent undos - undo after you re-open the file
    set undodir=~/.vim/dirs/undos
    if !isdirectory(&undodir)
        call mkdir(&undodir, "p")
    endif
endif
set viminfo+=n~/.vim/dirs/viminfo
" store yankring history file there too
let g:yankring_history_dir = '~/.vim/dirs'

" create needed directories if they don't exist
if !isdirectory(&backupdir)
    call mkdir(&backupdir, "p")
endif
if !isdirectory(&directory)
    call mkdir(&directory, "p")
endif

" ============================================================================
" Plugins settings and mappings
" Edit them as you wish.

" Tagbar ----------------------------- 

" toggle tagbar display
map <F4> :TagbarToggle<CR>
" autofocus on tagbar open
let g:tagbar_autofocus = 1

" NERDTree ----------------------------- 

" open nerdtree with the current file selected
nmap <Leader>t :NERDTreeFind<CR>
" don't show these file types
let NERDTreeIgnore = ['\.pyc$', '\.pyo$']


" CtrlP ------------------------------

" file finder mapping
let g:ctrlp_map = '<c-p>'
let g:ctrlp_cmd = 'CtrlP'
" don't change working directory
let g:ctrlp_working_path_mode = 0
" ignore these files and folders on file finder
let g:ctrlp_custom_ignore = {
  \ 'dir':  '\v[\/](\.git|\.hg|\.svn)$',
  \ 'file': '\.pyc$\|\.pyo$',
  \ }
" show hidden files
let g:ctrlp_show_hidden = 1
" include extensions
let g:ctrlp_extensions = ['cmdpalette']
" remap keys
let g:ctrlp_prompt_mappings = {
  \ 'ToggleType(1)':        ['<c-l>', '<c-up>'],
  \ 'PrtCurRight()':        ['<c-f>', '<right>'],
  \ }
" execute command immediately
let g:ctrlp_cmdpalette_execute = 1

" Plugins from github repos:
" tags (symbols) in current file finder mapping
nmap <Leader>g :CtrlPBufTag<CR>
" tags (symbols) in all files finder mapping
nmap <Leader>G :CtrlPBufTagAll<CR>
" general code finder in all files mapping
nmap <Leader>f :CtrlPLine<CR>
" recent files finder mapping
nmap <Leader>m :CtrlPMRUFiles<CR>
" commands finder mapping
nmap <Leader>b :CtrlPCmdPalette<CR>

" Syntastic ------------------------------

" show list of errors and warnings on the current file
nmap <leader>e :Errors<CR>
" check also when just opened the file
let g:syntastic_check_on_open = 1
" don't put icons on the sign column (it hides the vcs status icons of signify)
let g:syntastic_enable_signs = 1
" custom icons (enable them if you use a patched font, and enable the previous 
" setting)
let g:syntastic_error_symbol = '✗'
let g:syntastic_warning_symbol = '⚠'
let g:syntastic_style_error_symbol = '✗'
let g:syntastic_style_warning_symbol = '⚠'

" Python-mode ------------------------------

" don't use linter, we use syntastic for that
let g:pymode_lint_on_write = 0
let g:pymode_lint_signs = 0
" don't fold python code on open
let g:pymode_folding = 0
" don't load rope by default. Change to 1 to use rope
let g:pymode_rope = 0
" open definitions on same window, and custom mappings for definitions and
" occurrences
let g:pymode_rope_goto_definition_bind = ',d'
let g:pymode_rope_goto_definition_cmd = 'e'
nmap <Leader>D :tab split<CR>:PymodePython rope.goto()<CR>
" nmap <Leader>o :RopeFindOccurrences<CR>

" Window Chooser ------------------------------
" mapping
nmap  -  <Plug>(choosewin)
" show big letters
let g:choosewin_overlay_enable = 1

" Airline ------------------------------

let g:airline_powerline_fonts = 1
let g:airline_theme = 'bubblegum'
let g:airline#extensions#whitespace#enabled = 0
let g:airline#extensions#tabline#enabled = 1
let g:airline#extensions#tabline#left_alt_sep = '│'
let g:airline#extensions#branch#enabled = 1
let g:airline#extensions#branch#empty_message = ''
let g:airline#extensions#branch#displayed_head_limit = 10

" to use fancy symbols for airline, uncomment the following lines and use a
" patched font (more info on the README.rst)
if !exists('g:airline_symbols')
   let g:airline_symbols = {}
endif
let g:airline_left_sep = ''
let g:airline_left_alt_sep = ''
let g:airline_right_sep = ''
let g:airline_right_alt_sep = ''
let g:airline_symbols.branch = ''
let g:airline_symbols.readonly = ''
let g:airline_symbols.linenr = ''


" Better Search (f,F,t,T) ------------------------------

" search case-insensitive when search term is all lowercase
:set ignorecase
:set smartcase

let [pvft,pvftc]=[1,32]
fun! Multift(x,c,i)
    let [g:pvftc,g:pvft]=[a:c,a:i]
    let pos=searchpos((a:x==2? mode(1)=='no'? '\C\V\_.\zs' : '\C\V\_.' : '\C\V').(a:x==1 && mode(1)=='no' || a:x==-2? nr2char(g:pvftc).'\zs' : nr2char(g:pvftc)),a:x<0? 'bW':'W')
    call setpos("'x", pos[0]? [0,pos[0],pos[1],0] : [0,line('.'),col('.'),0]) 
    return "`x"
endfun
no <expr> F Multift(-1,getchar(),-1)
no <expr> f Multift(1,getchar(),1)
no <expr> T Multift(-2,getchar(),-2)
no <expr> t Multift(2,getchar(),2)
no <expr> ; Multift(pvft,pvftc,pvft)
" no <expr> , Multift(-pvft,pvftc,pvft)
