# functional-style-programming stuff
#
# the sort of things that belong in _.tcl, I guess
#
# For a list of lists:
#   [join $lol] eq [concat {*}$lol]
#
package require Tcl 8.6

package require options

namespace eval fun {

    proc K {a args} {set a}
    proc -- args {}    ;# pseudo-comment

    -- too raunchy?
    -- proc sex {name value} {
        tailcall try [format {
            set %s [expr {%s}]
        } [list $name] $value]
    }


    #package require lambda
    # copied straight out of tcllib, to avoid the dependency
    ## Originally (C) 2011 Andreas Kupries, BSD licensed.
    proc lambda {arguments body args} {
        list ::apply [list $arguments $body] {*}$args
    }
    proc lambda@ {namespace arguments body args} {
        list ::apply [list $arguments $body $namespace] {*}$args
    }

    ##namespace import ::tcl::mathop::*
    #namespace import ::tcl::mathfunc::*
    namespace path ::tcl::mathfunc

    # convenience function for printing lists (handy for debugging!)
    proc putl {args} {
        puts $args
    }

    proc callback {args} {
        tailcall namespace code $args
    }

    # max and min should be able to take list arguments!
    proc max {args} {
        tailcall ::tcl::mathfunc::max {*}[concat {*}$args]
    }
    proc min {args} {
        tailcall ::tcl::mathfunc::min {*}[concat {*}$args]
    }
    
    # this is a useful enough alias to preserve
    proc maxlen {ss} {
        max {*}[map {string length} $ss]
    }

    # and this is handy
    proc common_prefix {strings} {
        set model [lpop strings]
        for {set i 0} {$i < [string length $model]} {incr i} {
            set pattern [string range $model 0 $i]*
            if {![all {string match $pattern} $strings]} {
                return [string range $model 0 $i-1]
            }
        }
        return $model
    }

    # mimic's textutil::adjust::undent
    proc undent {text} {
        set pres [regexp -inline -all -linestop -lineanchor {^.*?(?=\S)} $text]
        set pre [common_prefix $pres]
        regsub -all -linestop -lineanchor "^$pre" $text "" text
        set text [string trimleft $text \n]
        set text [string trimright $text " \t"]
        return $text
    }


    # local aliases that respect namespaces
    proc alias {alias cmd args} {
        if {![string match ::* $alias]} {
            set alias [uplevel 1 {namespace current}]::$alias
        }
        if {![string match ::* $cmd]} {
            set c [uplevel 1 [list namespace which $cmd]]
            if {$c eq ""} {
                return -code error "Could not resolve $cmd!"
            }
            set cmd $c
        }
        tailcall interp alias {} $alias {} $cmd {*}$args
    }

    proc unalias {args} {
        foreach cmd $args {
            interp alias {} [uplevel 1 [list namespace which $cmd]] {}
        }
    }

    namespace import ::tcl::prefix

    # create an ensemble in one step
    proc ensemble args {
        set args [lreverse [lassign [lreverse $args] script name]]
        array set opt {
                -export     {{[a-z]*}}
                -parameters {}
                -prefixes   1
                -unknown    {}
                -path       {}
        }       ;#"
        set names [array names opt]
        foreach {o value} $args {
            set opt([prefix match $names $o]) $value
        }
        append script {; namespace path }   $opt(-path)
        append script {; namespace export } $opt(-export)
        append script {; namespace ensemble create}
        append script { } [list -parameters $opt(-parameters)]
        append script { } [list -prefixes   $opt(-prefixes)]
        append script { } [list -unknown    $opt(-unknown)]
        tailcall namespace eval $name $script
    }

    # resolve ?level? name -- (from toot)
    #      Returns the fully-qualified name of $name resolved relative to
    #      $level on the current call stack.
    #
    proc resolve args {
        if {$args eq "" || [llength $args] > 2} {
            throw {TCL WRONGARGS} "wrong # args: should be \"?level? name\""
        }
        if {[llength $args] == 2} {
            lassign $args level name
        } else {
            lassign $args name
            set level 0
        }
        incr level
        if {![string match ::* $name]} {
            set ns [uplevel $level { namespace current }]
            if {$ns eq "::"} {
                set name ::$name
            } else {
                set name ${ns}::$name
            }
        }
        return $name
    }
 
