#!/usr/bin/env tclsh
# A static website generator in Tcl.
# Copyright (C) 2013, 2014 Danyil Bohdan.
# This code is released under the terms of the MIT license. See the file
# LICENSE for details.

package require fileutil
package require textutil
package require textutil::expander

# Returns the content of file fname.
proc read-file {fname {binary 0}} {
    set fpvar [open $fname r]
    if {$binary} {
        fscriptConfigure $fpvar -translation binary
    }
    set content [read $fpvar]
    close $fpvar
    return $content
}

# Save content to file fname.
proc write-file {fname content {binary 0}} {
    set fpvar [open $fname w]
    if {$binary} {
        fscriptConfigure $fpvar -translation binary
    }
    puts -nonewline $fpvar $content
    close $fpvar
}

# Transform a path relative to fromDir into the same path relative to toDir.
proc replace-path-root {path fromDir toDir} {
    # string map here is a hack to fix /./ making printed logs ugly.
    string map {/./ /} [
        file join $toDir [
            ::fileutil::relative $fromDir [file dirname $path]
        ] [
            file tail $path
        ]
    ]
}

proc dict-default-get {default dictionary args} {
    if {[dict exists $dictionary {*}$args]} {
        dict get $dictionary {*}$args
    } else {
        return $default
    }
}

proc interp-set {name value} {
    interp eval templateInterp [format {set {%s} {%s}} $name $value]
}

proc interp-inject {dictionary} {
    dict for {key value} $dictionary {
        interp-set $key $value
    }
}

# Set up template interpreter and expander.
proc interp-up {} {
    upvar 1 scriptConfig scriptConfig

    # Create safe interpreter and expander for templates. Those are global.
    interp create -safe templateInterp

    foreach command {replace-path-root dict-default-get} {
        interp alias templateInterp $command {} $command
    }

    if {![catch {::textutil::expander exp}]} {
        ::exp evalcmd {interp eval templateInterp}
        ::exp setbrackets {*}$scriptConfig(templateBrackets)
    }
}

# Tear down template interpreter.
proc interp-down {} {
    interp delete templateInterp
}

# Convert raw Markdown to HTML using an external Markdown processor.
proc markdown-to-html {markdown} {
    upvar 1 scriptConfig scriptConfig

    exec -- {*}$scriptConfig(markdownProcessor) << $markdown
}

proc get-metadata-variables {rawContent} {
    set result {}
    foreach line [split $rawContent \n] {
        # Provide alternative syntax for just setting variables.
        if {[string index $line 0] == "!"} {
            dict set result [lindex $line 1] [lindex $line 2]
        }
    }
    return $result
}

# Make HTML out of content plus template.
proc template-subst {template pageData websiteConfig} {
    upvar 1 scriptConfig scriptConfig


    set choppedContent {}

    foreach line [split [dict get $pageData rawContent] \n] {
        # Provide alternative syntax for just setting variables.
        if {[string index $line 0] != "!"} {
            set choppedContent "$choppedContent$line\n"
        }
    }

    interp-up
    interp-inject $websiteConfig
    interp-inject $pageData
    # Macroexpand content then convert it from Markdown to HTML.
    set cookedContent [markdown-to-html [::exp expand $choppedContent]]
    # Expand template with content substituted in.
    interp-set content $cookedContent
    set result [::exp expand $template]
    interp-down

    return $result
}

# Process the page inputFile (a file containing Markdown + template code).
# put its rendered content into a template under the same path relative to
# outputDir that inputFile is relative to inputDir.
proc page-to-html {pageData template websiteConfig} {
    upvar 1 scriptConfig scriptConfig

    set inputFile [dict get $pageData inputFile]
    set outputFile [dict get $pageData outputFile]

    set subdir [file dirname $outputFile]

    if {![file isdir $subdir]} {
        puts "creating directory $subdir"
        file mkdir $subdir
    }

    puts "processing page file $inputFile into $outputFile"
    set output [
        template-subst $template $pageData $websiteConfig
    ]
    write-file $outputFile $output
}

