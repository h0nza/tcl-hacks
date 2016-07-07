#!/usr/bin/env tclsh8.6
#
socket -server {go accept} 8080

proc yieldm args {yieldto string cat {*}$args}

proc finally {script} {
    tailcall trace add variable :#finally#: unset [list apply [list args $script]]
}

proc go {args} {
    variable :gonum
    incr :gonum
    tailcall coroutine goro${:gonum} {*}$args
}

proc accept {chan chost cport} {
    chan configure $chan -blocking 0 -buffering line -translation crlf -encoding iso8859-1

    finally [list close $chan]

    chan even $chan readable [info coroutine]
    yieldm
    gets $chan request

    set preamble ""
    while {[yield; gets $chan line] > 0} {
        append preamble $line\n
    }
    chan even $chan readable ""
    if {![regexp {^([A-Z]+) (.*) (HTTP/.*)$} $request -> verb dest httpver]} {
        throw {PROXY BAD_REQUEST} "Bad request: $request"
    }

    # FIXME: just serve up a .pac for known dest

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

    # FIXME: resolve server first

    set upchan [socket -async $host $port]
    yieldto chan event $upchan writable [info coroutine]
    chan event $upchan writable ""
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

    chan configure $upchan -blocking 0 -buffering line -translation crlf -encoding iso8859-1

    if {$verb eq "CONNECT"} {
        # for CONNECT, we need to synthesise a response:
        puts $chan "$httpver 200 OK"
        puts $chan ""
    } else {
        # else, forward the request headers:
        puts $upchan $request
        puts $upchan $preamble  ;# extra newline is wanted here!
    }

    chan configure $chan   -buffering none -translation binary
    chan configure $upchan -buffering none -translation binary
    chan copy $chan $upchan -command [info coroutine]
    chan copy $upchan $chan -command [info coroutine]
    yieldm
    yieldm
}

vwait forever
