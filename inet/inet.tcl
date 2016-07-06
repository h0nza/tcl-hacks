#
# This is an exercise in asynchronous sockets, by implementing some of 
# the "obsolete named protocols" from inetd.  It should serve as a decent
# illustration of async socket techniques using coroutines.
#
# Probably a good example for benchmarking too.
#
# See http://networksorcery.com/enp/protocol/ip/ports00000.htm for assignments and references.
#
# Currently represented:
#   tcpmux/1    rfc1078
#   echo/7      rfc862
#   discard/9   rfc863
#   systat/11   rfc866
#   daytime/13  rfc867
#   netstat/15
#   qotd/17     rfc865
#   chargen/19  rfc864
#   time/37     rfc868
#   ident/113   rfc1413
#   finger/79   rfc1288, 4146
#   pwdgen/129  rfc972
#   proxy/8080  rfc2616(ish)
#
# Potentially interesting to add:
#   telnet/23   (illustrate handling telnet \xff codes in a transchan)
#   socks/1080  (socks4a out is almost trivial, see tcpmux) rfc1928
#
#   sntp/123    rfc5905     $ date -r$((16#`printf "\xb%-47.s"|nc -uw1 ntp.metas.ch 123|xxd -s40 -l4 -p`-2208988800))
#       0b[string cat 00 001 011 ][ string repeat \x00 47]
#       binary scan $resp a40I _ epoch
#       incr epoch [clock scan {00:00 January 1, 1900 UTC}]     ;# -2208988800
#
#
# Interesting but non-trivial directions to extend, suggesting pluggable modules:
#
#   * add some UDP protocols using a suitable extension
#     * syslog
#     * schelte's upnp/ssdp could plug in nicely
#   * a chat protocol (irc? ntalk?) would be fun
#   * make qotd more efficient by caching, or by using fortune.dat
#   * telnet?  With a stubborn client that WONT?
#     * feeds into serial-over-tcp, which is useful
#   * dustmote for http?
#
#  FIXME:
#    * proxy/8080 doesn't work well with CONNECT ..?
#
package require coroutine

namespace eval inet {
    variable BASEPORT 0         ;# offset from declared port
    namespace eval sockets {}   ;# we will keep coroutines here

    # our coros need to accept multiple arguments (tcpmux - for chan copy)
    proc yieldm args {yieldto string cat {*}$args}

    # coroutine-friendly IO proxies:
    proc gets args {tailcall coroutine::util gets {*}$args}
    proc read args {tailcall coroutine::util read {*}$args}
    proc after args {   ;# needs to wrap with [catch] in case the socket is killed while we're waiting
        if {[llength $args] == 1} {
            ::after {*}$args [list catch [info coroutine]]
            yield
        } else {
            ::after {*}$args
        }
    }

    # accept and dispatch a new connection
    proc accept {handler chan host port} {
        chan configure $chan -blocking 0 -buffering line -translation auto
        # :: (as in ipv6 addresses) is not permissible in command names, except as a namespace separator
        set coname [namespace tail $handler]:[string map {: _} $host]:$port
        coroutine sockets::$coname $handler $chan
    }