    # return the subcommands of an ensemble or an object as a list - see procmap::ens_map
    proc subcommands {command} {
        set cmd [uplevel 1 [list namespace which $command]]
        if {$cmd eq ""} {
            return -code error "$command is not a command!"
        }
        if {[info object isa object $cmd]} {
            return [info object methods $cmd -all]
        }
        # order of priority described in namespace(n):
        foreach try {
            {namespace ensemble configure $cmd -subcommands}
            {dict keys [namespace ensemble configure $cmd -map]}
            {   set ns [namespace ensemble configure $cmd -namespace]
                concat {*}[lmap pattern [namespace eval $ns {namespace export}] {
                    lmap c [info commands ${ns}::$pattern] {
                        namespace tail $c
                    }
                }]
            }
        } {
            if {[set res [try $try]] ne ""} {
                return $res
            }
        }
        return -code error "$cmd is not a namespace ensemble or object!"
    }

    # cd with automatic return
    proc indir {dir script} {
        set return [list ::cd [pwd]]
        cd $dir
        tailcall try $script finally $return
    }


    # we can't import ::readfile in safe interps created by interps-0.tm, so check for it:
    if {[namespace which -command ::readfile] eq ""} {
        proc readfile args {
            options {-oflags RDONLY} {-encoding utf-8} {-translation auto} {-eofchar ""}    ;# sensible defaults
            arguments {filename}

            set fd [open $filename $oflags]
            fconfigure $fd -encoding $encoding -translation $translation -eofchar $eofchar

            try {
                read $fd
            } finally {
                close $fd
            }
        }
    }

    proc writefile args {
        options {-oflags {WRONLY CREAT}} {-encoding utf-8} {-translation auto} {-eofchar ""}    ;# sensible defaults
        arguments {filename data}

        # always mkdir - some vfs's don't respond well if we don't
        file mkdir [file dirname $filename]

        set fd [open $filename $oflags]
        fconfigure $fd -encoding $encoding -translation $translation -eofchar $eofchar

        try {
            puts -nonewline $fd $data
        } finally {
            close $fd
        }
    }

    # ensures that $path is under $top (modulo symlinks - use [file normalize] for those)
    proc path_contains {top path} {
        # exact match is okay:
        if {$path eq $top} {
            return true
        }
        append top /
        set len [string length $top]
        # adjacent similarly-named directory is not okay
        if {[string compare -length $len $top $path]} {
            return false
        }
        # ensure no escape with ..
        set path [string range $path $len end]
        set depth 0
        foreach part [file split $path] {
            if {$part eq ".."} {
                incr depth -1
                if {$depth < 0} {return false}
            } else {
                incr depth
            }
        }
        # otherwise, it's safe!
        return true
    }


    proc divmod {a b} {
        list [expr {$a/$b}] [expr {$a % $b}]
    }

    # incrmod 10 i ?1?
    proc incrmod {m _n {i 1}} {
        upvar 1 $_n n
        set n [expr {($n + $i) % $m}]
    }


    # 19 chars
    proc isodate args {
        options {-dateonly}
        arguments {{time {}}}
        if {$time eq ""} {
            set time [clock seconds]
        }
        if {![string is integer $time]} {
            set time [clock scan $time]
        }
        set fmt "%Y-%m-%d"
        if {!$dateonly} {
            append fmt " %H:%M:%S"
        }
        clock format $time -format $fmt
    }
 
    # 10 chars max
    proc format_size {size} {
        if {$size < 1e6} {
            return "[commaify [expr {$size}]] B "
        } elseif {$size < 1e9} {
            return "[commaify [expr {$size/1000}]] KB"
        } elseif {$size < 1e12} {
            return "[commaify [expr {$size/1000000}]] MB"
        } elseif {$size < 1e15} {
            return "[commaify [expr {$size/1000000000}]] GB"
        } elseif {$size < 1e18} {
            return "[commaify [expr {$size/1000000000000}]] TB"
        } elseif {$size < 1e21} {
            return "[commaify [expr {$size/1000000000000000}]] PB"
        }
    }

