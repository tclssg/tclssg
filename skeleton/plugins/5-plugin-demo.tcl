# Tclssg, a static website generator.
# Copyright (C) 2013, 2014, 2015, 2016, 2017, 2018 dbohdan.
# This code is released under the terms of the MIT license. See the file
# LICENSE for details.

namespace eval ::tclssg::pipeline::5-plugin-demo {
    namespace path ::tclssg

    proc transform {} {
        log::info {running demo plugin}
        db input add fake/hello.txt {} {} [clock seconds]
        db output add hello.txt fake/hello.txt {Hello, World!}
    }
}
