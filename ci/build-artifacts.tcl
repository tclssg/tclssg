#! /usr/bin/env tclsh

proc run args {
    puts [list > {*}$args]
    exec {*}$args >@ stdout 2>@ stderr
}

proc revision {} {
    return [regsub -all / $::env(GITHUB_REF_NAME) -]
}

set projectDir [file dirname [file normalize [pwd]/___]]

cd ..
if {![file isdir packer]} {
    run git clone https://github.com/tclssg/packer 
}

cd packer
run ./build.tcl [revision] sourceRepository $projectDir

cd $projectDir
file rename ../packer/artifacts .

run ./ssg.tcl version