    # http://wiki.tcl.tk/26079
    proc yieldm {{value {}}} {
        yieldto string cat $value
    }

    proc func args {
        set expr [lindex $args end]
        set args [lrange $args 0 end-1]
        tailcall proc {*}$args [list expr $expr]
    }

    # helper for composing scripts:
    proc script {args} {
        join [lmap a $args {concat {*}$a}] \;
    }

    # helper to make quoting less odious
    if {[info commands Uplevel] eq ""} {
        proc Uplevel {n args} {tailcall uplevel $n $args}
    }

    # copied from [info body parray]
    proc pdict {d} {
        if {[dict size $d] eq 0} return
        set maxl [::tcl::mathfunc::max {*}[map {string length} [dict keys $d]]]
        ;# [dict for] doesn't see duplicate elements, but I want to:
        foreach {key value} $d {
            puts stdout [format "%-*s = %s" $maxl $key $value]
        }
    }

    # for binding multiple values.  Equivalent to [foreach {*}$args break]
    # the assert is a normally-very-useful static check.
    # this could evolve into a nice full destructuring bind ...
    # for which, see http://www.cs.berkeley.edu/~bh/ssch16/match.html
    # (or wiki on Unification and Algebraic Data Types)
    proc mset args {
        debug assert {[all [lmap {a b} [map {llength} $args] {expr {$a == $b}}]]}
        tailcall foreach {*}$args break
    }

    # aka [range].  Args are actually {{x 0} y+1}
    #interp alias {} iota {} range
    proc range {a {b ""}} {
        if {$b eq ""} {
            set b $a
            set a 0
        }
        for {set r {}} {$a<$b} {incr a} {
            lappend r $a
        }
        return $r
    }

#    proc index {list} {
#        range [llength $list]
#    }

    proc indexed {list} {
        set i -1
        concat {*}[lmap {x} $list {
            list [incr i] $x
        }]
    }

    # this is generally useful.
    # with multiple arguments it is equivalent to:
    #   [concat {*}[lmap ...]]
    # which under some circumstances can be thought of as:
    #   [join [lmap ...] " "]
    # the pattern comes up a lot.
    # Alternative names:  [lconcat] [ljoin] [lmap*]  (last conflicts with foreach*)
    proc lconcat args {
        concat {*}[uplevel 1 lmap $args]
    }

    # Most simply, when you want to map a list but return multiple values from the body,
    # such as to create a dict:
    # demonstrative usage:
    #   % pdict [dictify {tcl::pkgconfig get} [tcl::pkgconfig list]]
    #interp alias {} mapwith {} dictify
    proc dictify {cmdPrefix ls} {
        lconcat x $ls {
            list $x [uplevel 1 $cmdPrefix [list $x]]
        }
    }

    proc uniq {args} {
        set res ""
        foreach x [concat {*}$args] {
            if {$x ni $res} {lappend res $x}
        }
        return $res
    }

    proc ldiff {a b} {
        lmap elem $a { expr {$elem in $b ? [continue] : $elem} }
    }

    proc union {a b} {
        concat $a [lmap x $b {
            if {$x in $a} continue
            set x
        }]
    }

    proc intersect {a b} {
        lmap x $a {
            if {$x ni $b} continue
            set x
        }
    }

    # With 3+ arguments, this should be more like
    #  lmap $1 $2 [list expr $3]
    proc lfilter args {
        switch [llength $args] {
            2 {
                tailcall lfilter/2 {*}$args
            }
            1 - 0 {
                return -code error "Incorrect arguments!  Expected \"cmdPrefix ls\" or lmap-args"
            }
            default {
                tailcall lfilter/3 {*}$args
            }
        }
    }
    proc lfilter/3 {_xs list expr} {
        if {[llength $_xs] == 1} {  ;# should be faster
            tailcall lmap $_xs $list "
                if {!($expr)} continue
                set [list $_xs]
            "
        }
        tailcall lconcat $_xs $list [list if $expr [list map set $_xs] else continue]
    }
    proc lfilter/2 {cmdPrefix ls} {
        lmap x $ls {
            if {![uplevel 1 $cmdPrefix [list $x]]} continue
            set x
        }
    }

