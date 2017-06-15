# [exec] for coroutines - do it asynchronously without blocking the event loop.
# "drop-in" replacement for [exec] - this passes "most" of exec.test within a coro.
source assert.tcl

proc putl args {puts $args}

proc coexec {args} {
#    putl given $args

    # TODO: support -keepnewline, -ignorestderr, --

    # find last stdout redirection in $args:
    set idx 0
    set i -1
    foreach arg $args {
        if {[string match >* $arg]} {set i $idx}
        incr idx
    }

    if {$i == -1} {     ;# no output redirection present
        set redir ""

    } else {            ;# output redirection
        set redir [lindex $args $i]

        # handle ">@stderr" and ">@ stderr"
        set j $i
        if {[regexp {^([>@&]+)\s*([^>@&].+)$} $redir -> r d]} {
            set redir $r
            set dest $d
        } else {
            set dest [lindex $args [incr j]]
            if {$j >= [llength $args]} {
                return -code error "can't specify \"$redir\" as last word in command"
            }
        }
    }

    # not all variants use the pipe, but all clean up
    lassign [chan pipe] rd wr
    chan configure $wr -blocking 0 -buffering none -translation binary
    chan configure $rd -blocking 0 -buffering none -translation binary

    switch $redir {
        ""      {  }
        >       { set args [lreplace $args $i $j] }
        >&      { set args [lreplace $args $i $j]; lappend args 2>@1 }
        >>      { set args [lreplace $args $i $j] }
        >>&     { set args [lreplace $args $i $j]; lappend args 2>@1 }
        >@      { set args [lreplace $args $i $j] }
        >&@     { set args [lreplace $args $i $j]; lappend args 2>@1 }
        default { error "Unhandled redirection \"$redir\"" }
    }

    set close 0
    switch $redir {
        ""      { set dest "" }
        >       { set dest [open $dest w];  set close 1 }
        >&      { set dest [open $dest w];  set close 1 }
        >>      { set dest [open $dest a];  set close 1 }
        >>&     { set dest [open $dest a];  set close 1 }
        >@      {  }
        >&@     {  }
        default { error "Unhandled redirection \"$redir\"" }
    }

#    putl using $args
    # delegate to open!
    set chan [open |$args {RDONLY NONBLOCK}]
    close $wr
    set result ""

    if {$dest ne ""} {
        close $rd
        chan copy $chan $dest -command [info coroutine]
        yield
    } else {
        # loop until both channels done
        chan event $rd   readable   [list [info coroutine] $rd]
        chan event $chan readable   [list [info coroutine] $chan]

        set eofs {}
        while {[dict size $eofs] < 2} {
            set which [yield]
            set data [read $which]
            if {$data ne ""} {
                if {$dest ne ""} {
                    puts -nonewline $dest $data
                } else {
                    append result $data
                }
            } elseif {[eof $which]} {
                dict incr eofs $which
            }
        }
        close $rd
    }
    if {$close} {close $dest}

    # capture errors with blocking close
    chan configure $chan -blocking 1
    if {$chan in [chan names]} {close $chan}

    if {[string match *\n $result]} {   ;# legacy [exec] behaviour without -keepnewline
        set result [string range $result 0 end-1]
    }
    return $result
}

proc main {args} {
    set tclsh [info nameofexe]

    set one [coexec $tclsh testee.tcl -o one!]
    assert {$one eq "one!"}
    set one [coexec $tclsh testee.tcl -e two! 2>@1]
    assert {$one eq "two!"}
    set one [coexec $tclsh testee.tcl -o one! -e two! 2>@1]
    assert {$one eq "one!\ntwo!"}
    set one [coexec $tclsh testee.tcl -e one! -o two! 2>@1]
    assert {$one eq "one!\ntwo!"}

    catch {exec $tclsh testee.tcl -e two!} rc1
    catch {coexec $tclsh testee.tcl -e two!} rc2
    assert {$rc1 eq $rc2}

    set one [coexec $tclsh testee.tcl -o two! > /dev/null]

    catch {coexec $tclsh testee.tcl -e two! > /dev/null} rc2
    assert {$rc1 eq $rc2}

    set one [coexec $tclsh testee.tcl -o one! > output]
    set one [coexec cat < output]
    assert {$one eq "one!"}

    set one [coexec $tclsh testee.tcl -o two! > output]
    set one [coexec cat < output]
    assert {$one eq "two!"}

    set one [coexec $tclsh testee.tcl -o two! >> output]
    set one [coexec cat < output]
    assert {$one eq "two!\ntwo!"}

    coexec $tclsh testee.tcl -o one! -e two! >& output
    set one [coexec cat < output]
    assert {$one eq "one!\ntwo!"}

    set fd [open output w]
    coexec $tclsh testee.tcl -o one! -e two! >&@ $fd
    close $fd
    set one [coexec cat < output]
    assert {$one eq "one!\ntwo!"}

    coexec $tclsh testee.tcl -e out! >& output
    set one [coexec cat < output]
    assert {$one eq "out!"}

    coexec $tclsh testee.tcl -e OUT! 2> output
    set one [coexec cat < output]
    assert {$one eq "OUT!"}

    assert {[chan names] eq {stdin stdout stderr}}
    puts okay!
}

if 0 {
    rename exec original_exec
    proc exec args {
        if {[info coroutine] eq ""} {
            tailcall ::original_exec {*}$args
        } else {
            tailcall ::coexec {*}$args
        }
    }

    proc main {} {
        global errorCode
        global errorInfo
        package require tcltest
        source ~/Tcl/Env/src/tcl/tests/exec.test
    }
}

coroutine run main {*}$::argv
trace add command run delete {lappend ::forever}
vwait ::forever
