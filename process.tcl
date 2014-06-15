#!/bin/sh
# A basic static website generator in shell script
# Copyright (C) 2013, 2014 Danyil Bohdan, see the file LICENSE

package require fileutil

# Helper procs
proc read-file {fname {binary 0}} {
    set fpvar [open $fname r]
    if {$binary} {
        fconfigure $fpvar -translation binary
    }
    set content [read $fpvar]
    close $fpvar
    return $content
}

proc write-file {fname content {binary 0}} {
    set fpvar [open $fname w]
    if {$binary} {
        fconfigure $fpvar -translation binary
    }
    puts -nonewline $fpvar $content
    close $fpvar
}

proc chpath {inputFile inputDir outputDir} {
    file join $outputDir\
              [::fileutil::relative $inputDir [file dirname $inputFile]]\
              [file tail $inputFile]

}

# Core
proc markdown-to-html {inputFile inputDir templateDir outputDir} {
    set markdownProcessor {perl scripts/Markdown_1.0.1/Markdown.pl}
    set header [read-file [file join $templateDir header.html]]
    set footer [read-file [file join $templateDir footer.html]]
    set outputFile [
        file rootname [chpath $inputFile $inputDir $outputDir]
    ].html
    set subdir [file dirname $outputFile]

    if {![file isdir $subdir]} {
        puts "creating directory $subdir"
        file mkdir $subdir
    }

    puts "processing $inputFile into $outputFile"
    set content [read-file "| $markdownProcessor $inputFile"]
    write-file $outputFile [concat $header $content $footer]
}

proc compile-website {inputDir outputDir} {
    # Del outputDir/*?

    foreach file [fileutil::findByPattern $inputDir -glob *.md] {
        markdown-to-html $file $inputDir/pages $inputDir/templates $outputDir
    }

    foreach file [fileutil::find $inputDir/static] {
        if {[file isfile $file]} {
            set destFile [chpath $file $inputDir/static $outputDir]
            puts "copying static file $file to $destFile"
            file copy -force $file $destFile
        }
    }
}

if {[lindex $argv 0] eq "init"} {
    puts "not implemented"
    exit 1
    #init() {
        #echo Creating directories...
        #mkdir -p $content
        #mkdir -p $pages
        #mkdir -p $static
        #mkdir -p $output
        #cd $content
        #if [ ! -d .git ]; then
            #echo output/\* > .gitignore
            #git init
        #fi
        #exit 0
    #}
}

compile-website data/input data/output