    proc lremove {_ls args} {
        # tkcon's has options -all -glob -regexp, but doesn't use them
        set script [cmdpipe [list set $_ls] {*}[map {list lsearch -exact -not -all -inline ~} $args] [list set $_ls]]
        tailcall try $script

        # naive version:
        upvar 1 $_ls ls
        foreach a $args {
            set ls [lsearch -exact -not -all -inline $ls $a]
        }
    }

    proc lrot {ls {n 1}} {
        set l [llength $ls]
        set n [expr {$n % $l}]
        set tail [lrange $ls $n end]
        set head [lrange $ls 0 $n-1]
        concat $tail $head
    }

    # pop 1 or more items from the start of a list (into named args).  Returns last item popped.
    -- proc lpop {_ls args} {
        upvar 1 $_ls ls
        if {$args eq ""} {
            set ls [lassign $ls x]
            return $x
        }
        tailcall try [script {*}[lmap a $args {
            list set [list $a] \[[list lpop $_ls]\]
        }]]
    }

    # for symetry, lpop needs lpush
    interp alias {} lpush {} lappend

    # pop items off the beginning of a list.
    # single argument form returns the item popped
    # multi-arg form assigns to varNames, returning the remaining list.
    proc lpop {_ls args} {
        if {$args eq ""} {
            upvar 1 $_ls ls
            set ls [lassign $ls x]
            return $x
        }
        tailcall try [format {
            set %1$s [lassign $%1$s %2$s]
        } [list $_ls] $args]
    }

    # lshift listName ?count?
    # Removes and returns the first $count (default 1) items from $list.
    proc lshift {_ls {n 1}} {
        upvar 1 $_ls ls
        if {![llength $ls]} {
            return -code error "Attempted lshift of empty list!"
        }
        if {$n == 1} {
            set res [lindex $ls 0]
        } else {
            set res [lrange $ls 0 [expr {$n-1}]]
        }
        set ls  [lrange $ls $n end]
        return $res
    }
 
    # cheap options: consume all {-key val}
    # pairs off the beginning of $args
    proc getopts {_args} {
        upvar 1 $_args args
        set opts {}
        while {[string match -* [lindex $args 0]]} {
            # FIXME?: stop at --
            lappend opts {*}[lshift args 2]
        }
        return $opts
    }


    # from http://core.tcl.tk/tcl/tktview?name=0d2bcd9544
    proc lgroup {listIn lengthOfSublist} {
        set i 0
        foreach it $listIn {
            lappend tmp $it
            if {[llength $tmp] == $lengthOfSublist} {
                lappend result $tmp
                set tmp {}
            }
            incr i
        }
        if {[llength $listIn] % $lengthOfSublist} {
            lappend result $tmp
        }
        return $result
    }

    # http://core.tcl.tk/tcl/tktview?name=a95309bf70
    # % lselect {a {b c {d e}} f {g h}} {1 1} 1 3 {1 2 0}
    # c {b c {d e}} {g h} d
    proc lselect {list args} {
        map {lindex $list} $args
    }

    proc lswap {list i j} {
        set x [lindex $list $i]
        set y [lindex $list $j]
        lset list $j $x
        lset list $i $y
        return $list
    }

    # like [string replace], but with index semantics of [lreplace]
    # so it can replace empty strings in the string
    proc sreplace {s first last args} {
        # naive implementation, using lreplace directly:
        set l [split $s ""]
        set args [lmap a $args {split $a ""}]
        set l [lreplace $l $first $last {*}$args]
        return [join $l ""]
        # a little smarter is actually full of edge conditions, since indexes aren't treated uniformly:
        if {$last < $first} {
            string insert $s $first {*}$args
        }
    }

