all: build

build:
	./ssg.tcl build data/input data/output

upload:
	./ssg.tcl upload-copy data/input data/output
