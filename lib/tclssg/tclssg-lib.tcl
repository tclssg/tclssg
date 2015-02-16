# Tclssg, a static website generator.
# Copyright (C) 2013, 2014, 2015 Danyil Bohdan.
# This code is released under the terms of the MIT license. See the file
# LICENSE for details.

proc file-join-not-empty args {
    if {[llength $args] == 0} {
        return ""
    } else {
        return [file join {*}$args]
    }
}

proc import-recursive {directory prefix imports} {
    dict for {key value} $imports {
        set path [file join $directory \
                [file-join-not-empty {*}$prefix] $key $key.tcl]
        source $path
        import-recursive $directory [concat $prefix $key] $value
    }
}

proc import {dir} {
    set imports {
        command {}
        debugger {}
        pages {}
        templating {
            cache {}
            interpreter {}
        }
        utils {}
    }

    import-recursive $dir {} $imports

    rename file-join-not-empty {}
    rename import-recursive {}
    rename import {}

    package provide tclssg-lib 0
}
