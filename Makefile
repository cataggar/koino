all:
	zig build run

test:
	zig build test

exe:
	echo hello | zig build run
	zig build run --help
	zig build run -- --help

spec:
	zig build spec

fetch-clap:
	zig fetch --save=clap git+https://github.com/Hejsil/zig-clap#05faf3905e8548f5cc269a8836e154065e70128d

fetch-uucode:
	zig fetch --save=uucode git+https://github.com/jacobsandlund/uucode#1fb73433bba5d93366c57f23ff2e9d7939746500

example:
	zig build example
