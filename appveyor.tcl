proc run args {
    puts [list > {*}$args]
    exec {*}$args >@ stdout 2>@ stderr
}

proc revision {} {
    global env

    return [expr {
        $env(APPVEYOR_REPO_TAG) ?
        $env(APPVEYOR_REPO_TAG_NAME) :
        $env(APPVEYOR_REPO_BRANCH)
    }]
}

cd ../packer
run ../tclssg/tclkit.exe build.tcl [revision] sourceRepository c:/projects/tclssg

cd ../tclssg
file rename ../packer/artifacts .
run tclkit.exe ssg.tcl version
