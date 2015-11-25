#
# The design choice here is for each row to have an explicit name, thus [insert] must take pairs.
#
# An alternative would be for [lindex 0] of each inserted list to be a key, but that raises
# indexing questions (0- or 1-based?) for columns so is better avoided.  Dicts are king!
#
# -command takes %-substitution:
#  %W %x %y %X %Y %j %i
#  %C(olumn name)
#  %V(alue)
#  %N(ame)
#
package require adebug
package require snit
package require tablelist
package require sql
package require adebug
package require tests

#package require autoscroll
#::autoscroll::wrap

snit::widgetadaptor easytable {

    delegate method Get     to hull as get  ;# these methods are overridden
    delegate method Insert  to hull as insert
    delegate method *       to hull

    option          -command    -default {puts {%W activate %N (%j) %C (%i) %V}}
    delegate option -tlcolumns  to hull as -columns 
    option          -columns    -configuremethod SetOpt
    option          -rightmenu  -default "" ;# -configuremethod SetOpt
    delegate option *           to hull

    constructor args {
        set args [dict merge {
                -labelcommand tablelist::sortByColumn
                -labelcommand2 tablelist::addToSortColumns
                -snipstring \u2026
                -stretch all
                -resizablecolumns yes
                -showseparators yes
                -stripebackground #ccccff
                -selecttype cell
                -selectmode extended
                -exportselection 1
            } $args]
        installhull using tablelist::tablelist
        $self configurelist $args
        bind $win.body <Double-Button-1> [mymethod Activate mouse]
        bind $win.body <Return> [mymethod Activate active]
        bind $win.body <Button-3> [mymethod Rightmenu]
        # bind $win.body <Control-a> [mymethod selection set 0 end] ;# ??? FIXME
    }

    method Rightmenu {} {
        if {[set spec $options(-rightmenu)] eq ""} {
            return
        }
        if {[winfo exists $win.rm]} {
            destroy $win.rm
        }
        set cell [$self mousecell]
        mkmenu $win.rm [$self CmdSub $spec $cell]
        set xy [winfo pointerxy $win]
        ;# [map ::tcl::mathop::+ [winfo pointerxy $win] [list [winfo rootx $win] [winfo rooty $win]]]
        tailcall tk_popup $win.rm {*}$xy
    }

    method SetOpt {name value} {
        switch $name {
            -columns {
                set tlc [lconcat c $value {list 0 $c}]
                $self configure -tlcolumns $tlc
            }
            default {
                error "Unknown option: $name"
            }
        }
        set options($name) $value
    }

    method columns {names} {
        $win configure -columns $names  ;# $win instead of $self for dynamic dispatch /~inheritance
    }

    method set args {
        switch [llength $args] {
            2 { $self set/2 {*}$args }
            3 { $self set/3 {*}$args }
            default { raise {BADARGS} "FIXME: multiargs" }
        }
    }
    method set/2 {j values} {
        foreach i [range [$self columncount]] value $values {
            $self cellconfigure [$self RowId $j],$i -text $value
        }
    }
    method set/3 {j i value} {
        $self cellconfigure [$self RowId $j],$i -text $value
    }

    method get args {
        switch [llength $args] {
            0 {
                tailcall $self Get 0 end
            }
            1 { lassign $args j
                set j [$self RowId $j]
                tailcall $self Get $j
            }
            2 { lassign $args j i
                set j [$self RowId $j]
                tailcall $self getcells $j,$i
            }
            default {
                raise {BAD_ARGS} "FIXME: this should be a proper error"
            }
        }
    }

    ;# return "" if the key is invalid
    method RowId {key} {
        set i [$hull findrowname n$key]
        if {$i == -1} {
            lassign [$hull getfullkeys $key] i
        }
        return $i
    }

    ;# same for insert* would be great!
    method insert {index args} {
        debug assert {[llength $args]%2==0}
        set names   [lmap {a b} $args {set a}]
        set values  [lmap {a b} $args {set b}]
        set values [lmap v $values {
            set diff [expr {[$self columncount] - [llength $v]}]
            if {$diff > 0} {
                lappend v [lrepeat $diff {}]
            } elseif {$diff < 0} {
                throw {EASYTABLE TOOMANY} "Too many values by [expr -$diff]"
            }
            set v
        }]
        set rowids [$self Insert $index {*}$values]
        foreach name $names rowid $rowids {
            if {$name ne ""} {  ;# ??
                $self rowconfigure $rowid -name n$name
            }
        }
        return $rowids  ;# not names, because we haven't shimmed ::tablelist::rowIndex
    }

    method mousecell {} {
        foreach {x y} [winfo pointerxy $win] {}
        incr x [expr {-[winfo rootx $win]}]
        incr y [expr {-[winfo rooty $win]}]
        $self containingcell $x $y
       # lassign [split [$self cellindex @$x,$y] ,] y x
       # set y [$self rowcget $y -name]
       # return "$y,$x"
       # [self findcolumnname $x]
       # $self cellindex @$x,$y  ;# WARNING: this is indices!
    }

    method activecell {} {
        $self cellindex active
    }

    method selected {} {
        set cellsel [$self curcellselection]
        set xs [lmap xy $cellsel {lindex [split $xy ,] 1}]
        set xs [lsort -uniq $xs]
        set xs [llength $xs]
        if {$xs eq [$self columncount]} {
            $self Get [$self curselection]
        } else {
            lgroup [$self getcells $cellsel] $xs
        }
    }

    method Activate {what} {
        debug assert {$what in {active mouse}}  ;# activecell mousecell
        set cell [$self ${what}cell]
        #puts "Activated [$self getcells $cell]"
        if {$options(-command) ne ""} {
            set script [$self CmdSub $options(-command) $cell]
            after idle [list after 0 $script]
        }
    }

    method CmdSub {script cellIndex} {
        set W $self
        lassign [split $cellIndex ,] j i
        lassign [winfo pointerxy $win] x y
        # FIXME: check xyXY
        set X [expr {$x+[winfo rootx $win]}]
        set Y [expr {$y+[winfo rooty $win]}]
        set V [$self get $j $i]
        set N [$self rowcget $j -name]
        set N [string range $N 1 end]
        set C [$self columncget $i -title]
        set % %%
        foreach var [info locals ?] {
            dict set map %$var [list [set $var]]
        }
        string map $map $script
    }
}

