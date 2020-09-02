# Tclssg, a static website generator.
# Copyright (c) 2013, 2014, 2015, 2016, 2017, 2018, 2019, 2020
# D. Bohdan and contributors listed in AUTHORS. This code is released under
# the terms of the MIT license. See the file LICENSE for details.

namespace eval ::tclssg::pipeline::70-generate-feeds {
    proc transform {} {
        namespace path {
            ::tclssg
            ::tclssg::pipeline::50-generate-pages
            ::tclssg::pipeline::60-generate-tag-pages
        }

        set formats [lsort -unique [db config get {feeds formats} {}]]
        if {[db config get {rss enable} false] && {rss} ni $formats} {
            lappend formats rss
        }
        set formatInfo {
            json {
                template ::json-feed::render
                feedPath ::json-feed::path
                name {JSON Feed}
            }
            rss {
                template ::rss-feed::render
                feedPath ::rss-feed::rss-feed-path
                name RSS
            }
            twtxt {
                template ::twtxt-feed::render
                feedPath ::twtxt-feed::path
                name twtxt
            }
        }

        set interp 70-generate-feeds
        interpreter create $interp

        lassign [templates blog-index] blogIndexInput
        lassign [tag-index] tagIndexInput

        if {$blogIndexInput ne {%NULL%}} {
            foreach format $formats {
                if {![dict exist $formatInfo $format]} {
                    error "unknown feed format: \"$format\""
                }

                set pcd 10
                set postCount [expr {
                    $format eq {rss}
                    ? [rss-setting posts $pcd]
                    : [db config get {feeds posts} $pcd]
                }]
                unset pcd

                gen-blog-feed \
                    -blogIndexInput $blogIndexInput \
                    -feedPath [dict get $formatInfo $format feedPath] \
                    -formatName [dict get $formatInfo $format name] \
                    -interp $interp \
                    -postCount $postCount \
                    -template [dict get $formatInfo $format template] \
            }
        }

        if {[db config get {feeds tagFeeds} false]} {
            foreach tagPage [db::input::list tag-page] {
                set tag [db::settings::raw-mget \
                    [list $tagPage] \
                    tagPageTag \
                ]
                set pages [db::tags::inputs-with-tag $tag]

                foreach format $formats {
                    if {$format eq {rss} && ![rss-setting tagFeeds false]} {
                        continue
                    }

                    gen-tag-feed \
                        -feedPath [dict get $formatInfo $format feedPath] \
                        -formatName [dict get $formatInfo $format name] \
                        -interp $interp \
                        -pages $pages \
                        -tagIndexInput $tagIndexInput \
                        -tagPage $tagPage \
                        -template [dict get $formatInfo $format template] \
                }
            }
        }

        interp delete $interp
    }

    proc gen-blog-feed args {
        utils::named-args {
            -blogIndexInput blogIndexInput
            -feedPath feedPath
            -formatName formatName
            -interp interp
            -postCount postCount
            -template template
        }

        set lastFeedPost [expr { $postCount - 1 }]
        set posts [lrange \
            [db settings inputs-with-true-setting \
                blogPost \
                $blogIndexInput \
            ] \
            0 \
            $lastFeedPost \
        ]

        set output [interp eval \
            $interp \
            [list $feedPath $blogIndexInput {}] \
        ]

        gen \
            -interp $interp \
            -template $template \
            -input $blogIndexInput \
            -output $output \
            -extraArticles $posts \
            -paginate 0 \
            -logScript [format {apply {{input output} {
                ::tclssg::log::info "generating blog feed [list $output] (%s)"
            }}} $formatName]
    }

    proc gen-tag-feed args {
        utils::named-args {
            -feedPath feedPath
            -formatName formatName
            -interp interp
            -pages pages
            -tagIndexInput tagIndexInput
            -tagPage tagPage
            -template template
        }

        set output [interp eval \
            $interp \
            [list $feedPath $tagPage {}] \
        ]

        gen \
            -interp $interp \
            -template $template \
            -input $tagIndexInput \
            -output $output \
            -extraArticles $pages \
            -paginate 0 \
            -templateExtras [list -tagPage $tagPage] \
            -logScript [format {apply {{input output} {
                ::tclssg::log::info "generating tag feed [list $output] (%s)"
            }}} $formatName]
    }

    proc rss-setting {key default} {
        return [db config get \
            [list rss $key] \
            [db config get [list feeds $key] \
                           $default]]
    }
}
