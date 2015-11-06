# why is this so subtle?
#
# because object methods, class methods, constructors, initialisation scripts, classes, metaclasses, 
# instances and subclasses are all concepts just a little bit too close to one another.
#
# But I think I've (finally!) nailed it.
#
#
# To best understand this, it helps to reflect on a few things:
#
# TclOO consists of four commands: oo::class, oo::object, oo::define, oo::objdefine.  The first two
# are objects:  they're tasty and the whole point of the exercise.  The other two are a bit funny.
# They're kinda like namespace ensembles with a -parameter, but if you check, that expansion doesn't
# hold:
#
#   % oo::define myclass method bark {} {puts woof}
#   % oo::define::method myclass bark {} {puts woof}
#   error
#
# They seem to work by inspecting the stack to see which object is being defined -- at least, that's
# the best method I've seen used in script.  Basically, they're a little bit perverse and resistant
# to extension in a way most things in Tcl aren't, which is why I kept picking at this like a scab.
#
# It's worth noting (accepting) that objects and classes are different.  Which is why there are these
# two definition commands.  And hard-to-articulate differences between class methods and object 
# methods, to say nothing of the weird involuted relationship between oo::class and oo::object.
#
# This module makes classes better, but does nothing for objects.  That will come later.
#
# An object is a command with a namespace tied to its lifetime.  And various properties relating to
# OO and Classes, but the namespace lifetime is really the nugget.
#
# A class is a special kind of object that can also (create) be the class of objects.  This is why
# there is no oo::objdefine::constructor, and why a mixin can only be a class.
#
# oo::class is special among classes in that its instances are classes.  This is why they get a create 
# method, but their instances don't.  We call it a metaclass.
#
# How do you make a metaclass?  By creating a class which is a subclass of oo::class:  this way its
# instances will have create methods and be able to act as classes.
#
# It is worth having [Inspecting TclOO] handy as you proceed.  Nothing beats looking under the covers.
#
catch {namespace delete meta}

namespace eval meta {

    ;#proc debug {args} { puts "D: [uplevel 1 subst $args]" }
    proc debug args {}

;# doesn't everybody use these?  [interp alias] + all those [namespace] calls is so verbose

    proc alias {alias cmd args} {
        if {![string match ::* $alias]} {
            set alias [uplevel 1 {namespace current}]::$alias
        }
        if {![string match ::* $cmd]} {
            set c [uplevel 1 [list namespace which $cmd]]
            if {$c eq ""} {
                return -code error "Could not resolve $cmd!"
            }
            set cmd $c
        }
        tailcall interp alias {} $alias {} $cmd {*}$args
    }

    proc unalias {args} {
        foreach cmd $args {
            interp alias {} [uplevel 1 [list namespace which $cmd]] {}
        }
    }

;# now we start:

    # The class of all classes ...
    oo::class create Metaclass {
        superclass oo::class
    }

    # .. has all the oo::define commands as methods.
    # they take an extra argument at the beginning: [$metaclass method $class name args body]
    #                                   .. compare: [oo::define $class method name args body]
    foreach cmd [info commands ::oo::define::*] {
        set tail [namespace tail $cmd]
        if {$tail eq "self"} continue

        oo::define Metaclass method $tail {cls args} [format {
            set cls [uplevel 1 [list namespace which $cls]]     ;# could avoid this with [tailcall]..
            debug log {defining %1$s on $cls}
            oo::define $cls %1$s {*}$args
        } [list $tail]]
    }

    # The base class of all classes is an instance of Metaclass and a subclass of oo::class.
    # Got that?  No, neither have I.  But play along .. it works.
    #
    # As an instance of Metaclass, it gets all the methods defined above (eg [Class export $cls $name ...]).
    #
    # As a subclass of oo::class, its instances are classes with no special features.
    #
    Metaclass create Class0 {

        superclass oo::class

        # Class's constructor takes a script, which it evaluates
        # in the new class's namespace, temporarily augmented
        # with aliases to all of its own methods.
        constructor {{script ""}} {
            set class [info object class [self]]    ;# not [self class] !
            debug log {creating $class [self]}

            set cmds [info object methods $class -all]
            foreach cmd $cmds {
                alias $cmd $class $cmd [self]
            }

            try $script finally [list unalias {*}$cmds]
        }
    }
    ;# This is a drop-in extension for oo::class.  It has some extra methods, which should
    ;# not get in the way next to the normally-used [$cls create] [$cls new] and [$cls destroy].

    ;# Its constructor (class initialiser) behaves slightly differently, but these changes should
    ;# not be able to impact any but the most pathological constructor scripts.  See below.

    ;# Costs only occur at class creation time, which should be insignificant unless your name
    ;# is hypnotoad.  The aliases exist only as long as they need to, and in the class object's
    ;# namespace where they shouldn't be able to affect anything but the class's initialisation
    ;# script.

