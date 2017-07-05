#!/usr/bin/env tclsh
#
# Stubbed out Gerber RS-274X parser, following
#  https://www.ucamco.com/files/downloads/file/81/the_gerber_file_format_specification.pdf
#
# Why?  Because libgerbv uses floating point (well, it's allowed), but also because I wanted to understand the format more than understand someone else's code.  Goal is to be able to lint gerber files:  features too small, fills by painting, risky overlap, false apertures ...
#
# Basics:
#   7-bit ascii clean: \x20..\x7e
#   \x0a, \x0d CR/LF have no effect
#   \x20 space only legal inside strings
#   Case sensitive:  command codes all in UPPER CASE
#   Data blocks end at "*"
#   %...% special syntax for extended code commands
#

# Names beginning with a for are reserved
set name_regex {[a-zA-Z_.$][a-zA-Z_.0-9]+}

# All but \r\n%*
# Note there is no escape char.  \ is literal. \u{hex4} is unicode.
set string_regex {(\\u[0-9a-fA-F]{4}|[a-zA-Z0-9_+-/!?<>\"'(){}.|&@# ,;$:=])+}

proc putl {args} {puts $args}
proc _trace {args} {
    set c [info coroutine]
    set s [uplevel 1 self]
    set l [info level [expr {[info level]-1}]]
    set _ [string repeat \  [info level]]
    puts stderr "TRACE$_[concat $c $s $l $args]"
}


# integers must fit in a 32-bit integer
# decimals must fit in an IEEE double
# coordinate numbers must conform to FS

# Contours have an origin and a (closed, non-intersecting) list of strokes
# Standard contours (Circle Rect Obloid Poly) have origin = centre

oo::class create Gerber {
    variable Coord_format   ;# FS (4.9)
    variable Unit           ;# MO (4.10) {in mm}
    variable X
    variable Y
    variable Interpolation  ;# G1 G2 G3 (4.4, 4.5) {1 cw ccw 10 0.1 0.01}
    variable Quadrant_mode  ;# G74 G75 (4.5) {single multi}
    variable Aperture       ;# AD AM (4.11 4.13) {C R O P ...}
    variable Polarity       ;# LP (4.14) {dark clear}   dark
    variable Region_mode    ;# G36 G37 (4.6) {on off}   off

    constructor {} {
        set Polarity dark
        set Region_mode off
        set X ""; set Y ""
    }

    method parse {s} {
        _trace
        set i 0
        while {$i < [string length $s]} {
            if {[string is space [string index $s $i]]} {incr i; continue}
            if {[string index $s $i] eq "%"} {
                set j [string first % $s $i+1]
                if {$j == -1} {error "Expected another % after $i [string range $s $i end]!"}
                set cmd [string range $s $i+1 $j-1]
                set i [expr {$j + 1}]
                my Extended $cmd
            } else {
                set j [string first * $s $i]
                if {$j == -1} {error "Expected another * after $i [string range $s $i end]!"}
                set cmd [string range $s $i $j-1]
                set i [expr {$j + 1}]
                my Command $cmd
            }
        }
    }

    method Command {text} {
        _trace X=$X Y=$Y
        set coords [dict create]
        set rest $text[unset text]
        while {[regexp {\A([A-Z])([+-]?[0-9]+)(.*)\Z} $rest -> fun num rest]} {
            scan $num %d num
            if {$fun in {X Y I J}} {
                dict set coords $fun $num
            } else {
                my Function $fun$num $rest $coords
                #break  ;# apparently not, say the tests
            }
        }
        if {$rest ne ""} {
            error "Unexpected leftovers after command: [list $rest]"
        }
        # simply: dict with coords {}  ?
        dict with coords {}
#        dict for {k v} $coords {
#            set $k $v
#        }
    }

    method Function {code arg args} {
        _trace
        switch $code {
            D1 {  ;# Interpolate (4.2)
                if {$Region_mode} {
                    # create contour segment
                } else {
                    # draw arc
                    if {$Interpolation in {linear 1 10 0.1 0.01}} {
                        # draw line from (X,Y) to (x,y)
                    } else {
                        # draw arc from (X,Y) to (x,y) with center at (i,j)
                    }
                }
            }
            D2 {  ;# Move (4.2)
            }
            D3 {  ;# Flash
                if {$Region_mode} {
                    error "D03 with region mode off!"
                } else {
                    # flash current aperture
                }
            }
            D4 - D5 - D6 - D7 - D8 - D9 {
                error "Reserved function D0x!"
            }
            D* {
                if {$Region_mode} {
                    error "D* with region mode off!"
                }
                # FIXME: select aperture
            }
            G1 {
                set Interpolation linear
            }
            G2 {
                set Interpolation cw
            }
            G3 {
                set Interpolation ccw
            }
            G4 {
                # comment
            }
            G10 {
                set Interpolation 10
            }
            G11 {
                set Interpolation 0.1
            }
            G12 {
                set Interpolation 0.01
            }

            G36 {
                set Region_mode on
            }
            G37 {
                set Region_mode off
            }

            G54 {
                puts stderr "Ignoring obsolete G54 (select aperture)"
            }
            G55 {
                puts stderr "Ignoring obsolete G55 (prepare for flash)"
            }
            G70 {
                error "Obsolete G70 (unit = inch)"
            }
            G71 {
                error "Obsolete G71 (unit = mm)"
            }

            G74 {   ;# (4.5)
                set Quadrant_mode single
            }
            G75 {   ;# (4.5)
                set Quadrant_mode multi
            }

            G90 {
                error "Obsolete code G90 (absolute coord mode)!"
            }
            G91 {
                error "Obsolete code G91 (incremental coord mode)!"
            }

            M02 {
                # end of program
            }
        }
    }

    method Extended {cmd} {
        _trace
        set arg [string range $cmd 2 end]
        set cmd [string replace $cmd 2 end]
        # FS MO  -- (4.11) only once, at head of file
        # AD AM  -- (4.13) multi ok.  recommended at header
        # LP SR  -- (4.14)
        switch $cmd {
            FS {
                # FSLAX25Y25
                if {[regexp {\ALAX([0-6])([4-6])Y([0-6])([4-6])\*\Z} $arg -> xi xd yi yd]} {
                    # xi == yi, xd == yd
                }
            }
            MO {
                set Unit [dict get {IN* in MM* mm} $arg]
                puts "UNIT $arg"
            }

            AD {
                if {[regexp {\AD([0-9]+)([CROP])(?:,(.*))?\*\Z} $arg -> idx kind params]} {
                    # define aperture $idx as $kind with $params
                } elseif {[regexp {\AD([0-9]+)(.*)\*\Z} $arg -> idx name]} {
                    # define as index of macro $name
                } else {
                    error "Unknown AD command: AD$arg"
                }
            }
            AM {
                if {[regexp {\A([A-Z0-9]*)\*(.*)\Z} $arg -> name script]} {
                    # define aperture macro
                } else {
                    error "Unknown AD command: AD$arg"
                }
            }

            LP {
                set Polarity [dict get {D* dark C* clear} $arg]
            }

            SR {
                # ???
            }

            TF {
                # file attribute
            }
            TA {
                # aperture attribute:  applies to all that follow
            }
            TD {
                # ???
            }
        }
    }

}

oo::class create Parse {
    variable str idx
    constructor {s} {
        set str $s
        set idx 0
        my space
    }
    method Error {args} {
        set what [lindex [info level [expr {[info level]-1}]] 1]
        puts "ERROR: expected $what at index $idx, before '[string range $s $idx $idx+10]...'"
    }

    proc Def {name args body} {
        tailcall proc $name [list _str _idx {*}$args] "
            upvar 1 \$_str str
            upvar 1 \$_idx idx
            $body
        "
    }

    Def end {} {
        if {$idx != [string length $str]} {Error}
    }
    Def space {} {
        if {![regexp -idx $idx {\A\s*} $str _]} {Error}
        incr idx [string length $_]
    }
    Def function {} {
        if {![regexp -idx $idx {\A([A-Z])([+-]?[0-9]+)} _ f num]} {Error}
        incr idx [string length $_]
        list $f [expr {$num}]
    }
    Def extended {} {
        if {![regexp -idx $idx {\A%([^%]*)%} $str _ commands]} {Error}
        incr idx [string length $_]
        return $commands
    }
    Def command {} {
        if {![regexp -idx $idx {\A([^*]*)*} $str _ commands]} {Error}
        set coords [dict create]
        set i 0
        while {$i < [string length $_]} {
            lassign [function _ i] fun num
            if {$fun in {X Y I J}} {
                dict set coords $fun $num
            } else {
                Eval $fun$num $coords
            }
        }
        end _ i
    }
}

if 1 {
    proc Eat {_ re args} {
        upvar 1 #str str
        upvar 1 #idx idx
        #puts [info level [info level]]:$idx
        if {$args ne ""} {
            upvar 1 [lindex $args 0] match
        }
        if {[regexp -start $idx \\A$re $str match]} {
            #puts "ate: [list $match]"
            incr idx [string length $match]
            if {$args ne ""} {
                puts "$args = $match"
            }
            if {!$_} {
                return true
            }
        } else {
            if {!$_} {
                return false
            } else {
                tailcall Eaterror "{$re}"
            }
        }
    }
    proc Eaterror {msg} {
        upvar 1 #str str
        upvar 1 #idx idx
        tailcall return -code error "Expected $msg at $idx ([string range $str $idx 10+$idx])"
    }
    interp alias {} eat? {} Eat 0
    interp alias {} eat! {} Eat 1
    interp alias {} eat  {} Eat 1
    proc grbr {#str {#idx 0}} {
        while {${#idx} < [string length ${#str}]} {
            eat \\s*
            if {[eat? %]} {
                if {[eat? MO]} {
                    eat IN|MM unit
                } elseif {[eat? FSLAX]} {
                    eat {[0-6]} xi
                    eat {[4-6]} xd
                    eat Y$xi$xd
                } elseif {[eat? LN]} {
                    eat {[^*]*} linespec
                } elseif {[eat? AD]} {
                    eat D
                    eat {[0-9]*} apid
                    eat {[CROP]} aptype
                    eat ,
                    eat {[^*]*} apargs
                } elseif {[eat? AM]} {
                    eat {[0-9A-Z]*} name
                    eat {\*}
                    eat {[^*]*} script
                }
                eat {\*}
                eat %
            } elseif {[eat? G0*4]} {
                eat {[^*]*} comment
                eat *
            } elseif {[eat? {[XYIJ]} coord]} {
                eat {[0-9]*(?:\.[0-9]*)?} value
            } elseif {[eat? {[DGM][0-9]*} cmd]} {
            } elseif {[eat? {\*}]} {
            }
        }
        eat \\s*
        if {${#idx} != [string length ${#str}]} {
            Eaterror "Expected EOF"
        }
    }
}

set tests {
    test-drill-leading-zero-1 {
        %MOIN*%
        %FSLAX25Y25*%
        %LNOUTLINE*%
        %ADD22C,0.0100*%
        G54D22*X0Y36000D02*G75*G03X0Y36000I36000J0D01*G01*
        M02*
    }
}

proc main {args} {
    dict for {name gbr} $args {
        puts "$name:"
        grbr $gbr
        #Gerber create ger
        #ger parse $gbr
        #ger destroy
    }
}

main {*}$tests
