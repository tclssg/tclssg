# Tclssg, a static website generator.
# Copyright (C) 2013, 2014, 2015, 2016, 2017, 2018 dbohdan.
# This code is released under the terms of the MIT license. See the file
# LICENSE for details.

namespace eval ::article {}
proc ::article::render {} {
    set title [title]
    set headerBlock [author][date]

    set output {}
    if {($::content ne "") || ($title ne "") || ($headerBlock ne "")} {
        if {$::collection && !$::collectionTop} {
            append output <article>
        }
        append output [article-setting {article top} {}]
        append output <header>$title
        if {$headerBlock ne ""} {
            append output "<div class=\"page-info\">$headerBlock</div>"
        }
        append output </header>
        append output [abbreviate-article $::content $::abbreviate ]
        append output [tag-list]
        append output [article-setting {article bottom} {}]
        if {$::collection && !$::collectionTop} {
            append output </article>
        }
    }
    return $output
}

namespace eval ::article {    
    proc article-setting {key {default %NULL%}} {
        return [file-setting $::articleInput $key $default]
    }

    proc author {} {
        set author [article-setting author]
        if {($author eq {%NULL%}) || ![article-setting showAuthor 1]} {
            return {}
        } else {
            return [format {<address class="author">%s</address>} $author]
        }
    }

    proc title {} {
        set title [entities [article-setting title {}]]
        if {($title eq {}) || ![article-setting showTitle 1] ||
            ![article-setting showArticleTitle 1]} {
            return {}
        } else {
            set result {<h1 class="page-title">}
            if {[article-setting blogPost 0] &&
                $::collection &&
                !$::collectionTop} {
                append result [rel-link [article-output] $title]
            } else {
                append result $title
            }
            append result {</h1>}
            return $result            
        }
    }

    proc article-output {} {
        set output [input-to-output-path $::articleInput \
                                         -relativeOutput 1 \
                                         -includeIndexHtml 0]
        return $output
    }

    proc format-date {htmlClass dateKey timestampKey} {
        set date [article-setting $dateKey]
        set timestamp [article-setting $timestampKey]

        if {$date eq {%NULL%}} {
            return {}
        } else {
            set dt [clock format [lindex $timestamp 0] \
                                 -format [lindex $timestamp 1]]
            return "<time datetime=\"$dt\" class=\"$htmlClass\">$date</time>"
        }
    }

    proc date {} {
        # Article creation and modification date.
        set resultList {}
        if {[article-setting showDate 1]} {
            set dateF [format-date date date timestamp]
            if {$dateF ne ""} {
                lappend resultList $dateF
            }
            if {[article-setting showModifiedDate 1]} {
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
                return [format [mc {Published %1$s}] $dateF]
            }
            default {
                return [format [mc {Published %1$s, updated %2$s}] $dateF $modDateF]
            }
        }
    }

    proc abbreviate-article {content {abbreviate 0}} {
        if {$abbreviate} {
            set link [file join $::root [article-output]]
            set moreText [article-setting moreText \
                                          {(<a href="$link">read more</a>)}]
            if {[regexp {(.*?)<!-- *more *-->} $content _ content]} {
                append content \
                       [string map [list \$link [entities $link]] $moreText]
            }
        }
        return $content
    }

    proc tag-list {} {
        set tags [db tags get $::articleInput ]
        if {$tags eq {}} {
            return {}
        } else {
            set links {}
            foreach tag $tags {
                lappend links "<li class=\"tag\">[tag-page-link $tag]</li>"
            }

            return "<nav class=\"container-fluid tags\">[format \
                    [mc {Tagged: <ul>%1$s</ul>}] [join \
                    $links]]</nav><!-- tags -->"
        }
    }
}