    # adapted from http://wiki.tcl.tk/3603
    proc do {body keyword expr} {
        switch -exact $keyword {
            while {
                set expr !($expr)
            }
            until {
            }
            default {
                return -code error "unknown keyword \"$keyword\": must be until or while"
            }
        }
        tailcall while 1 "
            $body
            [list if $expr break]
        "
    }

    proc until {cond body} {
        tailcall while !($cond) $body
    }

    # following TclX
    # .. I want to extend this to multiple arguments, maybe to map/fold, but thataway lies
    # lisp's (loop), which is madness
    proc loop {_var first limit args} {
        # arguments {_var first limit {incr 1} script}
        switch [llength $args] {
            1 {
                set incr 1
                lassign $args script
            }
            2 {
                lassign $args incr script
            }
            default {
                error "Invalid arguments"
            }
        }
        set first [uplevel 1 [list expr entier($first)]]
        set limit [uplevel 1 [list expr entier($limit)]]
        set cond [expr {$incr > 0 ? "<" : ">"}]
        tailcall for [
                    list set $_var $first
            ] [
                        string cat "\${$_var} $cond $limit"
            ] [
                            list incr $_var $incr
            ] $script
    }

    # map {uplevel 1} [lrepeat $n $script] !
    # oh it gets even better.  You can write that:
    #  interp alias {} repeat {} {*}[compose {map {uplevel 0}} {lrepeat}]
    proc repeat {n script args} {
        set script [concat $script {*}$args]
        set res {}
        loop i 0 $n {
            lappend res [uplevel 1 $script]
        }
        set res
    }

    # I don't really use this
    proc counting {_var args} {
        set script [lindex $args end]
        set args [lreplace $args end end]
        arguments {{initial 0} {increment 1}}
        uplevel 1 [list set $_var $initial]
        set suffix [list incr $_var $increment] 
        return "$script; $suffix"
    }

