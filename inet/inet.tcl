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
#   1     tcpmux   rfc1078
#   7     echo     rfc862
#   9     discard  rfc863
#   11    systat   rfc866
#   13    daytime  rfc867
#   15    netstat  rfc866?
#   17    qotd     rfc865
#   19    chargen  rfc864
#   37    time     rfc868
#   43    whois    rfc3912
#   79    finger   rfc1288, 4146
#   113   ident    rfc1413
#   129   pwdgen   rfc972
#   1080  socks5   rfc1928 (outbound tcp only)
#   8080  proxy    rfc2616(ish)
#
# Potentially interesting to add:
#   telnet/23   (illustrate handling telnet \xff codes in a transchan)
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
#   * how simple http can get away with? dustmote?
#

namespace eval inet {
    variable BASEPORT 0         ;# offset from declared port
    namespace eval sockets {}   ;# we will keep coroutines here

    # our coros need to accept multiple arguments (tcpmux - for chan copy)
    proc yieldm args {yieldto string cat {*}$args}

    # this is handy for cleanup
    proc finally {script} {
        tailcall trace add variable :#finally#: unset [list apply [list args $script]]
    }

    # coroutine-friendly IO proxies - like coroutine::util:
    proc gets {chan args} {
        if {![chan configure $chan -blocking]} {
            set was [chan event $chan readable]
            chan event $chan readable [list catch [info coroutine]]
            yield
            chan event $chan readable $was
        }
        tailcall ::gets $chan {*}$args
    }

    proc read {chan {numChars Inf}} {
        if {[chan configure $chan -blocking]} {
            tailcall ::read $chan {*}$numChars
        } else {
            set was [chan event $chan readable]
            chan event $chan readable [list [info coroutine]]
            finally [list chan event $chan readable $was]
            set data ""
            while {[string length $data] < $numChars} {
                yield
                append data [::read $chan $numChars]
                if {[eof $chan]} break
            }
            return $data
        }
    }

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
            finally [list catch [list close $chan]]
            try {
                %s
            } on error {e o} {
                puts "Error in [info coroutine]: $e"
            }
            puts "End [info coroutine]"
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
            read $chan
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
                after idle
            }
            puts $chan [string range $chargen $i $i+71]
            after idle      ;# make sure other clients get serviced!
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
                    puts $chan "No forwarding allowed!"
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

# socks5 is pretty simple - outbound TCP only
    service socks5/1080 {
        chan configure $chan -encoding binary -buffering none

        # authentication
        scan [read $chan 2] %c%c ver nmeth
        if {$ver != 5} return
        binary scan [read $chan $nmeth] c* meths
        if {0 in $meths} {          ;# no authentication! yay
            puts -nonewline $chan \x05\x00
        } elseif {2 in $meths} {    ;# user/passwd
            scan [read $chan 2] %c%c ver len
            if {$ver != 1} return
            set username [read $chan $len]
            scan [read $chan 1] %c len
            set password [read $chan $len]
            puts -nonewline $chan \1\0  ;# success!
        } else {                    ;# no supported auth methods
            puts -nonewline $chan \x05\xff
            return
        }

        # request
        scan [read $chan 4] %c%c%c%c ver cmd z atyp
        if {$ver != 5 || $z != 0} return

        if {$atyp == 1} {       ;# IPv4
            scan [read $chan 4] %c%c%c%c a b c d
            set dst $a.$b.$c.$d
        } elseif {$atyp == 3} { ;# hostname
            scan [read $chan 1] %c alen
            set dst [read chan $alen]
        } elseif {$atyp == 4} { ;# IPv6
            binary scan [read $chan 16] c* dst
            set dst [join $dst :]
        }

        binary scan [read $chan 2] Su dpt

        if {$cmd == 3} {        ;# UDP
            puts -nonewline $chan \5\7\0\3\0\0\0    ;# cmd not supported ":0"
            return
        } elseif {$cmd == 2} {  ;# bind
            puts -nonewline $chan \5\7\0\3\0\0\0    ;# cmd not supported ":0"
            return
        } elseif {$cmd == 1} {  ;# connect

            set upchan [socket -async $dst $dpt]
            finally [list catch [list close $upchan]]

            yieldto chan event $upchan writable [info coroutine]
            chan event $upchan writable ""

            set err [chan configure $upchan -error]
            if {$err ne ""} {
                # 1 generic 2 notallowed
                # 3 netunreach 4 hostunreach
                # 5 connrefused 6 ttlexpired
                puts -nonewline $chan \5\5\0\1\0\0\0    ;# connection refused
                return
            }

            lassign [chan configure $upchan -sockname] myaddr _ myport

            if {[scan $myaddr %d.%d.%d.%d a b c d] == 4} {
                set myaddr [format %c%c%c%c%c 1 $a $b $c $d]  ;# IPv4
            } else {
                # pack an IPv6 address
                lassign [split $myaddr ::] a b
                set myaddr [lrepeat 16 0]
                set i -1
                foreach octet $a {
                    lset $myaddr [incr i] $octet
                }
                set i 16
                foreach octet [lreverse $b] {
                    lset $myaddr [incr i -1] $octet
                }
                set myaddr [binary format cc* 4 $myaddr]    ;# IPv6
            }
            set myport [binary format Su $myport]
            puts -nonewline $chan \5\0\0$myaddr$myport      ;# OK

            chan configure $upchan -translation binary

            chan copy $chan $upchan -command [info coroutine]
            chan copy $upchan $chan -command [info coroutine]
            lassign [yieldm] nbytes err     ;# twice to catch both events
            lassign [yieldm] nbytes err
        }
    }

