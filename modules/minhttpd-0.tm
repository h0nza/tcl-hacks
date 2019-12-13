#!/usr/bin/env tclsh
#
# Just the bare minimum to serve http.  See example at bottom.
#

namespace eval minhttpd {

    proc callback args {
        tailcall namespace code $args
    }
    proc finally args {
        set ns [uplevel 1 {namespace current}]
        set callback [list apply [list args $args $ns]]
        tailcall trace add variable :#:FINALLY:#: unset $callback
    }

    # an async gets that *must* consume a line + newline, and will reject lines > limit chars long
    proc http-gets {chan _line {limit 1024}} {
        upvar 1 $_line line
        while 1 {
            yield
            if {[gets $chan line] >= 0 && ![eof $chan]} break   ;# EOF will be true if we didn't get a line-terminator
            if {[chan pending input $chan] > $limit} {
                return -level 2 -code error -errorcode {MINHTTPD LINE_TOO_LONG} "Line too long: [chan pending $chan] > $limit bytes"
            }
            if {[eof $chan]} {
                return -level 2 -code error -errorcode {MINHTTPD EOF} "Premature EOF while reading line after [string length $line] bytes"
            }
        }
    }

    proc serve {callback port} {
        dict set sockargs -server [callback accept $callback]
        if {[regexp {(.*):(.*)} $port -> host port]} {
            dict set sockargs -myaddr $host
        }
        set listenfd [socket {*}$sockargs $port]
        return $listenfd
    }

    proc stop {listenfd} {
        close $listenfd
        # timeouts will take care of existing clients
    }

    proc accept {callback chan caddr cport} {
        coroutine coro#$chan#[info cmdcount] Accept $callback $chan
    }

    proc Accept {callback chan} {
        finally close $chan

        set timeout [after 1000 [list rename [info coroutine] {}]]
        finally after cancel $timeout

        chan configure $chan -translation crlf -encoding iso8859-1 -blocking 0
        chan event $chan readable [info coroutine]

        http-gets $chan reqline

        if {![regexp {^GET (.*) HTTP/1.\d+$} $reqline -> uri]} {
            puts $chan "HTTP/1.1 400 Bad Request"
            puts $chan "Connection: close"
            puts $chan ""
            return -code error -errorcode {MINHTTPD INVALID REQUEST} "Invalid request [list $reqline]"
        }

        while 1 {
            http-gets $chan header
            if {$header eq ""} break
        }

        regsub {^https?://[^/]*} $uri {} uri

        set rc [catch {uplevel #0 [list {*}$callback $uri]} res opts]

        if {$rc == 0} {
            set code 200
            set data $res
        } elseif {$rc < 100} {
            set code 500
            set data ""
        } else {
            set code $rc
            set data $res
            set rc 0
        }

        if {$code in {301 302}} {
            if {![dict exists $opts -location]} {
                if {$res eq ""} {
                    throw {MINHTTPD BAD REDIRECT} "Redirect must specify -location or a result"
                } else {
                    dict set opts -location $res
                    set res ""
                }
            }
            set data $res
        }

        dict unset opts -level
        dict unset opts -code
        foreach errkey [dict keys $opts -error*] {
            dict unset opts $errkey
        }

        set httpcodes {
            200 "OK"
            204 "No Content"
            301 "Moved Permanently"
            302 "Found"
            403 "Forbidden"
            404 "Not Found"
            500 "Internal Server Error"
        }
        set codedesc [dict get $httpcodes $code]

        if {$data eq ""} {
            if {$code eq 200} {set code 204}
            if {$code ne 204} {set data $codedesc}
        }

        puts $chan "HTTP/1.1 $code $codedesc"
        puts $chan "Connection: close"

        set defheaders {
            -content-type text/html
        }

        set headers [dict merge $defheaders $opts]

        set is_text [string match text/* [dict get $headers -content-type]]

        if {$is_text} {
            dict append headers -content-type "; charset=utf-8"
        }

        dict for {k v} $headers {
            if {$v eq ""} {
                dict unset headers $k
            }
        }

        if {$data eq ""} {
            dict unset headers -content-type
        }

        dict for {header value} $headers {
            regsub ^- $header {} header
            regsub :$ $header {} header
            regsub -all "\n\\s*" $value "\n "
            puts $chan "$header: $value"
        }
        puts $chan ""

        if {!$is_text} {
            chan configure $chan -translation binary
            puts -nonewline $chan $data
        } else {
            chan configure $chan -encoding utf-8
            if {$data ne ""} {
                puts $chan $data        ;# extra newline for friendliness
            }
        }

        # finally will close $chan

        if {$rc != 0} {
            return -code $rc {*}$opts $res
        }
    }
}

if {[info script] eq $::argv0} {

    set port 8080
    while {$port < 8100} {
        try {
            set svrfd [minhttpd::serve httpGet $port]
            puts "Listening on http://localhost:$port/"
            break
        } on error {} continue
    }
    if {![info exists svrfd]} {
        puts "Unable to open server socket!"
        exit 1
    }

    proc httpGet {url} {
        if {$url eq "/"} {
            return -code 302 /index.html
        }
        if {$url eq "/admin"} {
            return -code 403 "You are not allowed!"
        }
        if {$url eq "/index.html"} {
            return "(\u2713) Hello, world!"
        }
        if {$url eq "/binary"} {
            return -content-type application/octet-stream \x0d\xea\xd0\x0b\xee\xf0
        }
        if {$url eq "/exit"} {
            after idle {incr ::forever}
            return "Exiting!"
        }
        if {$url eq "/empty"} {
            return ""
        }
        if {$url eq "/no-content-type"} {
            return -code 404 -content-type "" {<script>alert("boom")</script>}
        }
        if {$url eq "/error"} {
            expr {1/0}
        }
        return -code 404
    }

    vwait forever

}
