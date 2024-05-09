# Tclssg, a static website generator.
# Copyright (c) 2013-2020
# D. Bohdan and contributors listed in AUTHORS. This code is released under
# the terms of the MIT license. See the file LICENSE for details.

namespace eval ::tclssg::pipeline::50-plugin-demo {
    namespace path ::tclssg
    lappend ::tclssg::config::schema greeting

    proc transform {} {
        set me [namespace tail [namespace current]]
        log::info [list running demo plugin $me]

        db input add \
            -type demo \
            -file fake/hello.txt \
            -timestamp [clock seconds]
        set greeting [db config get greeting {Hello, %s!}]
        db output add hello.txt fake/hello.txt [format $greeting World]
    }
}
