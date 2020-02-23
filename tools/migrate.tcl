#! /usr/bin/env tclsh
# This tool will help you migrate a typical project for Tclssg 1.0.x or earlier
# to Tclssg 2.x.
# Copyright (c) 2019, 2020
# dbohdan and contributors listed in AUTHORS. This code is released under
# the terms of the MIT license. See the file LICENSE for details.

package require fileutil 1
package require struct 2
package require try 1

namespace eval migrate {
    namespace export *
}

namespace eval migrate::dsl {
    namespace export *

    proc pop-settings-key path {
        upvar 1 settings settings
        upvar 1 name name
        upvar 1 value value

        if {![dict exists $settings {*}$path]} {
            # Handle with care.
            return -level 2 {}
        }

        set name [lindex $path end]
        set value [dict get $settings {*}$path]

        dict unset settings {*}$path
    }

    proc op {name arguments body} {
        set prelude {
            upvar 1 settings settings
            pop-settings-key $path

            upvar 1 acc acc
            upvar 1 indent indent
        }
        proc $name $arguments $prelude$body
    }

    proc comment-out text {
        upvar 1 indent indent 
        return "# [join [split $text \n] "\n$indent# "]"
    }

    proc add-freeform text {
        upvar 1 acc acc
        upvar 1 indent indent

        lappend acc $indent$text
    }

    proc add {name value {notEmpty 0}} {
        upvar 1 acc acc
        upvar 1 indent indent

        set emptyRe {^\s*$}
        if {$notEmpty && [regexp $emptyRe $value]} return

        lappend acc $indent[list $name $value]\n
    }

    proc negate x {
        return [expr {!$x}]
    }

    proc replace-all {replacements list} {
        set updated {}

        foreach item $list {
            lappend updated [string map $replacements $item]
        }

        return $updated
    }

    proc setting-not-empty path {
        upvar 1 settings settings

        return [expr {
            [dict exists $settings {*}$path] &&
            [dict get $settings {*}$path] ne {}
        }]
    }

    op removed path {
        add-freeform [comment-out "The setting \"$name\" has been removed\
                                   (was: \"$value\")."]\n
    }

    op id path {
        add $name $value
    }

    op transform {path newName script} {
        add $newName [uplevel 1 $script [list $value]]
    }

    op renamed {path newName} {
        add $newName $value
    }

    op pop path {
        return $value
    }

    op unknown path {
        add-freeform [comment-out "The setting \"$name\" is unknown\
                                   (was: \"$value\")."]\n
    }

    proc group {newName script} {
        upvar 1 acc acc
        upvar 1 indent indent

        set parentAcc $acc
        set acc {}

        append indent {    }

        try {
            uplevel 1 $script
        } finally {
            set indent [string range $indent 0 end-4]
            set result $acc

            set acc $parentAcc
        }

        if {$result ne {}} {
            add-freeform "[list $newName] \{\n[join $result {}]$indent\}\n"
        }
    }

    proc drain {} {
        upvar 1 acc acc
        upvar 1 indent indent
        upvar 1 settings settings

        foreach key [dict keys $settings] {
            unknown $key
        }
    }
}

