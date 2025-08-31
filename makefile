
all: doskey.bin

lbr: doskey.lbr

clean:
	rm -f doskey.lst
	rm -f doskey.bin
	rm -f doskey.lbr

doskey.bin: doskey.asm include/bios.inc include/kernel.inc
	asm02 -L -b doskey.asm
	rm -f doskey.build

doskey.lbr: doskey.bin
	rm -f doskey.lbr
	lbradd doskey.lbr doskey.bin