snit::widgetadaptor edittable {

    # maintaining an always-blank row for adding entries?
    option -editcommand -default {debug log {Edit:}}
    option -addcommand -default {debug log {Add:}}
    option -delcommand -default {debug log {Delete:}}
    option -columns -default {} -configuremethod SetOpt

    delegate option * to hull
    delegate method * to hull

    constructor args {
        installhull using easytable
        $self configure -editselectedonly true
        $self configure -editstartcommand [list $self EditStart]
        $self configure -editendcommand   [list $self EditEnd]
        #$self configure -titlecolumns 1
        $self configurelist $args
        $self Editable
    }

    method SetOpt {name value} {
        switch $name {
            -columns {
                #$hull configure -columns $value  ;# propagate the change to hull
                $hull configure -columns [linsert $value 0 ""]  ;# implicit column 0
                $hull configure -titlecolumns 1
                $hull columnconfigure 0 -width 1 -labelcommand [list $self AddEvent]
                after idle [list after 0 [list $self Editable $value]]
            }
            default {
                error "Unknown option: $name"
            }
        }
        set options(-columns) $value
    }

    # deal with the icky implicit column 0
    method insert {index args} {
        set args [join [lmap {a b} $args {
            list $a [list "" {*}$b]
        }]]
        set keys [$hull insert $index {*}$args]
        set j 0
        foreach row $keys {
            $hull cellconfigure ${row},0 -window [list $self DelButton] -stretchwindow true
        }
    }
    method set args {
        if {[llength $args] != 3} {
            tailcall $hull set {*}$args
        } else {
            lassign $args j i value
            incr i
            $hull set $j $i $value
        }
    }
    method get args {
        if {[llength $args] != 3} {
            tailcall $hull get {*}$args
        } else {
            lassign $args j i value
            incr i
            $hull get $j $i $value
        }
    }

    method DelButton {tl row col w} {
        button $w -padx 0 -pady 0 -width 1 -height 1 -takefocus 0 -text "X" -command [list $self DelEvent $row]
        return $w
    }
    method AddEvent {tl col} {
        uplevel #0 $options(-addcommand)
    }
    method DelEvent {row} {
        set rowid [$hull rowcget $row -name]
        set rowid [string range $rowid 1 end]
        uplevel #0 $options(-delcommand) $rowid
    }

    method Editable args {
        set ncols [$self columncount]
        for {set i 1} {$i < $ncols} {incr i} {
            $self columnconfigure $i -editable true
        }
    }

    method EditStart {tl row col value} {
        variable OrigVal
        set OrigVal $value
        return $value
    }
    method EditEnd {tl row col value} {
        variable OrigVal
        set rowid [$self rowcget $row -name]
        set rowid [string range $rowid 1 end]
        set colname [$self columncget $col -title]
        try {   ;# FIXME: this is a bit presumptuous
            uplevel #0 $options(-editcommand) [list $rowid $colname $OrigVal $value]
        } on break {} {
            $win cancelediting
            return ""
        } on return {v o} {
            set value $v
        }
        unset OrigVal
        return $value
    }
}

