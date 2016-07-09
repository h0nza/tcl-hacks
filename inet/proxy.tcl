#!/usr/bin/env tclsh8.6
#
# FIXME: configurable ports
socket -server {go accept} 8080
puts "listening on 8080"

# FIXME: stunnel https

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

    # FIXME: add support for path-only with Host: header
    if {[regexp {^/.*$} $dest]} {
        # it's a plain http request, not proxy
        set path $dest
        if {![regexp -line {^Host: (.*)(?::(.*))$} $preamble -> host port]} {
            throw {PROXY HTTP BAD_HOST} "Bad Host header!"
        }
        if {$path eq "/proxy.pac"} {
            puts $chan "HTTP/1.1 200 OK"
            puts $chan "Connection: close"
            puts $chan "Content-Type: text/javascript"
            puts $chan ""
            # FIXME: this can be generated more cleverly, but have to be stunnel-aware
            puts $chan "function FindProxyForURL(u,h){return \"HTTPS localhost:8443\";}"
        } else {
            puts $chan "HTTP/1.1 404 Not Found"
            puts $chan "Connection: close"
            puts $chan "Content-Type: text/plain"
            puts $chan ""
            puts $chan "No such thing here.  Try /proxy.pac"
        }
        return  ;# was HTTP; response already sent; no forwarding
    } elseif {[regexp {^(\w+)://\[([^\]/ ]+)\](?::(\d+))?(.*)$} $dest -> scheme host port path]} {
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

    # divine the port, if blank
    if {$port eq ""} {
        try {
            set default_ports {http 80 https 443 ftp 21}    ;# this should come from a smarter registry, but here's enough
            set port [dict get $default_ports $scheme]
        } on error {} {
            set port 80
        }
    }

    # is it a request for proxy.pac?
    if {$verb eq "GET" && $path eq "/proxy.pac" && ($host in {127.0.0.1 localhost ::1} || [string match "wpad.*" $host])} {
        puts $chan "HTTP/1.1 200 OK"
        puts $chan "Connection: close"
        puts $chan "Content-Type: text/javascript"
        puts $chan ""
        puts $chan "function FindProxyForURL(u,h){return \"HTTPS localhost:8443\";}"
        # FIXME: this can be generated more cleverly, but have to support Host: header and know if stunnel'ed
        return
    }

    set upchan [socket -async $host $port]  ;# FIXME: synchronous DNS blocks :(
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

    # fortunately, a proxy doesn't have to care about "Connection: keep-alive"

    chan configure $chan   -buffering none -translation binary
    chan configure $upchan -buffering none -translation binary
    chan copy $chan $upchan -command [info coroutine]
    chan copy $upchan $chan -command [info coroutine]
    yieldm
    yieldm
}

vwait forever
