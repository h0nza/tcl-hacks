source util.tcl    ;# lshift

namespace eval tty {
    namespace path [namespace parent]

    # http://real-world-systems.com/docs/ANSIcode.html#Esc
    proc _def {name args result} {
        set CSI \x1b\[      ;# or \x9b ?
        proc $name $args "string cat [list $CSI] $result"
    }
    _def up {{n ""}}          { [if {$n==0} return] $n A }
    _def down {{n ""}}        { [if {$n==0} return] $n B }
    _def right {{n ""}}       { [if {$n==0} return] $n C }
    _def left {{n ""}}        { [if {$n==0} return] $n D }
    _def erase {{n ""}}       { [if {$n==0} return] $n X }
    _def delete {{n ""}}      { [if {$n==0} return] $n P }
    _def insert {{n ""}}      { [if {$n==0} return] $n @ }
    _def insert-line {{n 1}}  { [if {$n==0} return] $n L }
    _def delete-line {{n 1}}  { [if {$n==0} return] $n D }
    _def goto-col {col}       { $col G}
    _def goto {row col}       { $row \; $col H }
    _def erase-to-end {}      { K }
    _def erase-from-start {}  { 1K }
    _def erase-line {}        { 2K }

    _def identify {}          { c }
    _def save {}              { s }
    _def restore {}           { u }
    _def report {}            { 6n }      ;# responds with ^[[25;80R

    _def set-scroll-region {t b} { $t ; $b r}
    _def mode-insert {}       { 4h }
    _def mode-replace {}      { 4l }
    _def mode-wrap {}         { = 7 h }
    _def mode-nowrap {}       { = 7 l }

    # eg: [tty::attr fg bright blue bg blue bold]
    # note {fg bright blue} not often supported: try {fg blue bold}
    proc attr {args} {
        set attr {0}
        while {$args ne ""} {
            set arg [lshift args]
            if {$arg in {fg bg}} {
                set colour [lshift args]
                set bright [expr {$colour eq "bright"}]     ;# not widely supported?
                if {$bright} {set colour [lshift args]}
                # fg: 3x; bg: 4x; bright fg: 9x; bg: 10x
                set prefix [expr {3 + ($arg eq "bg") + 6*$bright}]
                lappend attr $prefix[_colour $colour]
            } else {
                lappend attr [dict get {bold 1 under 4 blink 5 reverse 7} $arg]
            }
        }
        string cat \x1b \[ [join $attr \;] m
    }

    # takes either:
    #  - a named (8-colour) colour
    #  - gray%d where %d in [0,23]
    #  - #fff, for a 256-colour selection (actually 232)
    #  - #ffffff, for a 24-bit colour
    proc _colour {c} {
        if {[regexp {^#[[:xdigit:]]{6}$} $c rgb]} {
            return "8;2;[_24bcolour $rgb]"
        } elseif {[regexp {^#[[:xdigit:]]{3}$} $c rgb]} {
            return "8;5;[_256colour $rgb]"
        } elseif {[scan $c gray%d g] == 1} {
            return "8;5;[_256gray $g]"
        } else {
            return [_8colour $c]
        }
    }
    # 24bit:        fg 38;2;$r;$g;$b m   bg 48;2;$r;$g;$b m
    # 256colour:    fg 38;5;$_ m         bg 48;5;$_ m
    # bright colours are specified by either 3x becoming 9x, or attr bold.  The former less (?) commonly.
    proc _8colour {c} {
        set names {black red green yellow blue magenta cyan white}
        set r [lsearch $names $c]
        if {$r == -1} {return -code error "Bad named colour specifier: $c (expected one of $names)"}
        return $r
    }
    proc _24bcolour {c} {
        if {[scan $c #%2x%2x%2x r g b] != 3} {return -code error "Bad 24-bit colour specifier: $c (expected 6 hex digits)"}
        return "$r;$g;$b"
    }
    proc _256gray {n} {
        if {$n < 0 || $n > 23} {return -code error "Unknown gray $n (expected 0..23)"}
        expr {232 + $n}
    }
    # 256colour:
    #   0..7:       8  normal      (unpredictable rgb, but like \e[3Xm)
    #   8..15:      8  bright      (unpredictable rgb, but like \e[9Xm or like \e[3X;1m)
    #   16..231:  216  rgb 6.6.6
    #   232..255:  24  grays
    proc _256colour {c} {
        if {[scan $c #%1x%1x%1x r g b] != 3} {return -code error "Bad 256-colour specifier: $c (expected 3 hex digits)"}

        # pick grays from 232..255 (24 levels, but we can only reach 16!)
        set curve { 1  2   4  5   7  8  10 11  13 14  16 17  19 20  22 23}
        if {$r == $g && $g == $b}   {return [expr {232 + [lindex $curve $r]}]}

        # ignore 0..16, because their intensities are unpredictable

        set r [lindex {0 1 1 1 2 2 2 3 3 3 4 4 4 5 5 5} $r]     ;# 0 is under-repped, but that's okay!
        set g [lindex {0 1 1 1 2 2 2 3 3 3 4 4 4 5 5 5} $g]
        set b [lindex {0 1 1 1 2 2 2 3 3 3 4 4 4 5 5 5} $b]
        return [expr {16 + $r*36 + $g*6 + $b}]
    }
}

# demos!  only colours/attrs here; cursor movement needs interactivity
if {[info exists ::argv0] && ([info script] eq $::argv0)} {

    proc demo_16 {} {
        foreach bg {black red green yellow blue magenta cyan white} {
            foreach bgb {"" bright} {
                puts -nonewline " ."
                foreach fg {black red green yellow blue magenta cyan white} {
                    foreach fgb {"" bright} {
                        puts -nonewline [tty::attr bg {*}$bgb $bg fg {*}$fgb $fg]XXX[tty::attr].
                    }
                }
                puts ""
            }
        }
    }

    proc demo_attr {} {
        set attrs {bold under blink reverse}
        set disp  {bo un bl rv}
        for {set i 0} {$i < 4} {incr i} {
            for {set j 0} {$j < 4} {incr j} {
                set bits [format %0[llength $attrs]b [expr {$i * 4 + $j}]]
                set bits [split $bits ""]
                set a [lmap c $bits a $attrs {
                    if {!$c} continue
                    set a
                }]
                set t [lmap c $bits d $disp {
                    expr {$c ? $d : "--"}
                }]
                puts -nonewline " [tty::attr {*}$a] $t [tty::attr] "
            }
            puts ""
        }
    }

    proc demo_256 {} {
        # show off 256 colours:
        for {set r 0} {$r < 6} {incr r} {
            for {set g 0} {$g < 6} {incr g} {
                for {set b 0} {$b < 6} {incr b} {
                    set i [expr {$r * 36 + $g * 6 + $b}]
                    set R [lindex {0 3 6 9 c f} $r]
                    set G [lindex {0 3 6 9 c f} $g]
                    set B [lindex {0 3 6 9 c f} $b]
                    set rgb #$R$G$B
                    puts -nonewline " [tty::attr fg $rgb] $rgb [tty::attr]"
                    if {$i % 12 == 11} {puts ""}
                }
            }
        }
    }
    proc demo_gray24 {} {
        for {set g 0} {$g < 24} {incr g} {
            puts -nonewline "  "
            for {set G 0} {$G < 24} {incr G} {
                puts -nonewline "[tty::attr fg gray$g bg gray$G]*[tty::attr]"
            }
            puts ""
        }
    }

    proc demo_24bit {} {
        set i 0
        lassign [exec stty size] rows cols
        while 1 {
            set col [expr {$i % (2 * $cols)}]
            if {$col > $cols} {set col [expr {2 * $cols - $col}]}
            set col [expr {$col / 7 * 7}]
            set col [expr {min($col, $cols-7)}]
            set r [expr {round(128 + 127 * sin($i*3.0/$cols))}]
            set g [expr {round(128 + 127 * sin($i*5.0/$cols))}]
            set b [expr {round(128 + 127 * sin($i*7.0/$cols))}]
            set fg [format #%02x%02x%02x $r $g $b]
            puts -nonewline [tty::goto-col $col][tty::attr fg $fg]$fg; flush stdout
            after 10
            incr i
        }
    }

    try {
        puts "## 16-colour demo"
        demo_16
        puts "\n## attributes demo"
        demo_attr
        puts "\n## 216-colour demo"
        demo_256
        puts "\n## 24-level grayscale demo"
        demo_gray24
        #puts "\n## 24 bit snake!"
        #demo_24bit
    } finally {
        puts -nonewline [tty::attr]
    }
}
