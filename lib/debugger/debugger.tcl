# Tclssg, a static website generator.
# Copyright (c) 2013-2018
# D. Bohdan and contributors listed in AUTHORS. This code is released under
# the terms of the MIT license. See the file LICENSE for details.

# Data dumping facilities to help debug templates and Tclssg itself.
namespace eval ::tclssg::debugger {
    namespace export *
    namespace ensemble create
    namespace path ::tclssg

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

        set dest [::tclssg::utils::replace-path-root $filename \
                                                     $inputDirSetting \
                                                     $debugDirSetting].$suffix
        if {$filename ne $previousFilename} {
            log::debug "saving intermediate stage [list $suffix] of\
                        [list $filename] to [list $dest]"
        } else {
            log::debug "saving stage [list $suffix] to [list $dest]"
        }

        fileutil::writeFile $dest $data
        set previousFilename $filename
        return
    }
} ;# debugger

package provide tclssg::debugger 0
