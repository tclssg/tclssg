all: build

init:
	./ssg.tcl init data/input data/output

build:
	./ssg.tcl build data/input data/output

upload:
	./ssg.tcl upload-copy data/input data/output
