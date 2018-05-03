#!/usr/bin/env tclsh
# socks5 is pretty simple - outbound TCP only


namespace eval socks5 {

    proc main {{port 1080}} {
        socket -server [callback accept socks5] $port
        puts "Listening on $port"
        vwait forever
    }

    proc accept {handler chan host port} {
        chan configure $chan -blocking 0
        set coname [namespace tail $handler]:[string map {: _} $host]:$port
        coroutine $coname $handler $chan $host $port
    }

    proc socks5 {chan caddr cport} {
        finally [list catch [list close $chan]]
        finally {log Disconnecting}
        log "New connection from $caddr $cport"
        chan configure $chan -translation binary -buffering none

        # authentication
        scan [read $chan 2] %c%c ver nmeth
        if {$ver != 5} return
        binary scan [read $chan $nmeth] c* meths
        if {0 in $meths} {                  ;# no authentication! yay
            puts -nonewline $chan \x05\x00      ;# success!
        } elseif {2 in $meths} {            ;# user/passwd
            scan [read $chan 2] %c%c ver len
            if {$ver != 1} return
            set username [read $chan $len]
            scan [read $chan 1] %c len
            set password [read $chan $len]
            log "Authenticating $username $password"
            puts -nonewline $chan \x05\x00      ;# success!
        } else {
            puts -nonewline $chan \x05\xff      ;# no supported methods
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
            log "UDP not supported"
            return
        } elseif {$cmd == 2} {  ;# bind
            puts -nonewline $chan \5\7\0\3\0\0\0    ;# cmd not supported ":0"
            log "Bind not supported"
            return
        } elseif {$cmd == 1} {  ;# connect

            log "Connecting to $dst $dpt"

            set upchan [socket -async $dst $dpt]
            finally [list catch [list close $upchan]]

            yieldto chan event $upchan writable [info coroutine]
            chan event $upchan writable ""

            set err [chan configure $upchan -error]
            if {$err ne ""} {
                # FIXME: proper responses are better
                # 1 generic 2 notallowed
                # 3 netunreach 4 hostunreach
                # 5 connrefused 6 ttlexpired
                log "Error $err: responding ECONNREFUSED"
                puts -nonewline $chan \5\5\0\1\0\0\0    ;# connection refused
                return
            }

            lassign [chan configure $upchan -sockname] myaddr _ myport

            log "Connected via $myaddr $myport"

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

            chan configure $upchan -translation binary -buffering none -blocking 0

            chan push $upchan [callback tamper_up]
            chan push $chan [callback tamper_down]

            chan copy $chan $upchan -command [list [info coroutine] client]
            chan copy $upchan $chan -command [list [info coroutine] server]
            lassign [yieldm] whom nbytes err
            log "Connection closed by $whom"
            close $chan
            close $upchan
        }
    }

    proc read {chan args} {
        if {![chan configure $chan -blocking]} {
            set was [chan event $chan readable]
            chan event $chan readable [list catch [info coroutine]]
            yield
            chan event $chan readable $was
        }
        tailcall ::read $chan {*}$args
    }

    proc log args {
        puts [list [info coroutine] {*}$args]
    }

    proc callback args {tailcall namespace code $args}

    proc yieldm args {yieldto string cat {*}$args}

    proc finally {script} {
        tailcall trace add variable :#finally#: unset [list apply [list args $script]]
    }

    namespace eval tamper_up {
        proc initialize {x mode}       { info procs }
        proc finalize {x}              { }
        proc read {x data} {
            return $data
        }
        proc write {x data} {
            if {[string match *\x00\x00\x00\x04\x31\x30\x30\x30* $data]} {
                puts "Rewriting!"
            }
            string map {
                \x00\x00\x00\x04\x31\x30\x30\x30
                \x70\x60\x50\x40\x31\x30\x30\x30
            } $data
        }
        namespace export *
        namespace ensemble create
    }

    namespace eval tamper_down {
        proc initialize {x mode}       { info procs }
        proc finalize {x}              { }
        proc read {x data} {
            return $data
        }
        proc write {x data} {
            return $data
        }
        namespace export *
        namespace ensemble create
    }
}

socks5::main {*}$::argv
