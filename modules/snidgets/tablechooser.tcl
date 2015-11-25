#
# SYNOPSIS:
#
#   TableChooser .tc \
#       -variable current_choice \
#       -columns {0 digit 0 word 0 Roman} \
#       -options {1 one I 2 two II 3 three III 4 four IV} \
#       -addmessage "Add another transation" \
#       -addefault {five} \
#       -addvalidate {string length} \
#       -addverify {string length}
#
# TODO:
#   * rename -options to -choices
#
package provide tablechooser 0.1
package require Tk
package require snit
package require tablelist

snit::widgetadaptor TableChooser {
    #hulltype tablelist::tablelist

    # beware: we hijack some of these!
    option -options      -default {} -configuremethod setOption
    option -listvariable -default {} -configuremethod setOption
    option -variable     -default {} -configuremethod setOption
    option -columns      -default {} -configuremethod setOption

    # for "New xxx"
    option -addmessage   -default {} -configuremethod setOption
    option -adddefault   -default {} -configuremethod setOption
    option -addverify    -default {} -configuremethod setOption
    option -addcommand   -default {} -configuremethod setOption

    delegate method * to hull
    delegate option * to hull

    constructor args {
        installhull using tablelist::tablelist
        $self configure -stretch 0 \
                -exportselection 1 \
                -selectmode browse \
                -height 0 \
                -width 0 \
                -editstartcommand [mymethod editStart] \
                -editendcommand [mymethod editEnd] \
                -forceeditendcommand 1 \
        ;#
        $self configurelist $args
        bind $self <<TablelistSelect>> [mymethod select]
        bind $self <<TablelistCellUpdated>> [mymethod editFinish]
    }

    method setOption {option value}  {
        switch -exact -- $option {
            -columns {
                set c [concat {*}[map {list 0} $value]]
                $hull configure -columns $c
                set options(-columns) $value
            }
            -listvariable {
                debug assert {[string match ::* $value]}    ;# I thought I knew how to handle this
                if {$options(-listvariable) ne ""} {
                    trace remove variable $value write [
                        lambda args [
                            list $self displayOptions
                        ]
                    ]
                }
                uplevel 1 [
                    list trace add variable $value write [
                        lambda args [
                            list $self displayOptions
                        ]
                    ]
                ]
                set options(-listvariable) $value
                after idle [mymethod displayOptions]
            }
            -options {
                set options(-options) $value
                if {$options(-listvariable) ne ""} {
                    set $options(-listvariable) $value
                } else {    ;# the trace will handle it
                    $self displayOptions
                }
            }
            -variable {
                set options($option) $value
            }
            -addmessage - -adddefault - -addvalidate - -addcommand - -addverify {
                set options($option) $value
                $self displayOptions
            }
        }
    }

    method displayOptions {} {
        if {$options(-columns) eq ""} {
            return
            #return -code error "Can't insert values without configuring columns!"
        }
        $self delete 0 end
        if {$options(-listvariable) ne ""} {
            set options(-options) [set $options(-listvariable)]
        }
        set value $options(-options)
        while {$value ne {}} {
            set vals [lshift value [llength $options(-columns)]]
            set idx [$self insert end $vals]
            $self rowconfigure $idx -name [lindex $vals 0]
        }
        ## special handling for adding a new item, which should probably be optional
        if {$options(-addmessage) ne ""} {
            set idx [$self insert end [list $options(-addmessage)]] ;# 1-elem list ok?
            $self rowconfigure $idx -name {}
            $self cellconfigure $idx,0 -image ::images(add) -editable 1
        }
    }

    # start editing
    method editStart {w row col value} {
        return $options(-adddefault)
    }

    # verify edit result
    method editEnd {w row col value} {
        if {($options(-addverify) eq "")} {
            $w rowconfigure $row -name $value
            return $value
        } else {
            set rc [catch {
                set value [uplevel 0 $options(-addverify) [list $value]]
            } err]
            if {$rc} { ;# an error occurred - blank the value
                tk_messageBox -icon error -type ok -message $err
                $w rowconfigure $row -name {}
                return ""
            } else {
                $w rowconfigure $row -name $value
                return $value
            }
        }
    }

    # end editing
    method editFinish {} {
        set value [$self rowcget end -name]
        if {$value ne ""} {
            $self cellconfigure end,0 -image ""
            if {$options(-addcommand) ne ""} {
                uplevel 0 $options(-addcommand) [list $value]
            }
            $self selection clear 0 end
            $self selection set $value
            $self select
        } else {
            $self displayOptions
        }
    }

    method select {} {
        set idx [$self curselection] 
        set val [$self rowcget $idx -name]
        if {$val eq ""} {
            return  ;# selected the -add option
        }
        if {$options(-variable) ne ""} {
            uplevel #0 [list set $options(-variable) $val]
        }
    }
}