# tableedit .q -table regex -key rowid -columns {pattern category}
#   -where {sqlcond}
#   -highlight {rowexpr}
snit::widgetadaptor tableedit {
    option -db
    option -table
    option -key
    option -columns
    option -where -default 1
    option -query -default ""
    delegate option * to hull
    delegate method * to hull
    constructor args {
        installhull using edittable
        $hull configure -addcommand [list $self Add]
        $hull configure -delcommand [list $self Del]
        $hull configure -editcommand [list $self Edit]
        $self configurelist $args
    }
    method Add {} {
        debug log {$self Add}
    }
    method Del {rowid} {
        debug log {$self Del $rowid}
    }
    method Edit {rowid column prev value} {
        debug log {$self Edit $rowid $column $value <- $prev}
    }
    method SqlSelect {} {
        if {$options(-query) ne ""} {
            return $options(-query)
        }
        return [Sql select $options(-table) [list $options(-key) {*}$options(-columns)] $options(-where)]
    }
    method refresh {} {
        $hull delete 0 end
        $hull configure -columns $options(-columns)
        $options(-db) eval [$self SqlSelect] row {
            $hull insert end $row($options(-key)) [
                lmap c $options(-columns) {set row($c)}
            ]
            # highlight? apply rowstyle?
        }
        # restore sorting?
    }
    method delete {rowid} {
        $options(-db) eval [Sql delete $options(-table) $options(-key) $rowid
    }
    method update {rowid args} {
        $options(-db) eval [Sql update $table $args [list $options(-key) $rowid]]
    }
}

tests {
    if 0 {
        pack [edittable .t] -fill both -expand yes
        wm deiconify .
        .t columns "left middle right"
        .t insert end english {one two three}
        .t insert end deutsch {eins zwei drei} thai {nung song sarm}
        .t set english 1 TWO
    } else {
        package require sqlight
        Sqlite create sqlite ../../../aeu_20150427.db
        puts aa
        set cols [sqlite columns foo]
        puts oo
        pack [tableedit .t -table foo -key rowid -columns $cols -db sqlite] -fill both -expand yes
        puts ok
        .t refresh
        package require repl
        coroutine mainrepl repl::chan stdin stdout
    }
}
