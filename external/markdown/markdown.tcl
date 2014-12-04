#
# Caius Functional Testing Framework
#
# Copyright (c) 2013, Tobias Koch <tobias.koch@gmail.com>
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without modifi-
# cation, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice,
#    this list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDER ``AS IS'' AND ANY EXPRESS
# OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
# OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN
# NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
# INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUD-
# ING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF
# USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUD-
# ING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFT-
# WARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#

## \file
# \brief Functions for converting markdown to HTML.

##
# \brief Functions for converting markdown to HTML.
#
namespace eval Markdown {

    namespace export convert

    ##
    #
    # Converts text written in markdown to HTML.
    #
    # @param markdown  currently takes as a single argument the text in markdown
    #
    # The output of this function is only a fragment, not a complete HTML
    # document. The format of the output is generic XHTML.
    #
    proc convert {markdown} {
        append markdown \n

        regsub -all {\r\n}  $markdown \n     markdown
        regsub -all {\r}    $markdown \n     markdown
        regsub -all {\t}    $markdown {    } markdown
        set markdown [string trim $markdown]

        # COLLECT REFERENCES
        array set ::Markdown::_references [collect_references markdown]

        # PROCESS
        return [apply_templates markdown]
    }

    ## \private
    proc collect_references {markdown_var} {
        upvar $markdown_var markdown

        set lines [split $markdown \n]
        set no_lines [llength $lines]
        set index 0

        array set references {}

        while {$index < $no_lines} {
            set line [lindex $lines $index]

            if {[regexp \
                {^[ ]{0,3}\[(.*?[^\\])\]:\s+(\S+)(?:\s+(([\"\']).*[^\\]\4|\(.*[^\\]\))\s*$)?} \
                $line match ref link title]} \
            {
                set title [string trim [string range $title 1 end-1]]
                if {$title eq {}} {
                    set next_line [lindex $lines [expr $index + 1]]

                    if {[regexp \
                        {^(?:\s+(?:([\"\']).*[^\\]\1|\(?:.*[^\\]\))\s*$)} \
                        $next_line]} \
                    {
                        set title [string range [string trim $next_line] 1 end-1]
                        incr index
                    }
                }
                set ref [string tolower $ref]
                set link [string trim $link {<>}]
                set references($ref) [list $link $title]
            }

            incr index
        }

        return [array get references]
    }

    ## \private
    proc apply_templates {markdown_var {parent {}}} {
        upvar $markdown_var markdown

        set lines    [split $markdown \n]
        set no_lines [llength $lines]
        set index    0
        set result   {}

        set ul_match {^[ ]{0,3}(?:\*|-|\+) }
        set ol_match {^[ ]{0,3}\d+\. }

        # PROCESS MARKDOWN
        while {$index < $no_lines} {
            set line [lindex $lines $index]

            switch -regexp $line {
                {^\s*$} {
                    # EMPTY LINES
                    if {![regexp {^\s*$} [lindex $lines [expr $index - 1]]]} {
                        append result "\n\n"
                    }
                    incr index
                }
                {^[ ]{0,3}\[(.*?[^\\])\]:\s+(\S+)(?:\s+(([\"\']).*[^\\]\4|\(.*[^\\]\))\s*$)?} {
                    set next_line [lindex $lines [expr $index + 1]]

                    if {[regexp \
                        {^(?:\s+(?:([\"\']).*[^\\]\1|\(?:.*[^\\]\))\s*$)} \
                        $next_line]} \
                    {
                        incr index
                    }

                    incr index
                }
                {^[ ]{0,3}-[ ]*-[ ]*-[- ]*$} -
                {^[ ]{0,3}_[ ]*_[ ]*_[_ ]*$} -
                {^[ ]{0,3}\*[ ]*\*[ ]*\*[\* ]*$} {
                    # HORIZONTAL RULES
                    append result "<hr/>"
                    incr index
                }
                {^[ ]{0,3}#{1,6}} {
                    # ATX STYLE HEADINGS
                    set h_level 0
                    set h_result {}

                    while {$index < $no_lines && ![is_empty_line $line]} {
                        incr index

                        if {!$h_level} {
                            regexp {^\s*#+} $line m
                            set h_level [string length [string trim $m]]
                        }

                        lappend h_result $line

                        set line [lindex $lines $index]
                    }

                    set h_result [\
                        parse_inline [\
                            regsub -all {^\s*#+\s*|\s*#+\s*$} [join $h_result \n] {} \
                        ]\
                    ]

                    append result "<h$h_level>$h_result</h$h_level>"
                }
                {^[ ]{0,3}\>} {
                    # BLOCK QUOTES
                    set bq_result {}

                    while {$index < $no_lines} {
                        incr index

                        lappend bq_result [regsub {^[ ]{0,3}\>[ ]?} $line {}]

                        if {[is_empty_line [lindex $lines $index]]} {
                            set eoq 0

                            for {set peek $index} {$peek < $no_lines} {incr peek} {
                                set line [lindex $lines $peek]

                                if {![is_empty_line $line]} {
                                    if {![regexp {^[ ]{0,3}\>} $line]} {
                                        set eoq 1
                                    }
                                    break
                                }
                            }

                            if {$eoq} { break }
                        }

                        set line [lindex $lines $index]
                    }
                    set bq_result [string trim [join $bq_result \n]]

                    append result <blockquote>\n \
                                    [apply_templates bq_result] \
                                  \n</blockquote>
                }
                {^\s{4,}\S+} {
                    # CODE BLOCKS
                    set code_result {}

                    while {$index < $no_lines} {
                        incr index

                        lappend code_result [html_escape [\
                            regsub {^    } $line {}]\
                        ]

                        set eoc 0
                        for {set peek $index} {$peek < $no_lines} {incr peek} {
                            set line [lindex $lines $peek]

                            if {![is_empty_line $line]} {
                                if {![regexp {^\s{4,}} $line]} {
                                    set eoc 1
                                }
                                break
                            }
                        }

                        if {$eoc} { break }

                        set line [lindex $lines $index]
                    }
                    set code_result [string trim [join $code_result \n]]

                    append result <pre><code> $code_result </code></pre>
                }
                {^[ ]{0,3}(?:\*|-|\+) |^[ ]{0,3}\d+\. } {
                    # LISTS
                    set list_type ul
                    set list_match $ul_match
                    set list_result {}

                    if {[regexp $ol_match $line]} {
                        set list_type ol
                        set list_match $ol_match
                    }

                    set last_line AAA

                    while {$index < $no_lines} {
                        set item_result {}

                        if {![regexp $list_match [lindex $lines $index]]} {
                            break
                        }

                        set in_p 1
                        set p_count 1

                        if {[is_empty_line $last_line]} { incr p_count }

                        for {set peek $index} {$peek < $no_lines} {incr peek} {
                            set line [lindex $lines $peek]

                            if {$peek == $index} {
                                set line [regsub "$list_match\\s*" $line {}]
                                set in_p 1
                            }

                            if {[is_empty_line $line]} {
                                set in_p 0
                            }\
                            elseif {[regexp {^    } $line]} {
                                if {!$in_p} {
                                    incr p_count
                                }
                                set in_p 1
                            }\
                            elseif {[regexp $list_match $line]} {
                                if {!$in_p} {
                                    incr p_count
                                }
                                break
                            }\
                            elseif {!$in_p} {
                                break
                            }

                            set last_line $line
                            lappend item_result [regsub {^    } $line {}]
                        }

                        set item_result [join $item_result \n]

                        if {$p_count > 1} {
                            set item_result [apply_templates item_result li]
                        } else {
                            if {[regexp -lineanchor \
                                {(\A.*?)((?:^[ ]{0,3}(?:\*|-|\+) |^[ ]{0,3}\d+\. ).*\Z)} \
                                $item_result \
                                match para rest]} \
                            {
                                set item_result [parse_inline $para]
                                append item_result [apply_templates rest]
                            } else {
                                set item_result [parse_inline $item_result]
                            }
                        }

                        lappend list_result "<li>$item_result</li>"
                        set index $peek
                    }

                    append result <$list_type>\n \
                                    [join $list_result \n] \
                                </$list_type>\n\n
                }
                {^<(?:p|div|h[1-6]|blockquote|pre|table|dl|ol|ul|script|noscript|form|fieldset|iframe|math|ins|del)} {
                    # HTML BLOCKS
                    set re_htmltag {<(/?)(\w+)(?:\s+\w+=\"[^\"]+\")*\s*>}
                    set buffer {}

                    while {$index < $no_lines} \
                    {
                        while {$index < $no_lines} \
                        {
                            incr index

                            append buffer $line \n

                            if {[is_empty_line $line]} {
                                break
                            }

                            set line [lindex $lines $index]
                        }

                        set tags [regexp -inline -all $re_htmltag  $buffer]
                        set stack_count 0

                        foreach {match type name} $tags {
                            if {$type eq {}} {
                                incr stack_count +1
                            } else {
                                incr stack_count -1
                            }
                        }

                        if {$stack_count == 0} { break }
                    }

                    append result $buffer
                }
                default {
                    # PARAGRAPHS AND SETTEXT STYLE HEADERS
                    set p_type p
                    set p_result {}

                    while {($index < $no_lines) && ![is_empty_line $line]} \
                    {
                        incr index

                        switch -regexp $line {
                            {^[ ]{0,3}=+$} {
                                set p_type h1
                                break
                            }
                            {^[ ]{0,3}-+$} {
                                set p_type h2
                                break
                            }
                            {^[ ]{0,3}(?:\*|-|\+) |^[ ]{0,3}\d+\. } {
                                if {$parent eq {li}} {
                                    incr index -1
                                    break
                                } else {
                                    lappend p_result $line
                                }
                            }
                            {^[ ]{0,3}-[ ]*-[ ]*-[- ]*$} -
                            {^[ ]{0,3}_[ ]*_[ ]*_[_ ]*$} -
                            {^[ ]{0,3}\*[ ]*\*[ ]*\*[\* ]*$} -
                            {^[ ]{0,3}#{1,6}} \
                            {
                                incr index -1
                                break
                            }
                            default {
                                lappend p_result $line
                            }
                        }

                        set line [lindex $lines $index]
                    }

                    set p_result [\
                        parse_inline [\
                            string trim [join $p_result \n]\
                        ]\
                    ]

                    if {[is_empty_line [regsub -all {<!--.*?-->} $p_result {}]]} {
                        # Do not make a new paragraph for just comments.
                        append result $p_result
                    } else {
                        append result "<$p_type>$p_result</$p_type>"
                    }
                }
            }
        }

        return $result
    }

    ## \private
    proc parse_inline {text} {
        set text [regsub -all -lineanchor {[ ]{2,}$} $text <br/>]

        set index 0
        set result {}

        set re_backticks   {\A`+}
        set re_whitespace  {\s}
        set re_inlinelink  {\A\!?\[((?:[^\]\\]|\\\])*)\]\s*\(((?:[^\)\\]|\\\))*)\)}
        set re_reflink     {\A\!?\[((?:[^\]\\]|\\\])*)\]\s*\[((?:[^\]\\]|\\\])*?)\]}
        set re_urlandtitle {\A(\S+)(?:\s+([\"'])((?:[^\"\'\\]|\\\2)*)\2)?}
        set re_htmltag     {\A</?\w+\s*>|\A<\w+(?:\s+\w+=\"[^\"]+\")*\s*/?>}
        set re_autolink    {\A<(?:(\S+@\S+)|(\S+://\S+))>}
        set re_comment     {\A<!--.*?-->}
        set re_entity      {\A\&\S+;}

        while {[set chr [string index $text $index]] ne {}} {
            switch $chr {
                "\\" {
                    # ESCAPES
                    set next_chr [string index $text [expr $index + 1]]

                    if {[string first $next_chr {\`*_\{\}[]()#+-.!}] != -1} {
                        set chr $next_chr
                        incr index
                    }
                }
                {_} -
                {*} {
                    # EMPHASIS
                    if {[regexp $re_whitespace [string index $result end]] &&
                        [regexp $re_whitespace [string index $text [expr $index + 1]]]} \
                    {
                        #do nothing
                    } \
                    elseif {[regexp -start $index \
                        "\\A(\\$chr{1,2})((?:\[^\\$chr\\\\]|\\\\\\$chr)*)\\1" \
                        $text m del sub]} \
                    {
                        if {[string length $del] > 1} {
                            set tag strong
                        } else {
                            set tag em
                        }

                        append result "<$tag>[parse_inline $sub]</$tag>"
                        incr index [string length $m]
                        continue
                    }
                }
                {`} {
                    # CODE
                    regexp -start $index $re_backticks $text m
                    set start [expr $index + [string length $m]]

                    if {[regexp -start $start -indices $m $text m]} {
                        set stop [expr [lindex $m 0] - 1]

                        set sub [string trim [string range $text $start $stop]]

                        append result "<code>[html_escape $sub]</code>"
                        set index [expr [lindex $m 1] + 1]
                        continue
                    }
                }
                {!} -
                {[} {
                    # LINKS AND IMAGES
                    set ref_type link

                    if {$chr eq {!}} {
                        set ref_type img
                    }

                    set match_found 0

                    if {[regexp -start $index $re_reflink $text m txt lbl]} {
                        # REFERENCED
                        incr index [string length $m]

                        if {$lbl eq {}} { set lbl $txt }

                        lassign $::Markdown::_references([string tolower $lbl]) url title

                        set url [html_escape [string trim $url {<> }]]
                        set txt [parse_inline $txt]
                        set title [parse_inline $title]

                        set match_found 1
                    } elseif {[regexp -start $index $re_inlinelink $text m txt url_and_title]} {
                        # INLINE
                        incr index [string length $m]

                        set url_and_title [string trim $url_and_title]
                        set del [string index $url_and_title end]

                        if {[string first $del "\"'"] >= 0} {
                            regexp $re_urlandtitle $url_and_title m url del title
                        } else {
                            set url $url_and_title
                            set title {}
                        }

                        set url [html_escape [string trim $url {<> }]]
                        set txt [parse_inline $txt]
                        set title [parse_inline $title]

                        set match_found 1
                    }

                    # PRINT IMG, A TAG
                    if {$match_found} {
                        if {$ref_type eq {link}} {
                            if {$title ne {}} {
                                append result "<a href=\"$url\" title=\"$title\">$txt</a>"
                            } else {
                                append result "<a href=\"$url\">$txt</a>"
                            }
                        } else {
                            if {$title ne {}} {
                                append result "<img src=\"$url\" alt=\"$txt\" title=\"$title\"/>"
                            } else {
                                append result "<img src=\"$url\" alt=\"$txt\"/>"
                            }
                        }

                        continue
                    }
                }
                {<} {
                    # HTML TAGS, COMMENTS AND AUTOLINKS
                    if {[regexp -start $index $re_comment $text m]} {
                        append result $m
                        incr index [string length $m]
                        continue
                    } elseif {[regexp -start $index $re_autolink $text m email link]} {
                        if {$link ne {}} {
                            append result "<a href=\"$link\">$link</a>"
                        } else {
                            set mailto_prefix "mailto:"
                            if {![regexp "^${mailto_prefix}(.*)" $email mailto email]} {
                                # $email does not contain the prefix "mailto:".
                                set mailto "mailto:$email"
                            }
                            append result "<a href=\"$mailto\">$email</a>"
                        }
                        incr index [string length $m]
                        continue
                    } elseif {[regexp -start $index $re_htmltag $text m]} {
                        append result $m
                        incr index [string length $m]
                        continue
                    }

                    set chr [html_escape $chr]
                }
                {&} {
                    # ENTITIES
                    if {[regexp -start $index $re_entity $text m]} {
                        append result $m
                        incr index [string length $m]
                        continue
                    }

                    set chr [html_escape $chr]
                }
                {-} {
                    # EMDASH
                    if {[string index $text [expr $index + 1]] eq {-}} {
                        append result {&#8212;}
                        incr index 2
                        continue
                    }
                }
                {>} -
                {'} -
                "\"" {
                    # OTHER SPECIAL CHARACTERS
                    set chr [html_escape $chr]
                }
                default {}
            }

            append result $chr
            incr index
        }

        return $result
    }

    ## \private
    proc is_empty_line {line} {
        return [regexp {^\s*$} $line]
    }

    ## \private
    proc html_escape {text} {
        return [string map {<!-- <!-- --> --> & &amp; < &lt; > &gt; ' &apos; \" &quot;} $text]
    }
}

