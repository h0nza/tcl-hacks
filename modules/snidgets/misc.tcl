package provide mysnits 0.1

package require Tk
package require ctext
package require snit

#
# A readonly entry which invokes -command on Invoke
# the result of -command becomes the new value
#
snit::widgetadaptor TouchInput {

    option -command     -default {}

    delegate option -variable to hull as -textvariable  ;# go team!

    delegate option * to hull
    delegate method * to hull

    constructor args {
        installhull using entry
        $self configurelist $args
        bind $win <1> [mymethod activate]
        bind $win <Return> [mymethod activate]
        bind $win <<Invoke>> [mymethod activate]
    }
    method activate args {
        # after idle ?
        $self configure -state normal   ;# yuck
        $self delete 0 end
        $self insert 0 [uplevel #0 $options(-command)]  ;# how does this get arguments?
        $self configure -state readonly ;# yuck
    }
}

#bind Ctext <Control-y> {%W edit redo}
#bind Ctext <Control-z> {%W edit undo}
# adds a -textvariable param to ctext (using traces)
snit::widgetadaptor Ctext {
    option -textvariable -default {} -configuremethod setOption
    option -maxheight    -default {} ;# -configuremethod setOption
    delegate method ins to hull as insert
    delegate method del to hull as delete
    delegate method rp to hull as replace
    delegate method * to hull
    delegate option * to hull
    constructor {args} {
        installhull using ctext
        $self configurelist $args
        bind $self <<Modified>> [mymethod <<Modified>>]   ;# this isn't quite right
        bind $self <FocusIn> [mymethod takeFocus]
        bind $self <Control-y> {%W edit redo} ;# doesn't belong here!
    }
    destructor {
        if {[info exists options(-textvariable)] && $options(-textvariable) ne ""} {
            trace remove variable $options(-textvariable) read [mymethod readTrace]
            trace remove variable $options(-textvariable) write [mymethod writeTrace]
        }
    }
    method insert args { $self ins {*}$args ; $self updateVar }
    method delete args { $self del {*}$args ; $self updateVar }
    method replace args { $self rp {*}$args ; $self updateVar }

    method updateVar args {
        if {[info exists options(-textvariable)] && $options(-textvariable) ne ""} {
            trace remove variable $options(-textvariable) write [mymethod writeTrace]
            set $options(-textvariable) [$self getText]
            if {[info exists options(-maxheight)] && $options(-maxheight) ne ""} { ;# c&p from below
                set h [llength [split [$self getText] \n]]
                $self configure -height [expr {min($h,$options(-maxheight))}]
            }
            trace add variable $options(-textvariable) write [mymethod writeTrace]
        }
    }

    method takeFocus {} { ;# work around ctext's broken focus
        debug log {taking focus}
        focus $self.t
    }
    method setOption {option value} {
        switch -exact -- $option {
            -textvariable {
                if {[info exists options(-textvariable)] && $options(-textvariable) ne ""} {
                    trace remove variable $options(-textvariable) read [mymethod readTrace]
                    trace remove variable $options(-textvariable) write [mymethod writeTrace]
                }
                set options(-textvariable) $value
                $self writeTrace
                trace add variable $value write [mymethod writeTrace]
                trace add variable $value read [mymethod readTrace]
            }
            default {
                return -code error "Unknown options $option"
            }
        }
    }
    method <<Modified>> args {
        #log info "<<Modified>> $self"
        set modified [$self edit modified]
        $self configure -linemapbg [expr {$modified ? "#fcc" : "#ffc"}]
        trace remove variable $options(-textvariable) read [mymethod readTrace]
        trace remove variable $options(-textvariable) write [mymethod writeTrace]
        set cur $options(-textvariable) ;# BUGBUG
        if {$cur ne ""} {
            # this would probably be better done by calling the cb with a flag
            set text [$self getText]
            if {$text ne $cur} {
                set $options(-textvariable) $text
            }
        }
        if {[info exists options(-maxheight)] && $options(-maxheight) ne ""} {
            set h [llength [split [$self getText] \n]]
            $self configure -height [expr {min($h,$options(-maxheight))}]
        }
        trace add variable $options(-textvariable) write [mymethod writeTrace]
        trace add variable $options(-textvariable) read [mymethod readTrace]
        #$self configure -linemapbg #fcc
    }
    method readTrace args {
        set $options(-textvariable) [$self getText]
    }
    method writeTrace args {
        $self setText [set $options(-textvariable)]
    }
    method getText {} {
        string range [$self get 1.0 end] 0 end-1 ;# !!
    }
    method setText {text} {
        $self del 1.0 end
        $self ins 1.0 $text
        event generate $self <<Modified>>
    }
}



snit::widgetadaptor CollapsingFrame {
    component b
    delegate option -text to b
    delegate option -textvariable to b
    delegate option * to hull
    delegate method * to hull
    constructor args {
        installhull using labelframe
        install b using label $win.b
        $self configurelist $args
        $self configure -labelwidget $b
        bind $b <1> [mymethod collapse]
    }
    method collapse {} {
        set C "+" ;#\u25ba
        set O "-" ;#\u25bc
        set h [winfo height $b]
        incr h 2
        set f [winfo parent $b]
        set title [$b cget -text]
        set title [string trimleft $title "$C$O "]
        if {[grid propagate $f]} {
            grid propagate $f 0
            $f configure -height $h
            $b configure -text "$C $title"
        } else {
            grid propagate $f 1
            $f configure -height 0
            $b configure -text "$O $title"
        }
    }
}
