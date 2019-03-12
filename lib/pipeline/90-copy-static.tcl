# Tclssg, a static website generator.
# Copyright (c) 2013, 2014, 2015, 2016, 2017, 2018, 2019
# dbohdan and contributors listed in AUTHORS. This code is released under
# the terms of the MIT license. See the file LICENSE for details.

namespace eval ::tclssg::pipeline::90-copy-static {
    namespace path ::tclssg

    proc transform {} {
        set inputDir [db config get inputDir]
        set outputDir [db config get outputDir]

        ::tclssg::utils::copy-files [file join $inputDir static] \
                                    $outputDir \
                                    always

    }
}