# a web proxy is a very nice thing to have, and not really much more complex:
    service proxy/8080 {

        chan configure $chan -translation crlf  -encoding iso8859-1

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

        if {[regexp {^(\w+)://\[([^\]/ ]+)\](?::(\d+))?(.*)$} $dest -> scheme host port path]} {
            # IPv6 URL
        } elseif {[regexp {^(\w+)://([^:/ ]+)(?::(\d+))?(.*)$} $dest -> scheme host port path]} {
            # normal URL
        } elseif {[regexp {^([^:/ ]+)(?::(\d+))?$} $dest -> host port]} {
            # CONNECT-style host:port
        } elseif {[regexp {^\[([^\]/ ]+)\](?::(\d+))?$} $dest -> host port]} {
            # CONNECT-style host:port IPv6
        } else {
            throw {PROXY BAD_URL} "Bad URL: $dest"
        }

        if {$port eq ""} {set port 80}

        # open outgoing conn
        set upchan [socket -async $host $port]  ;# -async ensures we don't block other clients.
                                                ;# But beware:  DNS lookup blocks!

        chan configure $upchan -blocking 0 -translation crlf -buffering none   -encoding iso8859-1

        # wait till we're connected:
        yieldto chan event $upchan writable [info coroutine]
        chan event $upchan writable ""

        # .. or did connection fail?
        set err [chan configure $upchan -error]
        if {$err ne ""} {
            # FIXME: smarter responses
            puts $chan "$httpver 502 Bad Gateway"
            puts $chan "Content-type: text/plain"
            puts $chan ""
            puts $chan "Error connecting to $host port $port:"
            puts $chan "  $err"
            return
        }
        finally [list close $upchan]

        if {$verb eq "CONNECT"} {
            # for CONNECT, we need to synthesise a response:
            puts $chan "$httpver 200 OK"
            puts $chan ""
        } else {
            # else, forward the request headers:
            puts $upchan $request
            puts $upchan $preamble  ;# extra newline is wanted here!
        }

        # revert to binary mode, and hand over to [chan copy]:
        chan configure $chan   -buffering none -translation binary -encoding binary
        chan configure $upchan -buffering none -translation binary -encoding binary
        chan copy $chan $upchan -command [info coroutine]
        chan copy $upchan $chan -command [info coroutine]
        lassign [yieldm] nbytes err     ;# twice to catch both events
        lassign [yieldm] nbytes err

        # and we're done!  Cleanup is automatic.
    }

}

::inet::listen 10000
vwait forever
