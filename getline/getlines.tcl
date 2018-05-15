# a wrapper around Getline that enhances it for multi-line input
oo::class create Getlines {
    superclass Getline

    variable Lines
    variable Lineidx
    variable Prompts        ;# for getlines, there must be a list of prompts!
    variable Prompt         ;# actually belongs to Getline

    constructor {args} {
        set Lines   [list ""]
        set Lineidx 0
        next {*}$args
        set Prompts [list $Prompt]
    }

    method reset {} {
        set Lines [list ""]
        set Lineidx 0
        next
    }

    # method goto .. count lines

    method clear {} {
        my reset
    }

    method getline {} {
        try {
            next
        } on break {} {
            return -code break
        } on continue {} {
            return -code continue
        }
        # FIXME: if [my display-rows] has changed, redraw-following
    }

    method get {} {
        lset Lines $Lineidx [input get]
        join $Lines \n
    }

    method redraw-following {} {
        set line [lindex $Lines $Lineidx]
        set pos [input pos]
        my end
        set idx $Lineidx
        incr idx
        while {$idx < [llength $Lines]} {
            output emit \n
            set l [lindex $Lines $idx]
            my set-state $l [string length $l]
            my redraw
        }
        my set-state $line $pos
    }

    # [insert \n] might create a new line!
    method newline {} {
        set input [my get]
        if {[my Complete? $input]} {
            # FIXME: go down
            tailcall my accept
        }
        my insert \n
    }

    method insert {s} {
        foreach c [split $s ""] {
            if {$c ne "\n"} {
                next $c
            } elseif {[info complete [my get]\n]} {
                tailcall my accept
            } else {
                my insert-newline
            }
        }
    }

    method insert-newline {} {
        set rest [my kill-after]
        set Lines [linsert $Lines $Lineidx+1 $rest]
        set rows [output wrap [output pos] [output rpos]]
        output emit [tty::down $rows]           ;# hmmm
        output emit \n
        incr Lineidx
        my set-state [lindex $Lines $Lineidx]
        my redraw
    }

    method prior-line {} {
        if {$Lineidx == 0} {my beep "no prev line"; return}
        my home
        output emit [tty::up 1]
        lset Lines $Lineidx [input get]
        incr Lineidx -1
        my set-state [lindex $Lines $Lineidx]
        set nrows [output wrap 0 [output len]]  ;# hmmm
        output emit [tty::up $nrows]            ;# hmmm
        my redraw
    }
    method next-line {} {
        if {$Lineidx + 1 == [llength $Lines]} {my beep "no next line"; return}
        my end
        lset Lines $Lineidx [input get]
        incr Lineidx 1
        my set-state [lindex $Lines $Lineidx]
        output emit [tty::down 1]               ;# hmmm
        my flash-message [my get]
        my redraw
    }

    method kill-next-line {} {
        set r [lindex $Lines $Lineidx+1]
        set Lines [lreplace $Lines $Lineidx+1 $Lineidx+1]
        return $r
    }
    method kill-prev-line {} {
        set r [lindex $Lines $Lineidx-1]
        set Lines [lreplace $Lines $Lineidx-1 $Lineidx-1]
        return $r
    }

    method back {{n 1}} {
        if {$n <= [input pos]} {
            next $n
        } elseif {$Lineidx > 0} {
            my prior-line
            my end
        } else {my beep "back at beginning of input"}
    }
    method forth {{n 1}} {
        if {$n <= [input rpos]} {
            next $n
        } elseif {$Lineidx+1 < [llength $Lines]} {
            my next-line
            my home
        } else {my beep "forth at end of input"}
    }

    method backspace {{n 1}} {
        if {$n <= [input pos]} {
            next $n
        } elseif {$Lineidx > 0} {
            my prior-line
            my end
            set s [my kill-next-line]
            my insert $s
            my redraw
            my redraw-following
        } else {my beep "backspace at beginning of input"}
    }
    method delete {{n 1}} {
        if {$n <= [input rpos]} {
            next $n
        } elseif {$Lineidx+1 < [llength $Lines]} {
            set rest [my kill-next-line]
            my insert $rest
            my back [string length $rest]
            my redraw
            my redraw-following
        } else {my beep "delete at end of input"}
    }

    method up {{n 1}} {
        if {$Lineidx > 0} {
            set pos [input pos]
            my prior-line
            my home
            set pos [expr {min($pos,[input rpos])}]
            my forth $pos
        }
    }
    method down {{n 1}} {
        if {$Lineidx + 1 < [llength $Lines]} {
            set pos [input pos]
            my next-line
            my home
            set pos [expr {min($pos,[input rpos])}]
            my forth $pos
        }
    }

}
