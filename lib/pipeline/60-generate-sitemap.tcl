# Tclssg, a static website generator.
# Copyright (c) 2013, 2014, 2015, 2016, 2017, 2018, 2019
# dbohdan and contributors listed in AUTHORS. This code is released under
# the terms of the MIT license. See the file LICENSE for details.

# Add an XML sitemap output listing the outputs of all Markdown inputs that
# don't have showInCollections 0.
namespace eval ::tclssg::pipeline::60-generate-sitemap {
    namespace path ::tclssg

    proc transform {} {
        if {![db config get {sitemap enable} 0]} return
        log::info {generating sitemap}
        set sitemap [make-sitemap]

        db input add \
            -type sitemap \
            -file sitemap \
            -timestamp [db config get buildTimestamp]
        db output add sitemap.xml sitemap $sitemap
    }

    # Generate a sitemap for the static website. This requires the setting
    # "url" to be set in the website config.
    proc make-sitemap {} {
        set outputDir [db config get outputDir]
        set header [utils::trim-indentation {
        <?xml version="1.0" encoding="UTF-8"?>
        <urlset
              xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"
              xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
              xsi:schemaLocation="http://www.sitemaps.org/schemas/sitemap/0.9
                    http://www.sitemaps.org/schemas/sitemap/0.9/sitemap.xsd">
        %s</urlset>
        }]

        set entry [utils::trim-indentation {
            <url>
              <loc>%s</loc>%s
            </url>
        }]

        db transaction {
            set result {}
            set url [db config get url]
            if {$url eq {%NULL%}} {
                error {can't generate a sitemap without a base URL set\
                       in the config}
            }
            # Exclude from the sitemap pages that are hidden from collections.
            db eval {
                SELECT output.file,
                       output.input as input
                FROM output
                JOIN input ON output.input = input.file
                WHERE input.type = 'page'
                ORDER BY output.file ASC;
            } row {
                if {![db settings preset-get $row(input) showInCollections 1]} {
                    continue
                }

                set t [db settings preset-get $row(input) modifiedTimestamp]
                if {$t eq {%NULL%}} {
                    set t [db settings preset-get $row(input) timestamp]
                }

                set lastmod {}
                if {$t ne {%NULL%}} {
                    lassign $t sec format
                    set lastmod "\n  <lastmod>[clock format $sec \
                                 -format $format]</lastmod>"
                }
                set path [file join $outputDir $row(file)]
                append result [format $entry $url$path $lastmod]\n
            }
        }
        set result [format $header $result]
        return $result
    }
}
