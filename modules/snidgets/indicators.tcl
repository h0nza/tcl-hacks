package require tooltip ;# tklib
package require snit

snit::widgetadaptor Lamp {
    variable State
    delegate method * to hull
    delegate option * to hull
    constructor args {
        installhull using label
        # $self configure -text \u25c9    ;# FISHEYE
        $self configure -text \u25cf      ;# LARGE BLACK CIRCLE
        # $self configure -text \u2022    ;# BULLET
        # $self configure -text *         ;# ultimate fallback
        $self configure -fg gray50
        $self configurelist $args
    }
    method state args {
        tailcall $self state/[llength $args] {*}$args
    }
    method state/0 {} {
        return $State
    }
    method state/1 {state} {
        set State $state
        $self configure -fg $State
    }
}

# this expects to be given a container widget
oo::class create Indicators {
    variable W
    variable Packer
    variable I
    variable Sym
    variable Statemap
    constructor {container {packer {pack -side right}}} {
        set W $container
        set Packer $packer
        array set I {}
        set Sym -1
        set Statemap {}
    }
    method statemap {d} {
        set Statemap [dict merge $Statemap $d]
    }
    method state args {
        catch {lset args end [dict get $Statemap [lindex $args end]]}
        tailcall my state/[llength $args] {*}$args
    }
    method delete {name} {
        tooltip::tooltip clear $I($name)
        destroy $I($name)
        unset I($name)
    }
    method widget {name} {
        if {![info exists I($name)] || $I($name) eq ""} {
            set I($name) [Lamp ${W}.i#[incr Sym]]
            tooltip::tooltip $I($name) $name
            {*}[linsert $Packer 1 $I($name)]
        }
        return $I($name)
    }
    method state/1 {name} {
        set w [my widget $name]
        $w state
    }
    method state/2 {name colour} {
        set w [my widget $name]
        $w state $colour
    }
}
