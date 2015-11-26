package require Tk

package require tkImprover
#source tkImprover-0.tm

pack [button .b -text button -command {puts Button!}]
pack [checkbutton .c -text check -command {puts Check!}]
pack [radiobutton .r1 -text radio\ 1 -variable radio -value 1 -command {puts Radio:$::radio}]
pack [radiobutton .r2 -text radio\ 2 -variable radio -value 2 -command {puts Radio:$::radio}]
pack [entry .e]

pack [ttk::button .tb -text button -command {puts Button!}]
pack [ttk::checkbutton .tc -text check -command {puts Check!}]
pack [ttk::radiobutton .tr1 -text radio\ 1 -variable radio -value 1 -command {puts Radio:$::radio}]
pack [ttk::radiobutton .tr2 -text radio\ 2 -variable radio -value 2 -command {puts Radio:$::radio}]
pack [ttk::entry .te]

pack [text .t -undo 1]

.e insert end "the sun always"
.t insert end "
    byteOrder - is the most significant, or least significant, byte first
    machine - some info specific to the kind of hardware
    os - a string identifying the operating system
    osVersion - the version of the os
    pathSeparator — character used to split variables like env(PATH) into a proper Tcl list (from 8.6)
    platform - which of the major types of computers is this
    pointerSize - bytes taken up by a void pointer (from 8.5)
    user - user's login id
    wordSize - number of bytes for a machine-word (actually, a long)
"

puts "\n\n====\n\n"
foreach w {.b .c .r1 .e .t} {
    puts "bindtags $w: [bindtags $w]"
    puts "class $w: [set class [winfo class $w]]"
    #puts "bind $class <Return>: [bind $class <Return>]"
}

