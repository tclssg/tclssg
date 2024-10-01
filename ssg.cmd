@echo off
setlocal

if "%TCLSH%"=="" (
    set TCLSH=tclsh
)
%TCLSH% %~dp0/ssg.tcl %*

endlocal