    # set up all listening ports
    proc listen {{baseport 0}} {
        variable BASEPORT
        set BASEPORT $baseport
        foreach cmd [info commands [namespace current]::*/*] {
            if {![regexp {/(\d+)$} $cmd -> port]} continue
            incr port $BASEPORT
            socket -server [namespace code [list accept $cmd]] $port
            puts $cmd
        }
    }

    # declare a service
    proc service {name body} {
        set body [format {
            puts "Start [info coroutine]"
            try {
                %s
            } on error {e o} {
                puts "Error on $chan: $e"
            } finally {
                catch {close $chan}
            }
            puts "Close [info coroutine]"
        } $body]
        tailcall proc $name {chan} $body
    }

# HELP is a special method for tcpmux.  It doesn't listen on a port, so /*
    service HELP/* {
        foreach cmd [info commands [namespace current]::*/*] {
            set cmd [namespace tail $cmd]
            set cmd [lindex [split $cmd /] 0]
            puts $chan $cmd
        }
    }

# tcpmux is a gateway to other protocols
    service tcpmux/1 {
        variable BASEPORT
        gets $chan proto
        set cmd [info commands $proto/*]
        if {[llength $cmd] != 1} {
            puts $chan "-No such service"
            return
        }
        puts $chan "+$cmd"
        if {0 || ![regexp {/(\d+)$} $cmd -> port]} {
            # easy version:  call the service directly
            $cmd $chan  ;# NOTE: we can't tailcall here because the finally handler closes the sock
        } else {
            incr port $BASEPORT
            set upchan [socket -async localhost $port]  ;# -async ensures we don't block other clients.
                                                        ;# But beware:  DNS lookup blocks!
            chan configure $upchan -blocking 0
            chan copy $chan $upchan -command [info coroutine]
            chan copy $upchan $chan -command [info coroutine]
            foreach _ {1 2} {     ;# twice to catch both events
                lassign [yieldm] nbytes err
                if {[eof $upchan] || [eof $chan]} {
                    break
                }
            }
            catch {close $upchan}   ;# make sure this gets closed
        }
    }

# echo, discard are very simple:
    service echo/7 {
        while {[gets $chan line] >= 0} {
            puts $chan $line
        }
    }

    service discard/9 {
        while {![eof $chan]} {
            # discard result
            coroutine::util read $chan
        }
    }

# chargen, qotd send some data:
    service chargen/19 {
        set chargen { !"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`abcdefghijklmnopqrstuvwxyz} ;# " - vim syntax hack
        set max [string length $chargen]
        append chargen $chargen
        set i 0
        while {![eof $chan]} {
            while {[chan pending output $chan]} {
                coroutine::util after idle
            }
            puts $chan [string range $chargen $i $i+71]
            coroutine::util after idle      ;# make sure other clients get serviced!
            incr i
            if {$i >= $max} {incr i -$max}
        }
    }

    service qotd/17 {
        set fd [open /usr/share/games/fortunes/fortunes r]
        set quote {}
        set current {}
        set i 0
        while {[gets $fd line]>=0} {
            if {$line eq "%"} {
                if {rand()*[incr i]<1} {
                    set quote $current
                }
                set current {}
            } else {
                lappend current $line
            }
        }
        close $fd
        foreach line $quote {
            puts $chan $line
        }
    }

# time services:
    service daytime/13 {
        puts $chan [clock format [clock seconds]]
    }

    service time/37 {
        chan configure $chan -encoding binary
        puts -nonewline $chan [binary format I [expr {[clock seconds]-[clock scan 1900-01-01]}]]    ;# ? UTC
    }

# whois is trivial:
    service whois/43 {  ;# rfc3912
        fconfigure $chan -translation crlf
        if {[gets $chan who] > 0} {
            puts $chan "WHOIS: $who"
            puts $chan "I don't know!"
        }
    }

    service finger/79 { ;# rfc1288
        fconfigure $chan -translation crlf

        if {[gets $chan req] > 0} {
            if {[regexp {^/W(?: +(.*))$} $req -> user]} {
                set parts [split $user @]
                if {[llength $parts] > 1} {
                    puts chan "No forwarding allowed!"
                } else {
                    foreach line {
                        Vending machines SHOULD respond to a {C} request with a list of all
                        items currently available for purchase and possible consumption.
                        Vending machines SHOULD respond to a {U}{C} request with a detailed
                        count or list of the particular product or product slot.  Vending
                        machines should NEVER NEVER EVER eat money.
                    } {puts $chan $line}
                }
            }
        }
    }

    service ident/113 { ;# rfc1413
        if {[gets $chan line] > 0} {
            set parts [lmap x [split $line ,] {string trim $x}]
            lassign $parts remote local

            if {![string is integer -strict $local] || $local < 1 || $local >= 2**16} {
                puts $chan "$remote, $local : ERROR : INVALID-PORT"
            } elseif {![string is integer -strict $remote] || $remote < 1 || $remote >= 2**16} {
                puts $chan "$remote, $local : ERROR : INVALID-PORT"
            } elseif {1} {
                puts $chan "$remote, $local : ERROR : HIDDEN-USER"
            } else {
                set opsys "UNIX"        ;# see "Assigned Numbers"
                set charset "US-ASCII"  ;# ugh, really?
                puts $chan "$remote, $local : USERID : $opsys, $charset : $userid"
            }
        }
        # FIXME: this can continue to accept requests, timing out after 60-180s idle
    }
    
    service pwdgen/129 { ;# rfc972
        package require base64
        for {set i 0} {$i < 6} {incr i} {
            set bits [lmap _ {1 2 3} {expr {entier((2**16)*rand())}}]
            set pw [base64::encode [binary format ttt {*}$bits]]
            puts $chan $pw
        }
    }

# systat, netstat can background a subprocess with redirection to channel
    service systat/11 {
        exec ps -ef >@$chan &
    }

    service netstat/15 {
        exec netstat -atun >@$chan &
    }

# but that's a TERRIBLE IDEA to expose, so let's just tell them about our state:
    service systat/11 {
        foreach cmd [info commands sockets::*] {
            puts $chan $cmd
        }
    }
    service netstat/15 {
        foreach cmd [info commands sockets::*] {
            puts $chan $cmd
        }
    }

    service proxy/8080 {

        chan configure $chan -translation crlf  -encoding binary

        # read first line
        gets $chan request

        # read until \n\n
        set preamble ""
        while {[gets $chan line] > 0} {
            append preamble $line\n
        }
        # note $preamble doesn't include the extra \n

        # parse request line
        if {![regexp {^([A-Z]+) (.*) (HTTP/.*)$} $request -> verb dest httpver]} {
            throw {PROXY BAD_REQUEST} "Bad request: $request"
        }

        if {[regexp {^(\w+)://([^:/ ]+)(?::(\d+))?(.*)$} $dest -> scheme host port path]} {
        } elseif {[regexp {^([^:/ ]+)(?::(\d+))?$} $dest -> host port]} {
        } else {
            throw {PROXY BAD_URL} "Bad URL: $dest"
        }

        if {$port eq ""} {set port 80}

        # open outgoing conn
        set upchan [socket -async $host $port]  ;# -async ensures we don't block other clients.
                                                ;# But beware:  DNS lookup blocks!
        chan configure $upchan -blocking 0 -translation crlf -buffering none   -encoding binary

        # send headers
        if {$verb ne "CONNECT"} {
            puts $upchan $request
            puts $upchan $preamble  ;# extra newline is wanted here!
        }

        # revert to binary mode
        chan configure $chan   -buffering none -translation binary -encoding binary
        chan configure $upchan -buffering none -translation binary -encoding binary

        # fcopy
        chan copy $chan $upchan -command [info coroutine]
        chan copy $upchan $chan -command [info coroutine]
        foreach _ {1 2} {     ;# twice to catch both events
            lassign [yieldm] nbytes err
            if {[eof $upchan] || [eof $chan]} {
                break
            }
        }
        catch {close $upchan}   ;# make sure this gets closed
    }

}

::inet::listen 10000
vwait forever
