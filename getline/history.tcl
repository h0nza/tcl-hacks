proc quote_glob {s} {
    regsub -all {\[|\*|\?|\]|\\} $s {\\\0} s
    return $s
}

# readline-style history has some odd properties:
#  using history-prev/next, edits on any history entry persist until accept
#  using history-search (for prefix), edits are immediately discarded
#  using search-history also preserves edits

oo::class create HistoryCursor {
    variable Items Index

    constructor {items {index ""}} {
        if {$index eq ""} {
            set index [llength $items]
        }
        set Items $items
        set Index $index
    }

    method get {} {lindex $Items $Index}
    method index {} {return $Index}
    method items {} {return $Items}

    method prev {{curr ""}} {
        if {$curr ne ""} {lset Items $Index $curr}
        if {$Index <= 0} {return ""}
        incr Index -1
        lindex $Items $Index
    }
    method next {{curr ""}} {
        if {$curr ne ""} {lset Items $Index $curr}
        if {$Index+1 >= [llength $Items]} {return ""}
        incr Index +1
        lindex $Items $Index
    }

    method prev-matching {glob {curr ""}} {
        if {$curr ne ""} {lset Items $Index $curr}
        set hits [lsearch -all -glob $Items $glob]
        set hit [lsearch -inline -sorted -bisect -integer $hits [expr {$Index-1}]]
        if {$hit eq ""} {return}
        set Index $hit
        lindex $Items $Index
    }
    method next-matching {glob {curr ""}} {
        if {$curr ne ""} {lset Items $Index $curr}
        set hit [lsearch -start [expr {1 + $Index}] -glob $Items $glob]
        if {$hit == -1} {return}
        set Index $hit
        lindex $Items $Index
    }
}

oo::class create History {
    variable Items
    variable Cursor

    constructor {} {
        set Items {}
        set Cursor {}
    }
    destructor {
        my cursor destroy
    }

    method cursor {args} {
        if {$Cursor eq ""} {
            if {$args eq {destroy}} return
            set Cursor [HistoryCursor new $Items]
        }
        if {$args eq {destroy}} {
            $Cursor destroy
            set Cursor ""
            return
        }
        tailcall $Cursor {*}$args
    }

    method add {args} {
        my cursor destroy
        foreach item $args {
            if {$item eq [lindex $Items end]} continue
            lappend Items $item
        }
    }

    method items {} {
        return $Items
    }
    method get {idx} {
        if {$idx < 0} {
            set idx end+[incr idx]
        }
        lindex $Items $idx
    }

    method prev {args}                  { my cursor prev {*}$args }
    method next {args}                  { my cursor next {*}$args }
    method prev-matching {glob args}    { my cursor prev-matching $glob {*}$args }
    method next-matching {glob args}    { my cursor next-matching $glob {*}$args }
    method prev-starting {s args}       { my prev-matching  [quote_glob $s]* {*}$args }
    method next-starting {s args}       { my next-matching  [quote_glob $s]* {*}$args }
    method prev-containing {s args}     { my prev-matching *[quote_glob $s]* {*}$args }
    method next-containing {s args}     { my next-matching *[quote_glob $s]* {*}$args }
}

if {$::argv0 eq [info script]} {
    History create history
    history add fee fie foe fum
    set s frok
    puts [history cursor items]
    while 1 {
        set s [history prev x[history cursor get]]
        puts <[history cursor index]:$s
        if {$s eq ""} break
    }
    puts [history cursor items]
    while 1 {
        set s [history next y[history cursor get]]
        puts >[history cursor index]:$s
        if {$s eq ""} break
    }
    puts [history cursor items]
    while 1 {
        set s [history prev X[history cursor get]]
        puts <[history cursor index]:$s
        if {$s eq ""} break
    }
    puts [history cursor items]
    puts [history items]
}
