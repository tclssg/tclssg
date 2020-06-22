# Tclssg, a static website generator.
# Copyright (c) 2020
# D. Bohdan and contributors listed in AUTHORS. This code is released under
# the terms of the MIT license. See the file LICENSE for details.

namespace eval ::tclssg::pipeline::10-register-template-command {
    namespace path ::tclssg

    proc foo {} {
        return {This was returned from a custom command available in templates\
                and macros.}
    }

    proc transform {} {
        set me [namespace tail [namespace current]]
        log::info [list running demo plugin $me]
        log::debug $::tclssg::interpreter::aliases

        dict set ::tclssg::interpreter::aliases \
                 [namespace current]::foo \
                 foo
    }
}
