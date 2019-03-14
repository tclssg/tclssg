#! /usr/bin/env tclsh
# This tool will help you migrate a typical project for Tclssg 1.0.x or earlier
# to Tclssg 2.x.
# Copyright (c) 2019
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

    proc pop-settings-key args {
        upvar 2 settings settings
        upvar 1 value value

        try {
            set value [dict get $settings {*}$args]
        } on error {} {
            return -level 2 {}
        }

        dict unset settings {*}$args
    }

    proc op {name arguments body} {
        set prelude {
            pop-settings-key $name
            upvar 1 indent indent
            upvar 1 acc acc
        }
        proc $name $arguments $prelude$body
    }

    proc comment-out text {
        upvar 1 indent indent 
        return "# [join [split $text \n] "\n$indent# "]"
    }

    proc add text {
        upvar 1 acc acc
        upvar 1 indent indent

        lappend acc $indent$text
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

    op removed name {
        add [comment-out "The setting \"$name\" has been removed\
                          (was: \"$value\")."]
    }

    op id name {
        add [list $name $value]
    }

    op transform {name newName script} {
        add [list $newName [uplevel 1 $script [list $value]]]
    }

    op renamed {name newName} {
        add [list $newName $value]
    }

    op pop name {
        return $value
    }

    op unknown name {
        add [comment-out "The setting \"$name\" is unknown\
                          (was: \"$value\")."]
    }

    op group {name script} {
        upvar 1 settings settings

        set parentSettings $settings
        set parentAcc $acc

        set settings $value
        set acc {}

        add "[list $name] \{"
        append indent "    "

        try {
            uplevel 1 $script
        } finally {
            set indent [string range $indent 0 end-4]
            set result $acc

            set settings $parentSettings
            set acc $parentAcc
        }

        add [join $result \n]\n\}\n
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

    group article {
        id bottom

        id top
    }

    id author

    renamed blog blogPost

    id blogPost

    group body {
        id bottom

        id top
    }

    transform bootstrapTheme bootstrap {apply {{indent path} {
        regsub {\$rootDirPath/} \
               $path \
               {} \
               path
        regsub {external/bootstrap-3.\d.\d-dist} \
               $path \
               vendor/bootstrap \
               path

        set res \n
        append res "${indent}    version 3\n"
        append res "${indent}    theme $path\n"

        return $res
    }} $indent}

    id contentColumns

    transform customCss customCSS {replace-all {
        $rootDirPath/ {}
    }}

    id date

    id description

    id draft

    id favicon

    id gridClassPrefix

    group head {
        id bottom

        id top
    }

    transform hide showInCollections negate

    transform hideArticleTitle showArticleTitle negate
    
    transform hideAuthor showAuthor negate
    
    transform hideDate showDate negate
    
    transform hideFooter showFooter negate

    transform hideFromCollections showInCollections negate
    
    transform hideFromSidebarLinks showInSidebarLinks negate
    
    transform hideModifiedDate showModifiedDate negate

    transform hidePostTags showPostTags negate
    
    transform hideSidebarLinks showSidebarLinks negate
    
    transform hideSidebarNote showSidebarNote negate
    
    transform hideTagCloud showSidebarTagCloud negate
    
    transform hideTitle showTitle negate
    
    transform hideUserComments showUserComments negate

    id locale

    id modified

    renamed modifiedDate modified

    id moreText

    id navbarBrand

    transform navbarItems navbarItems {replace-all {
        $indexLink /
        $blogIndexLink /blog/
        $rootDirPath {}
    }}

    renamed noindex noIndex

    removed pagePrelude

    id sidebarNote

    id sidebarPosition

    id tags

    id title

    renamed updated modified

    drain

    return [join $acc \n]\n
}

proc migrate::config settings {
    namespace path dsl

    set indent {}
    set acc {}
    set presets {}

    removed absoluteLinks

    removed blogIndexPage

    dict set presets blog [page [pop blogPostSettings]]

    id blogPostsPerFile

    id charset

    id comments

    id copyright

    removed debugDir

    id deployCopy

    id deployCustom

    id deployFtp

    renamed enableMacrosInPages macros

    removed indexPage

    id inputDir

    id locale

    id maxSidebarLinks

    renamed maxTags maxTagCloudTags

    id outputDir

    dict set presets default [page [pop pageSettings]]

    renamed prettyUrls prettyURLs

    removed reuseTemplateInterpreter

    group rss {
        id enable
        
        id feedDescription

        removed feedFilename

        id tagFeeds

        removed template
    }

    id server

    group sitemap {
        id enable
    }

    id sortTagsBy

    removed tagPage

    removed template

    id timezone

    id url

    id websiteTitle

    drain 

    return [dict create config [join $acc \n]\n \
                        presets $presets]
}

proc migrate::missing-keys {reference settings} {
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
    set missing [missing-keys [dict get $skel $key] $preset]
    append preset "# The following defaults were added\
                   from the current v2.x project skeleton.\n"
    dict for {key value} $missing {
        append preset [list $key $value]\n
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
                        [dict get $migrated config]

    file mkdir $dest/presets

    set presets(default) [preset-with-defaults $migrated $skel default]
    set presets(blog) [preset-with-defaults $migrated $skel blog]

    fileutil::writeFile $dest/presets/default $presets(default)
    fileutil::writeFile $dest/presets/blog $presets(blog)
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
