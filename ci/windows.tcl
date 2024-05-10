proc run args {
    puts [list > {*}$args]
    exec {*}$args >@ stdout 2>@ stderr
}

proc revision {} {
    global env

    return [regsub -all / $env(GITHUB_REF_NAME) -]
}

set projectDir [file dirname [file normalize [pwd]/___]]

cd ../packer
run ../tclssg/tclkit.exe build.tcl [revision] sourceRepository $projectDir

cd ../tclssg
file rename ../packer/artifacts .
run tclkit.exe ssg.tcl version
