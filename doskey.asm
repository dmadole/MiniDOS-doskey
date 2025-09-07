
;  Copyright 2021, David S. Madole <david@madole.net>
;
;  This program is free software: you can redistribute it and/or modify
;  it under the terms of the GNU General Public License as published by
;  the Free Software Foundation, either version 3 of the License, or
;  (at your option) any later version.
;
;  This program is distributed in the hope that it will be useful,
;  but WITHOUT ANY WARRANTY; without even the implied warranty of
;  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;  GNU General Public License for more details.
;
;  You should have received a copy of the GNU General Public License
;  along with this program.  If not, see <https://www.gnu.org/licenses/>.


          ; Include kernal API entry points

            #include include/bios.inc
            #include include/kernel.inc

          ; Executable program header

            org   2000h - 6
            dw    start
            dw    end-start
            dw    start

start:      br    chkvers

          ; Build information

            db    9+80h                 ; month
            db    6                     ; day
            dw    2025                  ; year
            dw    2                     ; build

            db    'See github.com/dmadole/MiniDOS-doskey for more info',0


          ; Check minimum needed kernel version 0.4.0 in order to have
          ; heap manager available.

chkvers:    ldi   k_ver.1               ; pointer to installed kernel version
            phi   rd
            ldi   k_ver.0
            plo   rd

            lda   rd                    ; if major is non-zero then good
            lbnz  skipspc

            lda   rd                    ; if minor is 4 or more then good
            smi   4
            lbdf  skipspc

            sep   scall                 ; quit with error message
            dw    o_inmsg
            db    'ERROR: Needs kernel version 0.4.0 or higher',13,10,0
            sep   sret


          ; Parse command line arguments, we accept one, which is the '-d' 
          ; option signifying that Backspace (Control-H) should be destructive
          ; like the Delete key.

skipspc:    lda   ra                    ; skip any leading spaces
            lbz   loadmod
            sdi   ' '
            lbdf  skipspc

            sdi   ' '-'-'               ; if not a dash then error
            lbnz  dousage

            lda   ra                    ; if not a 'd' then error
            smi   'd'
            lbnz  dousage

            ldi   backkey.1             ; get pointer to bz instruction
            phi   rf
            ldi   backkey.0
            plo   rf

            ldi   delete                ; change target of branch
            inc   rf
            str   rf

skipend:    lda   ra                    ; skip any spaces at end
            lbz   loadmod
            sdi   ' '
            lbdf  skipend

dousage:    sep   scall                 ; give a hint if error
            dw    o_inmsg
            db    'USAGE: doskey [-d]',13,10,0
            sep   sret


          ; Allocate a page-aligned block from the heap for storage of
          ; the persistent code module. Make it permanent so it will
          ; not get cleaned up at program exit.

loadmod:    sep   scall
            dw    o_inmsg
            db    'DOS/Key Line Editor Build 2 for Mini/DOS',13,10,0


            ldi   1+(modend-module).1   ; length of module plus history
            phi   rc
            ldi   (modend-module).0
            plo   rc

            ldi   255                   ; make allocation page-aligned
            phi   r7
            ldi   4+64                  ; block is permanent and named
            plo   r7

            sep   scall                 ; request memory block
            dw    o_alloc
            lbnf  zeromem

            sep   scall                 ; return with error
            dw    o_inmsg
            db    'ERROR: Could not allocate memory from heap',13,10,0
            sep   sret


          ; The first page of the memory block is used to hold input history,
          ; with zero bytes separating lines and filling any used space. Zero
          ; out this block so that we start with a blank history.

zeromem:    ldi   0                     ; set each byte of first page to zero
            str   rf
            inc   rf

            glo   rf                    ; continue for all, leave rf at end
            lbnz  zeromem

          ; References to addresses in the module code need to be adjusted
          ; in the copied block since it is probably at a different address
          ; than it was assembled for. Calculate this offset and save to the
          ; top of the stack where it can be easily referenced.

            ghi   rf                    ; offset to adjust addresses with
            smi   module.1
            str   r2


          ; Copy the resident module code into the permanent heap block. As it
          ; is copied, a rudimentary relocation function is performed so that
          ; the module can use long branch instructions. When a byte is seen
          ; that matches a long-branch opcode, the next byte is inspected to
          ; see if it is within the range of the unrelocated module; if so,
          ; then the offset is added to that byte to fix the target address.

            ldi   module.1              ; get source address
            phi   rb
            glo   rf
            plo   rb

            ldi   (modend-module).1     ; reduce size to exclude history page
            phi   rc