proc migrate::page {settings {indent {}}} {
    namespace path dsl

    set acc {}

    group alwaysEmpty {
        id noSuchSetting[expr rand()]
    }

    group article {
        id {article top}

        id {article bottom}
    }
    pop article

    id author

    renamed blog blogPost

    id blogPost

    group body {
        id {body bottom}

        id {body top}
    }
    pop body

    group bootstrap {
        if {[dict exists $settings bootstrapTheme] ||
            [dict exists $settings contentColumns] ||
            [dict exists $settings gridClassPrefix]} {
            add version 3
        }

        id contentColumns

        id gridClassPrefix

        transform bootstrapTheme theme {apply {{indent path} {
            regsub {\$rootDirPath/} \
                   $path \
                   {} \
                   path
            regsub {external/bootstrap-3.\d.\d-dist} \
                   $path \
                   vendor/bootstrap \
                   path

            return $path
        }} $indent}
    }

    if {[setting-not-empty {%FROM_CONFIG% charset}]} {
        id {%FROM_CONFIG% charset}
    }

    group comments {
        group disqus {
            renamed {%FROM_CONFIG% comments disqusShortname} shortname
        }

        id {%FROM_CONFIG% comments engine}

        transform hideUserComments enable negate
    }

    if {[setting-not-empty {%FROM_CONFIG% copyright}]} {
        id {%FROM_CONFIG% copyright}
    }

    transform customCss customCSS {replace-all {
        $rootDirPath/ {}
    }}

    id date

    id description

    id draft

    id favicon

    group head {
        id {head bottom}

        id {head top}
    }
    pop head

    group visibleIn {
        transform hide collections negate

        transform hideFromCollections collections negate

        transform hideFromSidebar sidebarLinks negate    

        transform hideFromSidebarLinks sidebarLinks negate
    }

    group show {
        transform hideArticleTitle articleTitle negate
        
        transform hideAuthor author negate
        
        transform hideDate date negate
        
        transform hideFooter footer negate

        transform hideModifiedDate modified negate

        transform hidePostTags postTags negate
        
        transform hideTitle title negate
    }

    if {[dict exists $settings locale]} {
        id locale
    } elseif {[setting-not-empty {%FROM_CONFIG% locale}]} {
        id {%FROM_CONFIG% locale}
    }

    id modified

    renamed modifiedDate modified

    group more {
        renamed moreText markup
    }

    group navbar {
        renamed navbarBrand brand

        transform navbarItems items {replace-all {
            $indexLink /
            $blogIndexLink /blog/
            $rootDirPath {}
        }}
    }

    renamed noindex noIndex

    removed pagePrelude

    group sidebar {
        group links {
            transform hideSidebarLinks enable negate

            if {[setting-not-empty {%FROM_CONFIG% maxSidebarLinks}]} {
                renamed {%FROM_CONFIG% maxSidebarLinks} max
            }
        }

        group note {
            renamed sidebarNote content

            transform hideSidebarNote enable negate
        }

        renamed sidebarPosition position
        
        group tagCloud {
            transform hideTagCloud enable negate

            if {[setting-not-empty {%FROM_CONFIG% maxTags}]} {
                id {%FROM_CONFIG% maxTags}
            }

            if {[setting-not-empty {%FROM_CONFIG% sortTagsBy}]} {
                renamed {%FROM_CONFIG% sortTagsBy} sortBy
            }
        }
    }

    id tags

    id title

    renamed updated modified

    if {[setting-not-empty {%FROM_CONFIG% websiteTitle}]} {
        id {%FROM_CONFIG% websiteTitle}
    }

    dict unset settings %FROM_CONFIG%
    drain

    return [join $acc {}]
}

proc migrate::config settings {
    namespace path dsl

    set acc {}
    set indent {}

    set fromConfig {}
    set presets {}

    removed absoluteLinks

    removed blogIndexPage

    dict set presets blog [page [pop blogPostSettings]]

    id blogPostsPerFile

    removed debugDir

    id deployCopy

    id deployCustom

    renamed deployFtp deployFTP

    removed description

    renamed enableMacrosInPages macros

    removed indexPage

    id inputDir

    id outputDir


    dict set fromConfig charset [pop charset]
    dict set fromConfig copyright [pop copyright]
    dict set fromConfig comments [pop comments]
    dict set fromConfig locale [pop locale]
    dict set fromConfig maxSidebarLinks [pop maxSidebarLinks]
    dict set fromConfig maxTags [pop maxTags]
    dict set fromConfig sortTagsBy [pop sortTagsBy]
    dict set fromConfig websiteTitle [pop websiteTitle]

    set merged [dict merge [pop pageSettings] \
                           [dict create %FROM_CONFIG% $fromConfig]]
    dict set presets default [page $merged]


    renamed prettyUrls prettyURLs

    removed reuseTemplateInterpreter

    group rss {
        id {rss enable}
        
        id {rss feedDescription}

        removed {rss feedFilename}

        id {rss tagFeeds}

        removed {rss template}
    }
    pop rss

    group server {
        id {server host}

        id {server port}
    }
    pop server

    group sitemap {
        id {sitemap enable}
    }
    pop sitemap

    removed tagPage

    removed template

    id timezone

    id url

    drain 

    return [dict create config [join $acc {}] \
                        presets $presets]
}

proc migrate::missing-pairs {reference settings} {
    set reference [::tclssg::utils::remove-comments $reference]
    set settings [::tclssg::utils::remove-comments $settings]
    set missing {}

    dict for {key _} $reference {
        if {![dict exists $settings $key]} {
            dict set missing $key [dict get $reference $key]
        }
    }

    return $missing
}