# Process input files in inputDir to produce static website in outputDir.
proc compile-website {inputDir outputDir websiteConfig} {
    upvar 1 scriptConfig scriptConfig

    set contentDir [file join $inputDir $scriptConfig(contentDirName)]

    # Build page index.
    set staticWebsite {}
    foreach file [fileutil::findByPattern $contentDir -glob *.md] {
        dict set staticWebsite $file inputFile $file
        dict set staticWebsite $file outputFile [
            file rootname [
                replace-path-root $file $contentDir $outputDir
            ]
        ].html
        dict set staticWebsite $file rawContent [read-file $file]
        dict set staticWebsite $file variables [
            get-metadata-variables [
                dict get $staticWebsite $file rawContent
            ]
        ]
        dict set staticWebsite $file pageTitle [
            dict-default-get {} $staticWebsite $file variables pageTitle
        ]
    }

    # Read template for $inputDir. Can later be made per-directory or
    # metadata-based.
    set template [
        read-file [
            file join $inputDir \
                      $scriptConfig(templateDirName) \
                      $scriptConfig(templateFileName) \
        ]
    ]

    # Process page files.
    dict for {file pageData} $staticWebsite {
        # Links to other page relative to the current.
        set outputFile [dict get $staticWebsite $file outputFile]
        set pageLinks {}
        dict for {otherFile otherMetadata} $staticWebsite {
            lappend pageLinks [
                ::fileutil::relative [
                    file dirname $outputFile
                ] [
                    dict get $otherMetadata outputFile
                ]
            ]
        }
        dict set websiteConfig pageLinks $pageLinks
        dict set websiteConfig fileName [
            ::fileutil::relative $outputDir $outputFile
        ]

        page-to-html $pageData $template $websiteConfig
    }

    # Copy static files verbatim.
    foreach file [
        fileutil::find [file join $inputDir $scriptConfig(staticDirName)]
    ] {
        if {[file isfile $file]} {
            set destFile [
                replace-path-root $file [
                    file join $inputDir $scriptConfig(staticDirName)
                ] $outputDir
            ]
            puts "copying static file $file to $destFile"
            file copy -force $file $destFile
        }
    }
}

# Load website configuration file from directory.
proc load-config {sourceDir} {
    upvar 1 scriptConfig scriptConfig
    upvar 1 websiteConfig websiteConfig

    set websiteConfig [
        read-file [
            file join $sourceDir $scriptConfig(websiteConfigFileName)
        ]
    ]
    puts "Loaded config file:\n[textutil::indent $websiteConfig {    }]\n"
}

proc main {argv0 argv} {
    # Configuration.
    set scriptConfig(markdownProcessor) \
        {perl scripts/Markdown_1.0.1/Markdown.pl}

    set scriptConfig(contentDirName) pages
    set scriptConfig(templateDirName) templates
    set scriptConfig(staticDirName) static
    set scriptConfig(templateFileName) default.thtml
    set scriptConfig(websiteConfigFileName) website.conf

    set scriptConfig(templateBrackets) {<% %>}

    set sourceDir [lindex $argv 1]
    set destDir [lindex $argv 2]

    # init command.
    switch -exact -- [lindex $argv 0] {
        init {
            foreach dir [
                list $scriptConfig(contentDirName) \
                     $scriptConfig(templateDirName) \
                     $scriptConfig(staticDirName)
            ] {
                file mkdir [file join $scriptConfig(sourceDir) $dir]
            }
            file mkdir $scriptConfig(destDir)
            # touch website.conf
            exit 0
        }
        build {
            load-config $sourceDir

            if {[file isdir $sourceDir]} {
                compile-website $sourceDir $destDir $websiteConfig
            } else {
                puts "couldn't access directory \"$sourceDir\""
                exit 1
            }
        }
        upload-copy {
            load-config $sourceDir

            set uploadDest [dict get $websiteConfig uploadDestCopy]

            foreach file [fileutil::find $destDir {file isfile}] {
                set destFile [replace-path-root $file $destDir $uploadDest]
                puts "copying $file to $destFile"
                if {![file isdir [file dirname $destFile]]} {
                    file mkdir [file dirname $destFile]
                }
                file copy -force $file $destFile
            }
            exit 0
        }
        upload-ftp {
            puts "not implemented"
            exit 1
        }
        default {
            puts [concat "usage: $argv0 (init|build|upload-copy|upload-ftp) " \
                         "sourceDir destDir"]
        }
    }
}

main $argv0 $argv