# MiniDOS-doskey

This provides a loadable replacement under Mini/DOS for the Mini/BIOS routines F_INPUT and F_INPUTL which perform line-based input from the console. DOS/Key adds more editing capability compared to the BIOS-based verisons, and also saves prior input lines and allows them to be recalled for editing.

The output of DOS/Key is designed to be terminal-independent, outputting only printable characters plus the backspace (ASCII 8) control character. For input, it recognizes ANSI/VT100 escape sequences for the arrow keys, and also control characters for the same functions. The control key mappings are:

^H - Cursor left (ASCII backspace)
^J - Recall previous history line
^K - Recall next history line
^L - Cursor right

As of build 2, the following alternate (emacs-like) control keys also work:

^B - Cursor left
^P - Recall previous history line
^N - Recall next history line
^F - Cursor right

Additionally the DEL character (ASCII 127) is used for the delete function. For simplicity, input is always in insert mode, where any characters to the right of the cursor are moved rightward of new input.  As of build 2, the '-d' option may be given to cause Control-H to behave the same as DEL.

DOS/Key saves 256 characters of input history. The number of lines saved will vary based on the length of the line. A maximum line length of 255 bytes is supported. As of build 2, a line recalled from history is not re-saved unless it is modified.

DOS/Key should also work under Elf/OS although this is not tested.

DOS/Key is named after the MS-DOS DOSKEY.EXE program which performs similar command-line editing functions.
