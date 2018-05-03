source input.tcl
namespace path [list {*}[namespace path] ::input]

proc assert {cond} {
    if {![uplevel 1 [list ::expr $cond]]} {
        append          err "Assertion failed: [list $cond]"
        catch {append err "\n           subst: ([uplevel 1 [list ::subst -noc -nob $cond]])"}
        catch {append err "\n          result: [uplevel 1 [list ::subst -nob $cond]]"}
        return -code error $err
    }
}

assert {[sreplace "foo" 0 0 BOO]    eq "BOOoo"}
assert {[sreplace "foo" 0 -1 BOO]   eq "BOOfoo"}
assert {[sreplace "foo" 0 1 BOO]    eq "BOOo"}
assert {[sreplace "foo" 1 1 BOO]    eq "fBOOo"}
assert {[sreplace "foo" 2 2]        eq "fo"}
assert {[sreplace "foo" end+1 end+1 BOO]    eq "fooBOO"}
assert {[sreplace "foo" end+1 1 BOO]        eq "fooBOO"}

input::init

# basics, endpoints:
assert {[input::insert "foo"] eq [list insert foo 3]}
assert {$::input::input eq "foo"}
assert {$::input::point eq 3}
assert {[input::left 4] eq [list left 3]}
assert {$::input::input eq "foo"}
assert {$::input::point eq 0}
assert {[input::insert "bar"] eq [list insert bar 3]}
assert {$::input::input eq "barfoo"}
assert {$::input::point eq 3}
assert {[input::right 4] eq [list right 3]}
assert {[input::right 1] eq [list]}
assert {[input::insert "badge"] eq [list insert badge 5]}
assert {$::input::input eq "barfoobadge"}
assert {[input::left 4] eq [list left 4]}
# deletion:
assert {[input::delete 2] eq [list delete ad 2]}
assert {[input::backspace 2] eq [list backspace ob 2]}
assert {$::input::input eq "barfoge"}
# insert within, insert control:
assert {[input::insert \x03] eq [list insert <03> 4]}
assert {[input::left] eq [list left 4]}
assert {[input::delete 2] eq [list delete <03>g 5]}