proc migrate::macros raw {
    set sourced {}

    if {[regsub {<%\s*interp-source footnotes.tcl\s*%>} $raw {} raw]} {
        lappend sourced footnotes.tcl
    }

    if {[regsub {<%\s*interp-source img.tcl\s*%>} $raw {} raw]} {
        lappend sourced img.tcl
    }

    return [list $raw $sourced]
}


namespace eval migrate::main {}

proc migrate::main::skel-path path {
    variable location

    return [file join $location ../skeleton $path]
}

proc migrate::main::preset-with-defaults {migrated skel key} {
    set preset [dict get $migrated presets $key]
    set missing [missing-pairs [dict get $skel $key] $preset]

    if {$preset ne {}} {
        append preset \n
    }
    append preset "# The following defaults were added\
                   from the current v2.x project skeleton."

    dict for {key value} $missing {
        append preset \n[list $key $value]
    }

    return $preset
}

proc migrate::main::config {src dest} {
    puts stderr "Migrating config file [list $src/website.conf] to\
                 [list $dest/website.conf], [list $dest/presets/default]\
                 and [list $dest/presets/blog]"

    dict set skel default [fileutil::cat [skel-path presets/default]]
    dict set skel blog [fileutil::cat [skel-path presets/blog]]

    set oldConfig [fileutil::cat $src/website.conf]
    set migrated [migrate::config $oldConfig]

    fileutil::writeFile $dest/website.conf \
                        [dict get $migrated config]\n

    file mkdir $dest/presets

    set presets(default) [preset-with-defaults $migrated $skel default]
    set presets(blog) [preset-with-defaults $migrated $skel blog]

    fileutil::writeFile $dest/presets/default $presets(default)\n
    fileutil::writeFile $dest/presets/blog $presets(blog)\n
}

proc migrate::main::pages {src dest} {
    puts stderr "Migrating pages:"

    set imgFiles {}
    set prefix [file join $src pages]
    foreach path [fileutil::findByPattern $prefix -glob *.md] {
        set outputPath [file join $dest [fileutil::relative $prefix $path]]

        puts stderr "    [list $path] to [list $outputPath]"

        set page [fileutil::cat $path]
        lassign [::tclssg::utils::separate-frontmatter $page] \
                frontmatter \
                raw

        set newFrontmatter [migrate::page $frontmatter {    }]

        regsub {<%\s*interp-source footnotes.tcl\s*%>} $raw {} raw

        lassign [migrate::macros $raw] raw sourced
        if {{img.tcl} in $sourced} {
            lappend imgFiles $outputPath
        }

        set new \{\n$newFrontmatter\n\}\n$raw

        fileutil::writeFile $outputPath $new
    }

    set messages {}
    if {$imgFiles ne {}} {
        lappend messages \
                "img.tcl sourced in the files from which [list $imgFiles] were\
                 migrated. You may need to adjust the \"imagePath\" page\
                 setting in the default preset."
    }

    return $messages
}


# If this is the main script...
if {[info exists argv0] && ([file tail [info script]] eq [file tail $argv0])} {
    namespace eval migrate::main {
        namespace path [namespace parent]

        variable location [file dirname [file dirname [file normalize $argv0/___]]]
        
        lappend ::auto_path [file join $location ../lib]
        package require tclssg::utils
    }

    proc [info script] {src dest} {
        if {![file exists $src/website.conf]} {
            puts stderr "website.conf not found in [list $src].\
                         Please point this tool at the input directory."
            exit 1
        }

        if {[file isdir $dest]} {
            puts stderr "Path [list $dest] exists. Not overwriting."
            exit 1
        }

        set messages {}

        migrate::main::config $src $dest

        lappend messages {*}[migrate::main::pages $src $dest]

        puts stderr "Copying static/"
        file copy $src/static $dest

        puts stderr "Copying default templates from project skeleton"
        file copy [migrate::main::skel-path templates] $dest

        puts stderr "Copying vendored assets from project skeleton"
        file copy [migrate::main::skel-path static/vendor] $dest/static/

        puts stderr "\nMessages and warnings:"
        foreach message $messages {
            puts stderr "    $message"
        }
    }

    [info script] {*}$argv
}
