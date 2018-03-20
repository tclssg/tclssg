# Tclssg, a static website generator.
# Copyright (c) 2013, 2014, 2015, 2016, 2017, 2018
# dbohdan and contributors listed in AUTHORS. This code is released under
# the terms of the MIT license. See the file LICENSE for details.

namespace eval ::tclssg::pipeline::5-plugin-demo {
    namespace path ::tclssg
    lappend ::tclssg::config::schema greeting

    proc transform {} {
        log::info {running demo plugin}
        db input add fake/hello.txt {} {} [clock seconds]
        set greeting [db config get greeting {Hello, %s!}]
        db output add hello.txt fake/hello.txt [format $greeting World]
    }
}