    proc gensym {{prefix gensym#}} {
        string cat $prefix [uplevel 1 [list info commands $prefix*]]
    }

    # FIXME:  the >2-arg form should take one cmdPrefix and many lists.
    # all ?cmdPrefix ..? $ls
    proc all {args} {
        set ls [lindex $args end]
        set cmd [lrange $args 0 end-1]
        if {$cmd eq ""} {
            set cmd K
        }
        foreach x $ls {
            if {![uplevel 1 {*}$cmd [list $x]]} {return false}
        }
        return true
    }

    # FIXME:  the >2-arg form should take one cmdPrefix and many lists.
    # any ?cmdPrefix ..? $ls
    proc any {args} {
        set ls [lindex $args end]
        set cmd [lrange $args 0 end-1]
        if {$cmd eq ""} {
            set cmd K
        }
        foreach x $ls {
            if {[uplevel 1 {*}$cmd [list $x]]} {return true}
        }
        return false
    }

    # Thanks RS: http://wiki.tcl.tk/3361
    proc forall {name set cond} {
        all [uplevel 1 [list lmap $name $set $cond]]
    }
    proc exists {name set cond} {
        any [uplevel 1 [list lmap $name $set $cond]]
    }

if 0 {
    #  .. be careful with keyword arguments ...
    proc if* {subst cond cons args} {
        set cmd [list if $cond [list $subst $cons]]
        foreach {kw cond body} $args {
            if {$kw eq "else"} {
                lappend cmd $kw [list $subst $cond]
            } else {
                lappend cmd $kw $cond [list $subst $body]
            }
        }
        tailcall {*}$cmd
    }
    interp alias {} sif {} if* ::subst  ;# substing-if
    interp alias {} eif {} if* ::expr   ;# expr-if
    #interp alias {} ?:  {} if* ::expr   ;# aka ?:
}
    proc ?: {cond args} {
        tailcall ::if $cond {*}[map {list string cat} $args]
    }

    # transposes its list arguments, by translating to an [lmap] call.
    # Length of longest arg governs length of result.
    proc zip {args} {
        set names [range [llength $args]]
        set forArgs [lconcat n $names a $args {list $n $a}]
        set cmdArgs [lconcat name $names {string cat \$ $name}]
        set body "list $cmdArgs"
        lmap {*}$forArgs $body
    }

    proc zip! {args} {
        debug assert {[== [map {llength} $args]]}
        tailcall zip {*}$args
    }

    proc transpose {lol} {
        # zip {*}$lol
        set res {}
        set r [set c -1]
        foreach row $lol {
            incr r
            foreach v $row {
                incr c
                lset res $c $r $v
            }
            set c -1
        }
        return $res
    }

    # normal map, but does multiple arguments:
    #  % map {expr} {1 2 3} {+ - *} {2 4 5}
    #  {3 -2 15}
    #
    # The args are names $0,$1..  in local space - they
    # could be upvared with performance benefit, but I'm
    # not convinced about the implicit pollution.
    #
    # much simpler in this form.
    proc map {cmdPrefix args} {
        set names [range [llength $args]]
        set forArgs [lconcat n $names a $args {list $n $a}]
        set cmdArgs [lconcat name $names {string cat \$ $name}]
        set body "uplevel 1 [list $cmdPrefix] \[list $cmdArgs\]"
        lmap {*}$forArgs $body
    }

    proc map! {cmdPrefix args} {
        debug assert {[== [map {llength} $args]]}
        tailcall map $cmdPrefix {*}$args
    }

    proc fold {cmdPrefix seed args} {
        set names [range [llength $args]]
        set cmdArgs [lconcat name $names {string cat \$ $name}]
        set body "set seed \[uplevel 1 $cmdPrefix \[list \$seed $cmdArgs\]\]"
        set forArgs [lconcat n $names a $args {list $n $a}]
        foreach {*}$forArgs $body
        return $seed
    }

    proc fold! {cmdPrefix args} {
        debug assert {[== [map {llength} $args]]}
        tailcall fold $cmdPrefix {*}$args
    }

    # [lfold] is an interesting idea, but too clumsy to be useful.  I think.

    ;# this is supposed to be used with [compose]?
    proc {expand} {cmd args} {tailcall $cmd {*}[concat {*}$args]}
    ;# usage: ...

    proc swap args {
        tailcall try "
            lassign \[map {set} [list $args]\] [lreverse $args]
        "
    }

    # returns a script which composes the given list of commands:
    # this has elsewhere been called [pipe], [cmdpipe], [~>]
    proc cmdpipe args {
        set anonvar ~
        set args [lassign $args body]
        foreach cmd $args {
            if {[string first $anonvar $cmd] >= 0} {
                set body [string map [list $anonvar "\[$body\]"] $cmd]
            } else {
                set body "$cmd \[$body\]"
            }
        }
        set body
    }

    # example:
    -- {
        set s [cmdpipe {*}{
            {open /etc/passwd r}
            {read}
            {string trim}
            {split ~ \n}
            {lindex ~ end}
            {split ~ :}
            {lindex ~ 4}
            {puts}
        }]
    }

    proc compose {args} {
        set pipe [list {map set $args} {*}[lreverse $args]]
        lambda args [cmdpipe {*}$pipe]
    }
    # this does horrible things to bcc in aid of evaluating in the caller
    proc compose args {
        set marker "{*}"    ;# so we will need to subst "[{*}]", which ought to be safe
        set pipe [cmdpipe $marker {*}[lreverse $args]]
        set marker {[{*}]}
        set i0 [string first $marker $pipe]
        set pre [string range $pipe 0 $i0-1]
        incr i0 [string length $marker]
        set post [string range $pipe $i0 end]

        #set pipe [string map { {[{*}]} {{*}$args} } $pipe]
        lambda args [format {
            tailcall try [string map [list {[{*}]} $args] %s]
        } [list $pipe]]
        lambda args [concat {
            tailcall try [string map [list {[{*}]} $args] 
        } [
            list $pipe
        ] {
            ]
        }]
        lambda args "
            tailcall try \[concat [list $pre] \$args [list $post]\]
        "
    }

    -- {
        puts [map [compose {expr} {string cat 0x}] {de ad beef}]
        return
    }

    # closures from http://wiki.tcl.tk/15778
    #
    # "The odd construct with tailcall prevents further arguments making a mess"
    proc closure {script} {
        set valuemap {}
        foreach v [uplevel 1 {info vars}] {
            # catch simply avoids arrays
            if {![uplevel 1 [list array exists $v]]} {
                lappend valuemap [list $v [uplevel 1 [list set $v]]]
            }
            #catch {lappend valuemap [list $v [uplevel 1 [list set $v]]]}
        }
        set body [list $valuemap $script [uplevel 1 {namespace current}]]
        return [lambda {} [list tailcall apply $body]]
    }

    #    # this wants enhanced [arguments.tcl] supporting optargs on the left
    #    switch [llength $args] {
    #        1 {
    #            lassign $args body
    #            set vars [uplevel 1 info locals]
    #        }
    #        2 {
    #            lassign $args vars body
    #        }
    #        default {
    #            return -code error "wrong # args: should be [lindex [info level [info level]] 0] ?varList? body"
    #        }
    #    }

    # related-ish to above: capture all (or named) vars in caller's scope as a dict
    proc capture {{names ""}} {
        if {$names eq ""} {
            set names [uplevel 1 {info vars}]
        }
        set res ""
        foreach name $names {
            ;# no arrays, no error on nonexistent or trace-hobbled vars
            catch {dict set res $name [uplevel 1 [list set $name]]}
        }
        return $res
    }

    # keep evaluating: [set varName [$script]]
    # until $varName stops changing
    #
    proc fixpoint {varName script} {
        upvar 1 $varName arg
        while {[set res [uplevel 1 $script]] ne $arg} {
            set arg $res
        }
        return $res
    }

    # handy example:
    proc commaify {num} {
        fixpoint num {
            regsub -all -expanded {
                (\d)    # a digit, contiguous with
                (\d{3}) # exactly three digits, followed by
                (?!\d)  # not a digit
            } $num {\1,\2}
        }
    }
    # that's a nice hack, but a [commaify] proc requires a little more smarts to be really friendly.
    # it should support Indian commaification, and (?) have no opinion what's a digit.


    # compute the transitive closure of:
    #   r = [{*}$cmdPrefix $seed  | for seed in $r]
    # note: seed is included in the result
    #  eg: [tclose {namespace children} ::]
    # FIXME: deal better with cyclic inspections, like
    #  eg: [tclose {info class instances} ::oo::class]
    #
    proc tclose {cmdPrefix seed} {
        set stack [list $seed]
        #puts "Starting with $seed .."
        for {set i 0} {$i < [llength $stack]} {incr i} {
            set el [lindex $stack $i]
            set kids [map {tclose $cmdPrefix} [{*}$cmdPrefix $el]]
            set kids [concat {*}$kids]
            set kids [ldiff $kids $stack]   ;# avoid cycles
            lappend stack {*}$kids
            #lappend stack {*}[concat {*}[map {tclose $cmdPrefix} [{*}$cmdPrefix $el]]]
        }
        set stack
    }

    # cartesian product of a list of lists
    # adapted from http://wiki.tcl.tk/2546
    proc cprod {lol} {
        set xs {{}}
        foreach ys $lol {
            set result {}
            foreach x $xs {
                foreach y $ys {
                    lappend result [list {*}$x $y]
                }
            }
            set xs $result
        }
        return $xs
    }

    proc ssplit {str substr} {
        set res {}
        set i 0
        set n [string length $substr]
        while {[set j [string first $substr $str $i]] != -1} {
            lappend res [string range $str $i $j-1]
            set i [expr {$j + $n}]
        }
        lappend res [string range $str $i end]
    }

    proc regsplit {regex str} {
        set ix [regexp -inline -indices -all $regex $str]
        set ix [concat {*}$ix]
        set ix [list -1 {*}$ix [string length $str]]
        lmap {i j} $ix {
            if {$i >= $j} continue
            string range $str [incr i 1] [incr j -1]
        }
    }

    proc dedent {text} {
        set mindent [::tcl::mathfunc::min {*}[map {string length} [regexp -all -inline -line {^[ \t]+(?!\s)} [string trim $text]]]]
        regsub -all -line "^[string repeat " " $mindent]" $text {} text
        return $text
    }

    proc memo {_arr args} {
        upvar 1 $_arr arr
        if {![info exists arr($args)]} {
            set arr($args) [uplevel 1 $args]
        }
        return $arr($args)
    }


    # from http://wiki.tcl.tk/2891
    proc gcd_lcm {args} {
        set arg1 [lindex $args 0]
        set args [lrange $args 1 end]
        set gcd $arg1
        set lcm 1
        foreach arg $args {
            set lcm [expr {$lcm * $arg}]
            while {$arg != 0} {
                set t $arg
                set arg [expr {$gcd % $arg}]
                set gcd $t
            }
        }
        set lcm [expr {($arg1/$gcd)*$lcm}]
        return [list $gcd $lcm]
    }

    proc gcd args {lindex [gcd_lcm {*}$args] 0}
    proc lcm args {lindex [gcd_lcm {*}$args] 1}

    # a simple adaptation of gcd
    proc coprime {a args} {
        set gcd $a
        foreach arg $args {
            while {$arg != 0} {
                set t $arg
                let arg = $gcd % $arg
                set gcd $t
                if {$gcd == 1} {return true}
            }
        }
        return false
    }

    # nested foreach.
    proc foreach* {args} {
        set script [lindex $args end]
        set args [lrange $args 0 end-1]
        foreach {b a} [lreverse $args] {
            set script [list foreach $a $b $script]
        }
        tailcall {*}$script
    }

    proc chuck args {
        set args [lreverse [lassign [lreverse $args] msg code]]
        tailcall return {*}$args -code error -errorcode $code $msg
    }

    proc quote_glob {s} {
        regsub -all {[?*{}\[\]~\\]} $s {\\\0}
    }
    proc quote_regex {str} {
        regsub -all {[][$^?+*()|\\.]} $str {\\\0}
    }

    namespace export *
}

namespace import ::fun::*    ;# eeek!

package require mainscript
if {[mainscript?]} {
    #tcl::tm::path add [pwd]
    package provide fun 0
    package require tests
    tests {
        func odd? {n} {$n%2}
        func even? {n} {![odd? $n]}

        test lfilter-1 "lfilter" -body {
            lfilter even? {1 2 3 4 5 6 7 8 9}
        } -result {2 4 6 8}

        test lfilter-2 "lfilter striding" -body {
            lfilter {x y} {1 2 3 4 5 6 7 8 9 0} {$x < 5}
        } -result {1 2 3 4}

        test lremove-1 "lremove" -body {
            set ls {1 2 3 4 5 6 7 8 9}
            lremove ls 2 4 6 8
            set ls
        } -result {1 3 5 7 9}

        test map-1 "multi-arg map" -body {
            map {expr} {1 2 3} {+ - *} {2 4 5}
        } -result {3 -2 15}

        test map-level "map level" -body {
            apply {{} {
                map set {a b c} {1 2 3}
                list $a $b $c
            }}
        } -result {1 2 3}

        test map-compose-expand "map + compose level + expand" -body {
            apply {{} {
                map [compose {expand set} {lrepeat 2}] {a b c}
                list $a $b $c
            }}
        } -result {a b c}

        test compose-repeat "repeat defined using compose" -body {
            set i 0
            try [concat [compose {map {uplevel 0}} {lrepeat}] [list 12 {incr i}]]
        } -result {1 2 3 4 5 6 7 8 9 10 11 12}

        test any-1 "any short circuit" -body {
            any even? {1 3 4 yellow}
            all odd? {1 3 4 yellow}
        } -result false
        test chuck-1 "chuck?" -body {
            proc foo {} {
                chuck {BAD JUJU} "your mojo is no good!"
            }
            list [catch foo r o] $r [dict get $o -errorcode]
        } -result {1 {your mojo is no good!} {BAD JUJU}}

        test pathcontains-1 "path contains test battery" -body {
            set top [pwd]
            lappend tests ${top} ${top}a ${top}/a [string replace $top end end] [file join $top a b .. c .. ..] [file join $top a .. b .. ..]
            lmap t $tests {path_contains $top $t}
        } -result {true false true false true false}
    }
}
