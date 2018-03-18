# Tclssg, a static website generator.
# Copyright (C) 2013, 2014, 2015, 2016, 2017, 2018 dbohdan.
# This code is released under the terms of the MIT license. See the file
# LICENSE for details.

namespace eval ::tclssg::converters::markdown {
    namespace export *
    namespace ensemble create
    namespace path ::tclssg

    # Convert raw Markdown to HTML.
    proc markdown-to-html {markdown} {
        set converter [db settings get config {markdown converter}]
        if {$converter in {{} {%NULL%}}} {
            return [::Markdown::convert $markdown]
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
