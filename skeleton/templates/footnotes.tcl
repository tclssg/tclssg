# Tclssg, a static website generator.
# Copyright (C) 2013, 2014, 2015 Danyil Bohdan.
# This code is released under the terms of the MIT license. See the file
# LICENSE for details.

set ::footnotes {}
set ::footnoteSuffix {}

# Return the footnote number that corresponds to the label $label.
proc footnote-number {label} {
    return [expr {
        [lsearch $::footnotes $label] / 2 + 1
    }]
}

# Generate a website-unique footnote id or footnote link id.
proc footnote-id {label {link 0}} {
    set n [footnote-number $label]

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

# Generate a link to an existing footnote by its label.
proc footnote-link label {
    return "<span class=\"footnote-link\" id=\"[footnote-id \
        $label 1]\"><a href=\"#[footnote-id \
        $label 0]\"><sup>\[[footnote-number $label]\]</sup></a></span>"
}

# Add a new footnote.
proc footnote args {
    switch -exact -- [llength $args] {
        1 {
            lassign $args markdown
            set label [expr {
                [llength [dict keys $::footnotes]] + 1
            }]
        }
        2 {
            lassign $args label markdown
            # Avoid conflicts with automatically assigned labels.
            if {[string is integer -strict $label]} {
                error "custom footnote labels can not be integer numbers"
            }
        }
        default {
            error {wrong # args: should be "footnote ?label? markdown"}
        }
    }
    if {[dict exists $::footnotes $label]} {
        error "footnote \"$label\" already exists"
    }
    dict set ::footnotes $label [markdown-to-html $markdown]
    return [footnote-link $label]
}

# Generate a list of all footnotes. This is typically used at the end of a page.
proc footnotes {} {
    set result {<ol class="footnotes">}
    dict for {label footnote} $::footnotes {
        append result "<li class=\"footnote\" id=\"[footnote-id \
                $label 0]\">$footnote <a href=\"#[footnote-id \
                $label 1]\">↩</a></li>"
    }
    append result {</ol>}
}
