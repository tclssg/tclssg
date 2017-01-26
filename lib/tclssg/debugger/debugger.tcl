# Tclssg, a static website generator.
# Copyright (C) 2013, 2014, 2015, 2016, 2017 dbohdan.
# This code is released under the terms of the MIT license. See the file
# LICENSE for details.

# Data dumping facilities to help debug templates and Tclssg itself.
namespace eval ::tclssg::debugger {
    namespace export *
    namespace ensemble create

    # When active intermediate results of processing are saved to $debugDir
    # for analysis. To enable pass the command line option "--debug" to
    # when building a project.
    variable dumpIntermediates 0

    variable inputDirSetting
    variable debugDirSetting

    variable previousFilename {}

    proc enable {} {
        variable dumpIntermediates
        set dumpIntermediates 1
    }

    proc init {inputDir debugDir} {
        variable inputDirSetting
        variable debugDirSetting
        set inputDirSetting $inputDir
        set debugDirSetting $debugDir
    }

    # Save $data for file $filename in the debug directory with filename
    # suffix $suffix.
    proc save-intermediate {filename suffix data} {
        variable dumpIntermediates
        if {!$dumpIntermediates} {
            return
        }
        variable inputDirSetting
        variable debugDirSetting
        variable previousFilename

        set dest "[::tclssg::utils::replace-path-root \
                $filename $inputDirSetting $debugDirSetting].$suffix"
        if {$filename ne $previousFilename} {
            puts "    saving intermediate stage $suffix of\
                    $filename to $dest"
        } else {
            puts "        saving stage $suffix to $dest"
        }

        fileutil::writeFile $dest $data
        set previousFilename $filename
        return
    }

    # Same as save-intermediate but gets the filename from the pages
    # database.
    proc save-intermediate-id {id suffix data} {
        return [save-intermediate \
                [tclssg pages get-data $id inputFile] \
                $suffix \
                $data]
    }
} ;# debugger