copymod:    lda   rb                    ; copy code to destination address
            str   rf
            inc   rf

          ; Long branch opcodes are C0, C1, C3, C3, C8, C9, CA, and CB.

            ani   %11110100             ; skip if not a long branch opcode
            xri   %11000000
            lbnz  patskip

            lda   rb                    ; copy potential branch address msb
            str   rf

          ; Check if the postential branch MSG is in the range of the module.

            smi   module.1              ; if not self-referencing then keep
            lbnf  patkeep
            sdi   (modend-module).1
            lbnf  patkeep

            ldn   rf                    ; otherwise relocate with offset
            add
            str   rf

patkeep:    inc   rf                    ; account for lbr msb argument
            dec   rc

          ; Note that if the module ends in a byte that looks like a long
          ; branch the following will fail, but this can never actually
          ; happen since the end of the module is the module name block.

patskip:    dec   rc                    ; continue for entire block
            glo   rc
            lbnz  copymod
            ghi   rc
            lbnz  copymod


          ; Update kernel hooks to point to the copied module code, based on
          ; a table of kernel hooks and the add replacement routine. The
          ; replacement routine addredd needs to be adjusted for relocated.

            ldi   hooktab.1             ; Get point to table of patch points
            phi   rd
            ldi   hooktab.0
            plo   rd

            lda   rd                    ; prime the pump with first byte

sethook:    phi   rf                    ; get pointer to vector to hook
            lda   rd
            plo   rf

            inc   rf                    ; skip the lbr opcode at vector

            lda   rd                    ; add offset to get copy address
            add
            str   rf
            inc   rf
            lda   rd
            str   rf

            lda   rd                    ; get next byte, zero marks the end
            lbnz  sethook


          ; All done, exit to operating system

            sep   sret


          ; Table giving addresses of jump vectors we need to update, along
          ; with offset from the start of the module to repoint those to.

hooktab:    dw    o_input, input
            dw    o_inputl, inputl
            db    0


          ; Start the actual module code on a new page so that it forms
          ; a block of page-relocatable code that will be copied to himem.

            org   (($-1)|255)+1


          ; ------------------------------------------------------------------
module:   ; This is the module that is loaded into memory to replace the
          ; F_INPUT and _FINPUTL BIOS routines. For either routine, a buffer
          ; is pointed to by RF on entry, and the length of the input is
          ; returned in RC. The general internal register usage is:
          ;
          ;   R9   - General working register and pointer
          ;   RA.0 - Characters to the left of the cursor
          ;   RB.0 - Characters to the right of the cursor
          ;   RC.0 - Number of bytes free in the buffer
          ;   RD   - Pointer to the current place in history
          ;   RF   - Pointer into buffer at cursor position
          ;
          ; The MSB of some are used for purposes unrelated to the LSB:
          ;
          ;   RA.1 - Holds MSB of first page for exit use
          ;   RB.1 - If non-zero then line should be saved
          ;   RC.1 - Used in endline to hold exit status

          ; If called at INPUTL, then the maximum length is in register RC.
          ; But we impose a limit of 255 bytes, so if what is passed is more
          ; then that, reduce it to 255 bytes.

inputl:     ghi   rc                    ; skip if length is 255 or less
            bz    noadjus

          ; If called at INPUT, the limit is fixed at 255 bytes maximum.
          ; We only use RC.0 internally but will set RC.1 to zero at exit.

input:      ldi   255                   ; else set maximum length to 255
            plo   rc

noadjus:    glo   r9
            stxd
            ghi   r9
            stxd

            glo   ra
            stxd
            ghi   ra
            stxd

            glo   rb
            stxd
            ghi   rb
            stxd

            glo   rd
            stxd
            ghi   rd
            stxd

          ; Set the terminal mode to no echo, but save the original mode so
          ; it can be restored (usually it will be set to echo).

            ghi   re                    ; get current mode and save it
            stxd

            ani   %11111110             ; clear bit 0 which is echo mode
            phi   re

          ; This variable is the pointer to the end of the history buffer,
          ; pointing to the zero at the end of the last line. Only the LSB
          ; needs to be kept since the buffer in one integral memory page.
          ; It is stored as an LDI argument that is updated in place.

