# Tclssg, a static website generator.
# Copyright (C) 2013, 2014, 2015 Danyil Bohdan.
# This code is released under the terms of the MIT license. See the file
# LICENSE for details.

set ::footnotes {}
set ::footnoteSuffix {}

proc footnote-id {n {link 0}} {
    # Generate a unique footnote suffix that cannot be mistaken for a footnote
    # number by applying a linear bijective map from 0..65535 to 0..65535 to
    # the page id and then formatting the result as four hex digits.
    if {$::footnoteSuffix eq ""} {
        set ::footnoteSuffix -[format %04x [expr {
            ($::currentPageId * 7459 + 23627) % 0x10000
        }]]
    }

    set suffix $::footnoteSuffix
    if {$link} {
        return "footnote-$n-link$suffix"
    } else {
        return "footnote-$n$suffix"
    }
}

proc footnote {markdown} {
    lappend ::footnotes [markdown-to-html $markdown]
    set i [llength $::footnotes]
    return "<span class=\"footnote-link\" id=\"[footnote-id \
            $i 1]\"><a href=\"#[footnote-id \
            $i 0]\"><sup>\[$i\]</sup></a></span>"
}

proc footnotes {} {
    set result {<ol class="footnotes">}
    set i 1
    foreach footnote $::footnotes {
        append result "<li class=\"footnote\" id=\"[footnote-id \
                $i 0]\">$footnote <a href=\"#[footnote-id $i 1]\">↩</a></li>"
        incr i
    }
    append result {</ol>}
}
