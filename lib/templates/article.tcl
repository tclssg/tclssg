# Tclssg, a static website generator.
# Copyright (c) 2013, 2014, 2015, 2016, 2017, 2018, 2019, 2020
# D. Bohdan and contributors listed in AUTHORS. This code is released under
# the terms of the MIT license. See the file LICENSE for details.

namespace eval ::article {}
proc ::article::render args {
    named-args {
        -articleInput   articleInput
        -abbreviate     {abbreviate 1}
        -collection     collection
        -collectionTop  collectionTop
        -content        content
        -root           root
    }
    set title [title $collection $collectionTop]
    set headerBlock [author][date]

    set output {}
    if {($content ne "") || ($title ne "") || ($headerBlock ne "")} {
        if {$collection && !$collectionTop} {
            append output <article>
        }
        append output [article-setting {article top} {}]
        append output <header>$title
        if {$headerBlock ne ""} {
            append output "<div class=\"page-info\">$headerBlock</div>"
        }
        append output </header>
        append output [abbreviate-article $content $abbreviate ]
        append output [tag-list]
        append output [article-setting {article bottom} {}]
        if {$collection && !$collectionTop} {
            append output </article>
        }
    }
    return $output
}

namespace eval ::article {
    proc lc text {
        upvar 1 articleInput articleInput

        localization get [article-setting locale en_US] ::article $text
    }

    proc author {} {
        upvar 1 articleInput articleInput

        set author [article-setting author]
        if {($author eq {%NULL%}) || ![article-setting {show author} 1]} {
            return {}
        } else {
            return [format {<address class="author">%s</address>} $author]
        }
    }

    proc title {collection collectionTop} {
        upvar 1 articleInput articleInput \
                root root

        set title [article-setting title {}]

        if {$title eq {} ||
            ![article-setting {show title} 1] ||
            ![article-setting {show articleTitle} 1]} {
            return {}
        }

        set result {<h1 class="page-title">}

        if {[article-setting blogPost 0] &&
            $collection &&
            !$collectionTop} {
            append result [rel-link [article-output] $title]
        } else {
            append result [entities $title]
        }

        append result {</h1>}

        return $result
    }

    proc article-output {} {
        upvar 1 articleInput articleInput

        set output [input-to-output-path $articleInput \
                                         -includeIndexHtml 0]
        return $output
    }

    proc format-date {htmlClass dateKey timestampKey} {
        upvar 1 articleInput articleInput

        set date [article-setting $dateKey]
        set timestamp [article-setting $timestampKey]
        set tz [article-setting {timezone date} {}]
        set formatOptions [expr {
            $tz eq {} ? {} : [list -timezone $tz]
        }]

        if {$date eq {%NULL%}} {
            return {}
        } else {
            set datetime [clock format [lindex $timestamp 0] \
                                 -format [lindex $timestamp 1] \
                                 {*}$formatOptions \
            ]
            if {[string first %z [lindex $timestamp 1]] == -1
                && $tz ne {}} {
                append datetime [clock format 0 -format %z -timezone $tz]
            }

            set text {}
            if {[article-setting {timezone show} 0]} {
                set text " [article-setting {timezone text}]"
            }

            return "<time datetime=\"$datetime\"\
                          class=\"$htmlClass\">$date$text</time>"
        }
    }

    # Article creation and modification date.
    proc date {} {
        upvar 1 articleInput articleInput

        set resultList {}
        if {[article-setting {show date} 1]} {
            set dateF [format-date date date timestamp]
            if {$dateF ne ""} {
                lappend resultList $dateF
            }
            if {[article-setting {show modified} 1]} {
                set modDateF [format-date modified modified modifiedTimestamp]
                if {$modDateF ne ""} {
                    lappend resultList $modDateF
                }
            }
        }
        switch -exact -- [llength $resultList] {
            0 {
                return ""
            }
            1 {
                return [format [lc {Published %1$s}] $dateF]
            }
            default {
                return [format [lc {Published %1$s, updated %2$s}] $dateF $modDateF]
            }
        }
    }

    proc abbreviate-article {content abbreviate {absoluteLink 0}} {
        upvar 1 articleInput articleInput \
                root root

        if {$abbreviate} {
            set link [link-path [article-output] $absoluteLink]
            set moreMarkup [article-setting {more markup} \
                                            {(<a href="$link">$text</a>)}]
            set moreText [article-setting {more text} [lc {read more}]]
            if {[regexp {(.*?)<!-- *more *-->} $content _ content]} {
                append content \
                       [string map [list \$link [entities $link] \
                                         \$text [entities $moreText]] \
                                   $moreMarkup]
            }
        }
        return $content
    }

    proc tag-list {} {
        upvar 1 articleInput articleInput \
                root root

        set tags [db tags get $articleInput ]
        if {$tags eq {}} {
            return {}
        } else {
            set links {}
            foreach tag $tags {
                lappend links "<li class=\"tag\">[tag-page-link $tag]</li>"
            }

            return "<nav class=\"container-fluid tags\">[format \
                    [lc {Tagged: <ul>%1$s</ul>}] [join \
                    $links]]</nav><!-- tags -->"
        }
    }
}