pointer:    equ   $+1                   ; points to the ldi argument below

            ldi   0                     ; get pointer to last buffer line
            plo   rd

            ghi   r3                    ; save for later variable reference
            phi   ra

            smi   1                     ; set msb of last line pointer
            phi   rd

          ; Start with an empty line, no characters to the left or right.

            ldi   0                     ; start with the input line empty
            plo   ra
            plo   rb


          ; ------------------------------------------------------------------
          ; This is the main loop that gets keystrokes from the termianl and
          ; processes them.

inploop:    sep   scall                 ; get next keystroke and save it
            dw    o_readkey
            plo   re

            smi   2                     ; if control-b (ascii 2)
            bz    movleft

            smi   3-2                   ; if control-c (ascii 3)
            lbz   endline

            smi   6-3                   ; if control-f (ascii 6)
            bz    mvright
   
            smi   8-6                   ; if control-h (ascii 8, backspace)
backkey:    bz    movleft

            smi   10-8                  ; if control-j (ascii 10, linefeed)
            lbz   forward
 
            smi   11-10                 ; if control-k (ascii 11)
            lbz   backwrd

            smi   12-11                 ; if control-l (ascii 12)
            bz    mvright
   
            smi   13-12                 ; if control-m (ascii 13, return)
            lbz   endline

            smi   14-13                 ; if control-n (ascii 14)
            lbz   forward
 
            smi   16-14                 ; if control-p (ascii 16)
            lbz   backwrd
 
            smi   27-16                 ; if control-[ (ascii 27, escape)
            bz    escapes

            smi   32-27                 ; if anything else < 32 then ignore
            bnf   inploop

            smi   127-32                ; if delete key (ascii 127)
            bz    delete

            bdf   inploop               ; if anything > 127 then ignore


          ; ------------------------------------------------------------------
          ; If nothing else, then this is a printable character, insert it
          ; into the line buffer at the cursor position.

            glo   rc                    ; ignore if buffer is already full
            bz    inploop

            phi   rb                    ; mark that line has been changed

            glo   rb                    ; run through characters to right
            plo   r9

            inc   r9                    ; plus the new one being inserted

          ; Shift each character to the right one space through a rotating
          ; buffer, and output as we do it to update the terminal.

insloop:    ldn   rf                    ; get character and save it
            phi   r9

            glo   re                    ; store prior character over it
            str   rf
            inc   rf

            sep   scall                 ; output it to the terminal
            dw    o_type

            ghi   r9                    ; save prior value for next loop
            plo   re

            dec   r9                    ; repeat until all processed
            glo   r9
            bnz   insloop

          ; In the end, the number of characters to the right of the cursor
          ; remains the same, but one to the left of it has been added, and
          ; the line is overall one character longer.

            inc   ra                    ; account for new character on left
            dec   rc

          ; Output backspaces to move the cursor back to the right position,
          ; and adjust RF back at the time same.

movback:    glo   rb                    ; loop count through all to the right
            plo   r9

nxtback:    bz    inploop               ; get next character if all processed

            ldi   8                     ; output a backspace to move cursor
            sep   scall
            dw    o_type

            dec   rf                    ; adjust the buffer pointer left

            dec   r9                    ; repeat until all processed
            glo   r9
            br    nxtback


          ; ------------------------------------------------------------------
          ; Delete a character to the left of the cursor, moving everything
          ; to the right one space to the left.

delete:     glo   ra                    ; ignore if at the start of line
            bz    inploop

            phi   rb                    ; mark that line has been changed

          ; All the characters from to cursor to the end of the line need to
          ; be moved one space to the left, both in memory and on the screen.

            ldi   8                     ; move cursor one space to the left
            sep   scall
            dw    o_type

            glo   rb                    ; get a copy of length to the right
            plo   r9

            bz    delskip               ; enter output loop at the test

delloop:    ldn   rf                    ; move each character down in memory
            dec   rf
            str   rf
            inc   rf
            inc   rf

            sep   scall                 ; output to terminal to move there
            dw    o_type

            dec   r9                    ; decrement the count of characters
            glo   r9
            bnz   delloop

          ; Erase the last character left dangling at the end of the line,
          ; then move the cursor back on the terminal to where it needs to be
          ; by sending backspaces.

delskip:    sep   scall                 ; erase last character on the line
            dw    o_inmsg
            db    32,8,0

          ; In the end, the number of characters to the right of the cursor
          ; remains the same, but one to the left of it has been removed,
          ; and the line is overall one character shorter.

            dec   ra                    ; remove character to left of cursor
            inc   rc
            dec   rf

            br    movback               ; adjust pointer and position cursor


          ; ------------------------------------------------------------------
escapes:    sep   scall                 ; get second character of escape
            dw    o_readkey

            smi   'O'                   ; if in application mode proceed
            bz    escapes 

            smi   '['-'O'               ; else if not [ then ignore rest
            bz    escapes

getnext:    sep   scall                 ; get third character of escape
            dw    o_readkey

            smi   'A'                   ; if A then previous line
            lbz   backwrd

            bnf   getnext               ; absorb anything less than A

            smi   'B'-'A'               ; if B then next line
            lbz   forward

            smi   'C'-'B'               ; if C then cursor left
            bz    mvright

            smi   'D'-'C'               ; if D then cursor right
            bz    movleft

            br    inploop               ; ignore anything else


          ; ------------------------------------------------------------------
          ; Move the cursor one space to the left.

movleft:    glo   ra                    ; ignore if at the start of the line
            bz     inploop

dobacks:    dec   ra                    ; move cursor to the left in buffer
            inc   rb
            dec   rf

            ldi   8                     ; echo a backspace to the terminal
            sep   scall                 ; output character to move cursor
            dw    o_type
 
            br    inploop


          ; ------------------------------------------------------------------
          ; Move the cursor one space to the right.

mvright:    glo   rb                    ; ignore if at the end of the line
            bz    inploop

doforwd:    inc   ra                    ; move to the right in buffer
            dec   rb
            lda   rf

outchar:    sep   scall                 ; output character to move cursor
            dw    o_type

            br     inploop



            org   (($-1)|255)+1

          ; ------------------------------------------------------------------
          ; Search forward for the next line in the history to restore. If
          ; there is no next line, ignore the operation.

forward:    glo   rd                    ; point r9 to next byte after rd
            plo   r9
            inc   r9
            ghi   rd
            phi   r9

            ldn   r9                    ; if there is no next line, ignore
            lbz   inploop

nextlin:    ghi   r9                    ; move to end of the next line
            inc   r9
            phi   r9
            ldn   r9
            bnz   nextlin

            br    restore               ; restore line from history

          ; ------------------------------------------------------------------
          ; Search backwards for the prior line in the history to restore.
          ; If there is no prior line, ignore the operation.

backwrd:    glo   rd                    ; point r9 to prior byte before rd
            plo   r9
            dec   r9
            ghi   rd
            phi   r9

            ldn   r9                    ; if there is no prior line, ignore
            lbz   inploop

prevlin:    ghi   r9                    ; move to end of the prior line
            dec   r9
            phi   r9
            ldn   r9
            bnz   prevlin

          ; R9 now points to either the next or previous line, save it as
          ; the next reference point, and copy the old line to the new.

restore:    glo   r9                    ; update line pointer to prior line
            plo   rd

            br    tofirst               ; copy prior line into line buffer


          ; ------------------------------------------------------------------
          ; Move the terminal cursor to the beginning of the line by emitting
          ; a backspace for each character to the left of the cursor. As we
          ; go, adjust the character counts and line buffer pointer.

fstloop:    ldi   8                     ; move to start of display line
            sep   scall
            dw    o_type

            dec   ra                    ; move character to other side
            inc   rb
            inc   rc
            dec   rf

tofirst:    glo   ra                    ; repeat until none on the left
            bnz   fstloop

          ; Output the line line from history, overwriting the current line
          ; on the terminal. Stop when all is copied, or if the line buffer
          ; runs out of space.

            br    copyold               ; jump into loop test to start

oldloop:    str   rf                    ; history byte into line and output
            sep   scall
            dw    o_type

            inc   ra                    ; move cursor to right one space
            inc   rf
            dec   rc

            glo   rb                    ; don't decrement right count past 0
            bz    copyold
            dec   rb

copyold:    glo   rc                    ; stop copying when line is full
            bz    endcopy

            ghi   r9                    ; advance history source pointer
            inc   r9
            phi   r9

            ldn   r9                    ; get history byte to copy
            bnz   oldloop

            phi   rb                    ; mark line as unchanged

          ; If the history line is the same length or longer than the current
          ; line we copied over, then we are done

endcopy:    glo   rb                    ; done if nothing left to the right
            bz    alldone

          ; Otherwise, blank the rest of the prior current line by writing
          ; spaces over it.

            plo   r9                    ; copy of count to overwrite

blankit:    ldi   32                    ; output a space over prior contents
            sep   scall
            dw    o_type

            dec   r9                    ; repeat until all overwritten
            glo   r9
            bnz   blankit

          ; Now backspace over the blanked part to move the cursor back to
          ; the end of the recalled line. At the same time, run RB down to
          ; zero since there will be nothing to the right of the cursor.

poslast:    ldi   8                    ; output a backspace to move cursor
            sep   scall
            dw    o_type

            dec   rb                   ; repeat until back to end of line
            glo   rb
            bnz   poslast

alldone:    lbr   inploop              ; done, go back and get keystroke


          ; ------------------------------------------------------------------
          ; At end of input, position pointer to the end of the line, zero-
          ; terminate, and return DF if exiting due to Control-C, or DF clear
          ; if exiting due to Carriage Return. The exit status is extracted
          ; from bit 1 of the ASCII code and stored in bit 0 of RC.1, and
          ; the rest of RC.1 is zeroed to failitate setting to zero at exit.

endline:    glo   re                    ; set exit status accordingly
            shr
            ani   %1
            phi   rc

          ; If the input line is empty then do not save it, and there is no
          ; need to do most of the post-processing, just skip to the return.

            glo   ra                    ; if line not empty then save it
            bnz   endtest
            glo   rb
            bnz   endtest

            str   rf                    ; else zero terminate and return
            br    skipsav

          ; Move the cursor to the end of the line, adjusting RA to the length
          ; of the line and setting RF just past the last character, then
          ; zero-terminating the input line.

endloop:    lda   rf                    ; output each character to terminal
            sep   scall
            dw    o_type

            inc   ra                    ; increment character count on left

            dec   rb                    ; count down characters on the right
endtest:    glo   rb
            bnz   endloop

            str   rf                    ; tero terminate the input line

          ; If exiting due to control-c then do not save the line to history.

            ghi   rc                    ; skip saving if exit status not 0
            shr
            bdf   skipsav

            ghi   rb                    ; if line not changed do not save
            bz    skipsav

          ; Adjust RF to point to the beginning of the line for copying it.
          ; All the rest is done without any updates to the terminal.

            glo   ra                    ; get characters to left of cursor
            str   r2

            glo   rf                    ; subtract it from the buffer pointer
            sm
            plo   rf
            ghi   rf
            smbi  0
            phi   rf

          ; Get pointer into the saved lines buffer.

            ldi   pointer               ; get pointer to history pointer
            plo   ra
            ldn   ra
            plo   rd

          ; Copy the new line into the buffer after the last time. We start
          ; pointing to the zero after the last line, so we start with the
          ; increment of the buffer pointer.

cpyloop:    ghi   rd                    ; increment pointer with lsb wrap
            inc   rd
            phi   rd

            lda   rf                    ; copy a byte until zero reached
            str   rd
            bnz   cpyloop

            glo   rd                    ; update history pointer
            str   ra

          ; Fill any remaining portion of the oldest line that we overwrote
          ; with zeros so that we won't go backward past it in the future.
          ; Since we start pointing to the terminator, do the increment first.

            br    fillinc               ; start loop at increment

filloop:    ldi   0                     ; overwrite old line with zero
            str   rd

fillinc:    ghi   rd                    ; increment pointer with lsb wrap
            inc   rd
            phi   rd

            ldn   rd                    ; if not at zero then keep filing
            bnz   filloop

          ; Set RC to the length of the input, set the exist status to DF,
          ; restore any used registers, and return.

skipsav:    glo   ra                    ; update rc with length of line
            plo   rc

            ghi   rc                    ; move status to df and zero rc.1
            shr
            phi   rc

            irx                         ; restore terminal echo flag
            ldxa
            phi   re

            ldxa                        ; restore other used registers
            phi   rd
            ldxa
            plo   rd

            ldxa
            phi   rb
            ldxa
            plo   rb

            ldxa
            phi   ra
            ldxa
            plo   ra

            ldxa
            phi   r9
            ldx
            plo   r9

            sep   sret                  ; return to caller


          ; ------------------------------------------------------------------
          ; The minfo command will look at the top of a heap block for a
          ; name if the 64 flag is set on the block, so here is a name. It
          ; needs some zero padding to copy into the block as well in case
          ; o_alloc returns a larger block than requested (hy up to 3 bytes)
          ; which can happen. Minfo knows to ignore this extra padding.

            db    0,'DOS/Key',0         ; label for minfo heap block
modend:     db    0,0,0                 ; padding if alloc returns excess


end:        end   start
