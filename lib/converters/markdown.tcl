# Tclssg, a static website generator.
# Copyright (c) 2013-2018, 2024
# D. Bohdan and contributors listed in AUTHORS. This code is released under
# the terms of the MIT license. See the file LICENSE for details.

namespace eval ::tclssg::converters::markdown {
    namespace export *
    namespace ensemble create
    namespace path ::tclssg

    # Convert raw Markdown to HTML.
    proc markdown-to-html {markdown} {
        set converter [db config get {markdown converter}]
        set tabs [db config get {markdown tabs} 0]
        if {$converter in {{} {%NULL%}}} {
            return [::Markdown::convert $markdown $tabs]
        } else {
            return [exec {*}$converter << $markdown]
        }
    }

    proc inline-markdown-to-html {text} {
        # Strip paragraph wrapping; we assume to be in an inline context.
        regexp ^<p>(.*)</p>$ [markdown-to-html $text] _ html
        return $html
    }
}
