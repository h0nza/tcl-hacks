namespace eval go {

    interp alias {} yieldm {} yieldto string cat
    proc -- args {}
    proc debug args {}
    -- proc debug {args} {
        set i [string repeat "  " [info level]]
        set msg [lmap s $args {uplevel 1 [list subst $s]}]
        set w [lrange [info level -1] 0 1]
        if {[string match my* $w]} {
            set c [uplevel 1 {self class}]
            set o [uplevel 1 {self}]
            set c [namespace tail $c]
            set o [namespace tail $o]
            lset w 0 [format {%s <%s>} $c $o]
        }
        set c [namespace tail [info coroutine]]
        if {$c ne ""} {set c \[$c\]}
        puts [format "D:%-40s %10s = %s" $i$w $c $msg]
    }

    # this is to workaround try's finally not being honoured in a coroutine.  Bugger.
    proc finally {script} {
        tailcall trace add variable [lindex [uplevel 1 {info locals}] 0] unset $script
    }

if 0 {
    rename ::after ::_after
    proc ::after args {
        debug {after $args :: [_after info]}
        tailcall _after {*}$args
    }
}

    # since this runs in a coroutine, and coroutines' [finally] clauses
    # may not be evaluated, we need to use an unset trace to clean up afters
    proc whenidle {script} {
        set id [after idle [info coroutine]]
        finally "after cancel $id; list"
        yieldm
        set id [after 0 [info coroutine]]
        finally "after cancel $id; list"
        yieldm
        uplevel #0 $script
    }

    #
    # A closed channel will no longer accept input, and will automatically delete itself
    # during the get which traps {GOCHAN EOF}.
    #
    oo::class create gochan {

        variable buf        ;# holds the elements currently in transit
        variable max        ;# maximum capacity.  0 = rendezvous channel.
        variable closed     ;# asynchronous closure flag.
        variable sleeping   ;# array($op in {read write}) of commands waiting on $op
        variable afters     ;# we need to clean these up on exit.  Keys only.

        constructor {{size 0}} {
            namespace path [list {*}[namespace path] ::go]
            set buf {}
            set max $size
            set closed 0

            if {$max == 0} {
                oo::objdefine [self] forward put my Put0
            } else {
                oo::objdefine [self] forward put my Put*
            }
        }

        destructor {
            debug {shutting down [self] [self namespace]}
            foreach id [array names afters] {
                debug {after cancel $id}
                after cancel $id
            }
        }

        method close {} {
            debug {[self] closing!}
            incr closed
            my notify read
            my notify write
        }

    ;# notify/subscribe mechanism
        method sub {op args} {
            if {$args eq ""} {lappend args [info coroutine]}
            if {[info exists sleeping($op)]} {
                throw {GOCHAN ERROR} "multiple subscribers not supported!"
            }
            set sleeping($op) $args
        }
        method unsub {op} {
            unset -nocomplain sleeping($op)
        }

        method waiton {op} {    debug {$op: $buf: [array get sleeping]}
            my sub $op [info coroutine]
            yield
            my unsub $op
        }

        # notify sets an [after idle after 0] callback ..
        method notify {op} {    debug {$op: $buf: [array get sleeping]}
            if {![info exists sleeping($op)]} {
                debug {Notify for $op but nobody cares .. (buf = $buf)}
                return
            }
            set cmd [go whenidle [namespace code [list my wake $op]]]
            debug {cmd = $cmd}
            return $cmd
        }

        # .. which lands in wake, where the subscriber is notified
        method wake {op} {  debug {$op: $buf: [array get sleeping]}
            if {![info exists sleeping($op)]} {
                debug {Spurious wake event for $op .. (buf = $buf); [array get sleeping]}
                return
            }
            set cmd $sleeping($op)
            unset sleeping($op)
            uplevel #0 $cmd
        }

    ;# channel commands: put and get
        # we have different implementations for rendezvous and queue channels because they are .. different
        method Put0 {data} {
            if {$closed} {
                throw {GOCHAN SIGPIPE} "attempt to write on closed channel!"
            }
            lappend buf $data
            my notify write
            my waiton read
        }
        method Put* {data} {
            if {$closed} {
                throw {GOCHAN SIGPIPE} "attempt to write on closed channel!"
            }
            if {[llength $buf] >= $max} { ;# FIXME: if?
                my waiton read
                if {$closed} {
                    throw {GOCHAN SIGBAD} "channel was closed under us during a write! This is bad!"
                }
            }
            lappend buf $data
            my notify write
        }

        # get is mostly straightforward.  We have to be careful of closure during read.
        method get {{_v ""}} {
            debug {get in [info coroutine]: $_v <- $buf}
            if {$_v ne ""} {upvar 1 $_v v}
            if {$buf eq ""} {
                if {$closed} {
                    whenidle [namespace code {my destroy}]
                    throw {GOCHAN EOF} "attempt to read from empty, closed channel!"
                }
                my waiton write
                if {$buf eq ""} {
                    if {!$closed} {throw {GOCHAN WTF} "this is too weird"}
                    whenidle [namespace code {my destroy}]
                    throw {GOCHAN EOF} "channel was closed under us during a read!"
                }
            }
            set buf [lassign $buf v]
            my notify read
            catch {debug {get in [info coroutine]: $_v = [set $_v]}}
            return $v
        }

    ;# friendly get for use in loops.  Breaks on EOF.
        method put? {v} {
            try {
                my put $v
            } trap {GOCHAN SIGPIPE} {} {    ;# NOTE: SIGPIPE
                return -code break
            }
        }
        method get? {{_v ""}} {
            if {$_v ne ""} {upvar 1 $_v v}
            try {
                my get v
            } trap {GOCHAN EOF} {} {
                return -code break
            }
        }

if 0 {  ;# this mixes badly with object teardown
        method get! {{_v ""}} {
            if {$_v ne ""} {upvar 1 $_v v}
            if {$buf eq "" && $closed} {throw {GOCHAN EOF} "early detection"}
            set varname [namespace current]::!
            if {[info exists $varname]} {
                throw {GOCHAN BADBANG} "multiple sync commands?"
            }
            debug {waiting on $varname}
            go my Goget! $varname
            #go my get $varname
            if {![info exists $varname]} { vwait $varname }
            lassign [set $varname][unset $varname] result eof
            if {$eof} {
                throw {GOCHAN EOF} "EOF during synchronous read"
            }
            set v $result
        }
        method Goget! {varname} {
            try {
                tailcall set $varname [list [my get] 0]
            } trap {GOCHAN EOF} {} {
                tailcall set $varname [list "" 1]
            }
        }
}

        method put! {v} {
            set varname [namespace current]::!
            if {[info exists $varname]} {
                throw {GOCHAN BADBANG} "multiple sync commands?"
            }
            debug {waiting on $varname}
            go try "
                [namespace code my] put [list $v]
                incr [list $varname]
            "
            vwait $varname
            unset $varname
        }

        forward <- my put
        forward <-! my put!
        forward <-? my put?
        forward -> my get
        # forward ->! my get!
        method ->! args {tailcall ->! [self] {*}$args}
        forward ->? my get?
        export <- -> <-! ->! <-? ->?
    }

    # select has to reach into the [sub] and [unsub] methods directly
    proc select {script} {
        foreach {op chan body} $script {
            switch -exact -- $op {
                -> {
                    set op write
                }
                <- {
                    set op read
                }
                default {
                    error "bad argument: expected <- or ->"
                }
            }
            $chan sub $op [info coroutine] $body
            lappend subs $chan $op
        }
        set body [yield]
        lmap {chan op} $subs {
            $chan unsub $op [info coroutine] $body
        }
        tailcall try $body
    }

    # set var [<- $chan]
    proc <- {channel} {tailcall $channel get}
    # while 1 {puts [<- $chan]}
    proc <-? {channel} {tailcall $channel get?}

    # synchronous version for outside coroutines:  BEWARE VWAIT!
    #proc <-! {channel} { tailcall $channel get!  }
    proc <-! {channel} {
        variable waitvars
        set varname [namespace which -variable waitvars]($channel:[info cmdcount])
        if {[info exists $varname]} {
            throw {GOCHAN BADBANG} "$varname is already in use!"
        }
        debug {<-! $channel waiting on $varname}
        #go $channel get $varname
        go apply {{chan varname} {
            try {
                set $varname [list [$chan get] 0]
            } trap {GOCHAN EOF} {} {
                set $varname [list "" 1]
            }
        }} $channel $varname
        if {![info exists $varname]} { vwait $varname }
        lassign [set $varname][unset $varname] v eof
        if {$eof} {
            throw {GOCHAN EOF} "late detection"
        }
        return $v
    }
    
    coroutine gensym apply {{} {
        set name ""
        while {1} {
            set p [yield $name]
            if {$p eq ""} {set p "goro#"}
            set name $p[incr i($p)]
        }
    }}

    # creates an anonymous coroutine
    proc go {cmd args} {
        set name [gensym goro#]
        uplevel 1 [list coroutine $name $cmd {*}$args]
        return $name
    }

    # a convenient constructor:
    proc channel {varNames args} {
        foreach varName $varNames {uplevel 1 set $varName [gochan new {*}$args]}
        ## csp had this taking varnames, not sure I like that.
        #tailcall ::set $varName [gochan new {*}$args]
    }

    namespace export *
}
namespace path [list {*}[namespace path] go]
# this is enough to get us through the first six tests, and we haven't invoked a fast-spinning timer!
#
# beyond here is some building stuff out of channels and goroutines, which is largely implementation
# independent.  Only [select] needs to be clever about gochans.
namespace eval go {

    proc -> {varname} {
        upvar 1 $varname chan
        channel chan
        go Oneshot $chan
    }
    proc ->* {varname} {
        upvar 1 $varname chan
        channel chan
        go Oneshot $chan
    }
    proc Oneshot {chan} {
        finally [list $chan destroy] ;# ?
        $chan <- [yield]
    }
    proc Oneshot* {chan} {
        finally [list $chan destroy] ;# ?
        $chan <- [yieldm]
    }

    proc ->> {varname} {
        upvar 1 $varname chan
        channel chan
        go Feeder $chan
    }
    proc Feeder {chan} {
        finally [list $chan destroy] ;# ?
        while 1 {
            $chan <- [yield] ;# probably should catch
        }
    }

    # I don't like this name. It's a [gofor]
    proc range {varName chan body} {
        upvar 1 $varName var
        while 1 {
            try {
                set var [<- $chan]
            } trap {GOCHAN EOF} {} {
                break
            }
            uplevel 1 $body
        }
    }

    # I don't like this name. It's a [gofor!]
    proc range! {varName chan body} {
        upvar 1 $varName var
        while 1 {
            try {
                debug {var <-! $chan ???}
                set var [<-! $chan]
                debug {var <-! $chan ==> $var}
            } trap {GOCHAN EOF} {} {
                debug {EOF <-! $chan !!}
                break
            }
            uplevel 1 $body
        }
    }

    proc timer {chanName ms} {
        upvar 1 $chanName chan
        after $ms [-> chan] {[clock microseconds]}      ;# this could try to clean up after itself ...
        return $chan
    }

    proc ticker {chanName interval {closeafter ""}} {
        upvar 1 $chanName chan
        if {$closeafter eq ""} {
            set closeafter -1
        } elseif {[string is integer -strict $closeafter]} {
            after $closeafter $chan close   ;# FIXME: after
            set closeafter -1
        } elseif {[string match #* $closeafter]} {
            set closeafter [string range $closeafter 1 end]
            if {$closeafter <= 0} {
                return -code error "bad argument \"$closeafter\": expected ?ms? or ?#iterations?"
            }
        } else {
            return -code error "bad argument \"$closeafter\": expected ?ms? or ?#iterations?"
        }

        channel chan
        go Ticker $chan $interval $closeafter
        return $chan
    }
    
    proc Ticker {chan interval closeafter} {
        try {
            while {$closeafter} {
                after $interval [info coroutine]    ;# FIXME: after
                yield
                incr closeafter -1
                $chan <-? [clock microseconds]
            }
        } finally {
            debug log {[info coroutine]: aborted!}
            $chan close
        }
    }
}

if 0 {
# this doesn't work because rename-deleting a coroutine bypasses its finally handlers!
    proc whenidle {script} {
        try {
            set id [after idle [info coroutine]]
            debug {yielding $id}
            yieldm
            debug {restarting $id}
            set id [after idle [info coroutine]]
            debug {yielding $id}
            yieldm
            debug {restarting $id}
            unset id
        } finally {
            if {[info exists id]} {
                debug {cancelling $id}
                after cancel $id
            } else {
                debug {cleanly exiting!}
            }
        }
        debug {continuing with $script}
        uplevel #0 $script
    }
}
