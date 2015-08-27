# this is derived from NEM's excellent series on the wiki, which follows Hutton's lovely paper
#
package require fun

pkg -export * monads {

    alias abstract error "implementation required!"

    # self-describing types
    proc ctor {name args} {
        tailcall proc $name $args {info level 0}
        tailcall alias $name list $name ;# doesn't enforce args
    }

    # simple pattern matching
    proc Match {pattern arg} {
        set res {}
        foreach a $arg p $pattern {
            if {[string match {[a-z]*} $p]} {
                dict set res $p $a
            } elseif {$p ne $a} {
                return false
            }
        }
        dict for {_v v} $res {
            uplevel 1 [list set $_v $v]
        }
        return true
    }

    # .. in a monad
    proc matchM {m a cases} {
        lappend     cmd     if 0 {}
        foreach {pattern body} $cases {
            lappend cmd     elseif \[[list Match $pattern $a]\] $body
        }
        lappend     cmd     else {error "cases exhausted!"}
        tailcall try $cmd
    }


    ensemble -export * Monad {
        proc ret a      abstract
        proc >>= {m f}  abstract
        proc fail {{reason "no reason"}} {
            error "monad fail: $reason"
        }
        proc plus {a b} abstract
        proc zero {}    abstract
        proc bind {a _v body} { ;# brute-force bind: the default
            >>= $a [uplevel 1 [list func $_v $body]]
        }
    }

    proc bindM {m a _v body} {   ;# brute-force bind for default use
        $m >>= $a [uplevel 1 [list func $_v $body]]
    }

    proc monad {name constructors body} {
        foreach c $constructors {
            uplevel 1 ctor $c
        }
        foreach {cmd proxy} {
                    do doM bind bindM match matchM
                } { ;# trampoline commands
            puts "alias ${name}::$cmd [namespace which $proxy]"
            set body "[list alias $cmd [namespace which $proxy] $name]; $body"
        }
        # {>>= ret fail plus zero bind do}
        tailcall ensemble -path [namespace which Monad] -export * $name $body
    }

    proc mapM {m f xs} { 
        $m bind $xs x {
            $m ret [uplevel 1 $f $x]
        }
    }
    proc filterM {m f xs} {
        $m bind $xs x {
            if {[uplevel 1 $f $x]} {
                $m ret $x
            } else fail
        }
    }

    # 
    proc doM {m script} {
        set lines [split $script \;]
        set lines [map {string trim} $lines]
        set lines [lfilter {string length} $lines]
        set lines [lassign [lreverse $lines] body]
        foreach line $lines {
            if {[regexp {(.*)<-(.*)} $line -> var comp]} {
                set body [format {%s >>= %s [func %s %s]} $m $comp [list [list $var]] [list $body]]
            } else {
                set body [format {%s >>= %s [func %s %s]} $m $line _                  [list $body]]
            }
        }
        tailcall try $body
    }

    monad List {} {
        proc ret a    {list $a}
        proc >>= {m f} {
            concat {*}[lmap el $m {uplevel 1 $f [list $el]}]
        }
        proc bind {m _v body} {
            #tailcall lolcat $_v $m $body
            concat {*}[uplevel 1 [list lmap $_v $m $body]]
        }
        proc fail r     {list}
        proc zero {}    {list}
        proc plus {a b} {concat $a $b}
    }

    monad Maybe {{Just a} Nothing} {
        proc ret a    {Just $a}
        proc >>= {m f} {
            set v [lassign $m con]
            if {$con eq "Nothing"} {
                Nothing
            } else {
                uplevel 1 $f $v
            }
        }
        proc bind {m _v body} {
            set v [lassign $m con]
            if {$con eq "Nothing"} {
                Nothing
            } else {
                uplevel 1 [list set $_v $v]
                tailcall try $body
            }
        }
        proc *>>= {m f} {
            set v [lassign $m con]
            switch $con {
                Nothing { Nothing }
                Just    { uplevel 1 $f $v }
            }
        }
        proc fail r     { Nothing }
        proc zero {}    { Nothing }
        proc plus {a b} {
            set v [lassign $a con]
            switch $con {
                Nothing { return $b }
                Just    { return $a }
            }
        }
    }

    monad Tree {Empty {Leaf a} {Branch l r}} {
        proc ret a    { Leaf $a }
        proc >>= {m f} {
            set v [lassign $m con]
            switch $con {
                Empty   { Empty }
                Leaf    { uplevel 1 $f $v }
                Branch  {
                    lassign $v l r
                    Branch [>>= $l $f] [>>= $r $f]
                }
            }
        }
        proc fail s     { Empty }
        proc zero {}    { Empty }
        proc plus {a b} { Branch $a $b }
    }


    # following Hutton & Meijer (and nem!)
    monad Parser {{Parse f}} {
        proc parse {m s} {
            lassign $m p cmd
            debug assert {$p eq "Parse"}
            uplevel 0 $cmd [list $s]
        }
        proc ret {a} {
            Parse [func {cs} {list $a $cs}]
        }
        proc zero {} {
            Parse [func {cs} {list}]
        }
        proc item {} {
            Parse [func {cs} {
                if {$cs ne ""} {
                    list [string range $cs 0 0] [string range $cs 1 end]
                }
            }]
        }
        proc >>= {m f} {
            Parse [func {cs} {
                concat {*}[lmap {a ccs} [parse $m $cs] {
                    parse [uplevel #0 $f [list $a]] $ccs
                }]
            }]
        }
        proc plus args {    ;# n-ary plus!
            Parse [func {cs} {
                concat {*}[lmap m $args {
                    parse $m $cs
                }]
            }]
        }
        proc || args {   ;# deterministic version
            Parse [func {cs} {
                foreach m $args {
                    set r [parse $m $cs]
                    if {$r ne ""} {return $r}
                }
            }]
        }
        proc const a {
            Parse [func cs { return $a }]
        }
        proc lit {l} {
            set len [string length $l]
            Parse [func {cs} {
                if {[string equal -length $len $l $cs]} {
                    list $l [string range $cs $len end]
                }
            }]
        }
        proc litNC {l} {
            set len [string length $l]
            Parse [func {cs} {
                if {[string equal -nocase -length $len $l $cs]} {
                    list $l [string range $cs $len end]
                }
            }]
        }
        proc sat {p} {  ;# tying the knot with [do]
            do {
                c <- [item];
                if {[uplevel #0 $p [list $c]]} {
                    ret $c
                } else {
                    zero
                }
            }
        }
        proc many {p} {
            || [many1 $p] [zero]
        }
        proc many1 {p} {
            do {
                a <- $p;
                as <- many $p;
                ret [concat [list $a] $as]
            }
        }
        proc * {p} {
            >>= [many $p] [func cs {
                ret [join $xs]
            }]
        }
        proc + {p} {
            >>= [many $p] [func cs {
                ret [join $xs]
            }]
        }
        proc sepby {p sep} {
            || [sepby1 $p $sep] [zero]
        }
        proc sebby1 {p sep} {
            do {
                a <- $p;
                as <-  many [>>= $sep [func cs {ret $p}]
                ret [concat [list $a] $as]
            }
        }
        proc chainl {p op a} {
            || [chainl1 $p $op] [Parser ret $a]
        }
        proc chainl1 {p op} {
            do {
                $a <- $p;
                rest $a $p $op
            }
        }
        proc rest {a p op} {
            || [do {
                f <- $op;
                b <- $op;
                rest [uplevel #0 $p [list $a $b] $p $op]
            }] [ret $a]
        }

        proc space {} {
            many [sat {string is space}]
        }
        proc token {p} {
            do { a <- $p; space; ret $a }
        }
        proc apply {p} {    ;# skip any leading space
            do { space; $p }
        }

    }
    namespace eval Parser {namespace export *}

    proc Capture {{level 1} {names ""}} {
        if {[string is integer $level]} {incr level}
        if {$names eq ""} {
            set names [uplevel $level {info vars}]
        }
        set res ""
        foreach name $names {
            ;# no arrays, no error on nonexistent or trace-hobbled vars
            catch {dict set res $name [uplevel $level [list set $name]]}
        }
        return $res
    }

    proc func {params body {ns ""}} {
        if {$ns eq ""} {
            set ns [uplevel 1 {namespace current}]
        }
        set env [Capture 1]
        set params [concat [dict keys $env] $params]
        set args   [dict values $env]
        list apply [list $params $body $ns] {*}$args
    }


}

if {[info exists ::argv0] && $::argv0 eq [info script]} {

        proc mtest {m xs ys} {
            $m >>= $xs [func x {
                $m >>= $ys [func y {
                    $m ret ($x,$y)
                }]
            }]
        }
        proc mtestb {m xs ys} {
            $m bind $xs x {
                $m bind $ys y {
                    $m ret ($x,$y)
                }
            }
        }
        set a [list 1 2 3]
        set b [list a b]

        debug assert { [mtest List $a $b]
                    eq "(1,a) (1,b) (2,a) (2,b) (3,a) (3,b)"}

        proc msquare {m x} { $m ret [expr {$x*$x}] }
        debug assert { [mtest List [List >>= $a {msquare List}] $b]
                    eq "(1,a) (1,b) (4,a) (4,b) (9,a) (9,b)"}

        debug assert {[mtest Maybe [Nothing]  [Nothing]]    eq "Nothing"}
        debug assert {[mtest Maybe [Just 1]   [Nothing]]    eq "Nothing"}
        debug assert {[mtest Maybe [Nothing]  [Just a]]     eq "Nothing"}
        debug assert {[mtest Maybe [Just 1]   [Just a]]     eq "Just (1,a)"}

        debug assert { [mtest Maybe [Maybe >>= [Just 3] {msquare Maybe}] [Just b]]
                    eq "Just (9,b)"}
        proc dotest {m a b} {
            $m do { x <- $a; y <- $b; $m ret ($x,$y) }
        }
        debug assert {[dotest List {1 2 3} {a b}] eq "(1,a) (1,b) (2,a) (2,b) (3,a) (3,b)"}
        debug assert {[dotest Maybe [Just a] [Nothing]] eq "Nothing"}
        debug assert {[List do { x <- {1 2 3 4 5} ; if {$x%2 == 0} { List ret $x }}] eq "2 4"}
        proc except {ls args} {ldiff $ls $args}
        # see http://blog.plover.com/prog/haskell/monad-search.html
        # and http://blog.plover.com/prog/monad-search-2.html
        # .. this is very very slow :-(
        proc smm {} {
            set digits {0 1 2 3 4 5 6 7 8 9}
            List do {
                s <- [except $digits 0];
                e <- [except $digits $s];
                n <- [except $digits $s $e];
                d <- [except $digits $s $e $n];
                m <- [except $digits 0 $s $e $n $d];
                o <- [except $digits $s $e $n $d $m];
                r <- [except $digits $s $e $n $d $m $o];
                y <- [except $digits $s $e $n $d $m $o $r];
                set send $s$e$n$d
                set more $m$o$r$e
                set money $m$o$n$e$y
                puts "$send + $more = $money"
                if {$send + $more != $money} {List fail -}
                List ret [list $send $more $money]
            }
        }
}