    ;# Normally only one command exists in this namespace (as with any object's namespace): [my]
    ;# Commands from oo::Helpers are also in the path (self, next, nextto), but nothing else.


;# !!! There is one loss !!!
    ;#  [oo::define::self], normally an alias to ~ [oo::objdefine [self class]], is gone
    ;# since we're running in the constructor.  I don't think that's a big loss, since it's
    ;# a confusing name coincidence and rarely used.  It needs exposure under a better name,
    ;# like [class].

    ;# I think we could restore [self] as a method on Metaclass, but it strikes me as risky.
    ;# Maybe that's not the case.  But I'm not sure I like the pun.


    ;# Some useful extensions are immediately visible:
    ;#
    ;#  * restore [self]-like behaviour through a different name ([class])
    ;#  * add [uplevel 1 namespace current] to the path during the initialisation script
    ;#    in fact, leave it there.  I want it more often than not.
    ;#
    oo::define Metaclass method class {cls cmd args} {   ;# restoration of oo::define::self
        debug log {class $cmd $cls [info object class [self]]!}
        oo::objdefine $cls $cmd {*}$args
    }
    Metaclass create Class {
        superclass ::meta::Class0
        constructor args {
            set p [namespace path]
            namespace path [list {*}$p [uplevel 1 {namespace current}]]
            next {*}$args
            ;#namespace path $p
        }
    }

}

;# Well .. but so what?

if 1 {
    namespace path [list meta {*}[namespace path]]

    ;# The net effect is close to zero:  Class has methods forwarding to oo::define's
    ;# pseudo-methods, and its constructor runs the new class's initialisation script
    ;# in the class's own namespace, with appropriate aliases in the namespace as though 
    ;# you were really there.
    ;#
    ;# Creating a class works pretty much the same:
    Class create C1 {
        method bark args woof
        variable foo

        ;# except this is neat:
        debug log {Creating [self] in [namespace current] (eq [info object namespace [self]])}
        ;# oo::class initialisers run on oo::define!  These run in the class's own namespace.
        ;#
        ;# This is a fairly big deal, since that's where most creative commands like to write
        ;# (like [proc]).
    }

    ;# we get this for free, which is just as well because it seems more distracting than useful:
    Class method C1 foo {args} {set foo {*}$args}

    ;# notice that these methods don't get in the way, as the only (object) methods we normally 
    ;# use from a class are [$cls create] [$cls new] and sometimes [$cls destroy].
    ;# 
    ;# This is a different thing (I think) than "class methods" as they exist in other languages.
    ;# But the concept appears pretty weak to me, so I don't think much is lost.  Note also that 
    ;# other Tcl object systems (which?) have taken an interpretation of class methods (or "class 
    ;# subcommands"?) similar to this.

    ;# but the magic comes here:
    Metaclass create Fancy {
        method accessor {cls args} {        ;# remember the extra cls argument!
            set cls [uplevel 1 [list namespace which $cls]]     ;# remember this bit too!
            foreach name $args {
                my variable $cls $name
                my method $cls $name args [format {
                    set %s {*}$args
                } [list $name]]
            }
        }
    }

    ;# now we could just:
    #oo::objdefine Class mixin Fancy
    ;# but in the interest of neighbourliness, let's leave our nice Class alone and
    ;# mess with a derivative:
    Metaclass create Klass {
        superclass ::meta::Class
    }
    oo::objdefine Klass mixin Fancy
    ;# notice that this used objdefine, not define, because it's affecting the class and not its instances.
    ;# a strong case could be made for making this a (object) method of Class.

    ;# of course, we can also do it with oo::objdefine ... or uplevel!
    oo::objdefine Klass method public {cls cmd name args} {
        my $cmd $cls $name {*}$args
        my export $cls $name
    }
    oo::objdefine Klass method private {cls cmd name args} {
        debug what
        uplevel 1 [list $cmd $name {*}$args]
        uplevel 1 [list unexport $name]
    }

    ;# now we can use that like this:
    Klass accessor C1 bar baz

    ;# or the better way:
    Klass create C2 {
        constructor args {
            lassign $args frop quaz
        }
        accessor frop quaz

        class method bar bar bar

        private method shush sh shh
        public method Brum {} gogogo
    }

    ;# notice that C2's instances bear no sign of being metaclass-derived.  This is good.

    ;# what you just saw is a SAFE way to extend object creation.   While I request that you squint
    ;# past my mixin directly on Class, notice that [accessor] as defined here need not conflict with
    ;# any other extension's use of the same command!  No more fighting over oo::define.  Or even
    ;# scribbling on it - that's just rude.
}

# Having done this, it's tempting to try a lot more.  Sensible namespace behaviour for oo::object
# initialisers;  using [info object namespace oo::class]::my CreateWithNamespace;  much more.  But
# it's a twisty maze of passages all alike, so go gently.

