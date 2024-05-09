# Tclssg, a static website generator.
# Copyright (c) 2013-2019
# D. Bohdan and contributors listed in AUTHORS. This code is released under
# the terms of the MIT license. See the file LICENSE for details.

set ::footnotes {}
set ::footnoteSuffixes {}

# Return the footnote number that corresponds to the label $label.
proc footnote-number label {
    return [expr {
        [lsearch $::footnotes $label] / 2 + 1
    }]
}

# Return a website-unique id for a footnote or a footnote link.
proc footnote-id {label {link 0}} {
    set n [footnote-number $label]

    # Generate a page-unique footnote suffix that cannot be mistaken for
    # a footnote number.
    if {![dict exists $::footnoteSuffixes $::input]} {
        dict set ::footnoteSuffixes \
                 $::input \
                 -[string range [sha256 -hex $::input] end-3 end]
    }

    set suffix [dict get $::footnoteSuffixes $::input]
    if {$link} {
        return "footnote-$n-link$suffix"
    } else {
        return "footnote-$n$suffix"
    }
}

# Return a link to an existing footnote by its label.
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
    dict set ::footnotes $label [inline-markdown-to-html $markdown]
    return [footnote-link $label]
}

# Return (as an HTML list) and empty all stored footnotes.
# This is typically used at the end of a page.
proc footnotes {} {
    set result {<ol class="footnotes">}
    dict for {label footnote} $::footnotes {
        append result "<li class=\"footnote\" id=\"[footnote-id \
                $label 0]\">$footnote <a href=\"#[footnote-id \
                $label 1]\">↩</a></li>"
    }
    append result </ol>

    set ::footnotes {}

    return $result
}
