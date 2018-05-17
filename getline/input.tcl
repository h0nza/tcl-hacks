source util.tcl ;# ssplit prepend

oo::class create Input {

    variable input
    variable moreinput

    constructor {{in ""} {idx end}} {
        namespace path [list [namespace qualifiers [self class]] {*}[namespace path]]
        my init $in $idx
    }

    method init {{in ""} {idx end}} {
        ssplit $in $idx -> input moreinput
    }

    method set-state {{in ""} {j end}} {
        ssplit $in $j -> input moreinput
    }

    method insert {s} {
        append input $s
        return $s
    }

    method back {{n 1}} {
        ssplit $input end-$n -> input s
        prepend moreinput $s
        return $s
    }
    method forth {{n 1}} {
        ssplit $moreinput $n -> s moreinput
        append input $s
        return $s
    }
    method delete {{n 1}} {
        ssplit $moreinput $n -> s moreinput
        return $s
    }
    method backspace {{n 1}} {
        ssplit $input end-$n -> input s
        return $s
    }
    method get  {} {return $input$moreinput}
    method len  {} {string length $input$moreinput}
    method pre  {} {return $input}
    method post {} {return $moreinput}
    method pos  {} {string length $input}
    method rpos {} {string length $moreinput}
    method reset {{s ""}} {
        set r [my get]
        my init $s
        return $r
    }
}
