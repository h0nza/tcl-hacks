namespace eval tty {
    # http://real-world-systems.com/docs/ANSIcode.html#Esc
    proc _def {name args result} {
        set CSI \x1b\[      ;# or \x9b ?
        proc $name $args "string cat [list $CSI] $result"
    }
    _def up {{n ""}}        {[if {$n==0} return] $n A}
    _def down {{n ""}}      {[if {$n==0} return] $n B}
    _def right {{n ""}}     {[if {$n==0} return] $n C}
    _def left {{n ""}}      {[if {$n==0} return] $n D}
    _def erase {{n ""}}     {[if {$n==0} return] $n X}
    _def delete {{n ""}}    {[if {$n==0} return] $n P}
    _def insert {{n ""}}    {[if {$n==0} return] $n @}
    _def mode-insert {}     {4h}
    _def mode-replace {}    {4l}
    _def goto-col {col}     {$col G}
    _def goto {row col}     {$row \; $col H}
    _def erase-to-end {}     {K}
    _def erase-from-start {} {1K}
    _def erase-line {}       {2K}
}
