ORG 0
INCLUDE "lib/exomiser.h.asm"

.has_swr        SKIP 1
.has_shadow     SKIP 1

ORG &1900
.start
INCLUDE "lib/bbc.h.asm"
INCLUDE "lib/exomiser.asm"
INCLUDE "lib/swr.asm"
INCLUDE "lib/shadowram.asm"
INCLUDE "lib/disksys.asm"

.load_file  EQUS "LOAD "
.file_name  EQUS "A."
.file_num   EQUS "01", 13

.file_swr   EQUS "XX     A" ; filename used by diskloader - a quirk of how the disksys works

.osfile_params			SKIP 18

LOAD_ADDR = &3000-64
HIDE_DISPLAY = FALSE
USE_SWR = FALSE

.main
{
    lda #200:ldx #3:jsr &fff4

    lda #0
    sta has_swr
    sta has_shadow

    ; detect sideways RAM if present
IF USE_SWR
    jsr swr_init
    sta has_swr
    bne no_swr

    ; page in SWR slot 0
    lda #0
    jsr swr_select_slot

    ; fetch & cache disk catalog
    jsr disksys_fetch_catalogue    
    
.no_swr
ENDIF

    ; clear display memory before mode switch for clean transition
    ldy #&50
.clearloop
    ldx #0
    txa
.clearloop2
    sta &3000,x
    inx
    bne clearloop2
    inc clearloop2+2
    dey
    bne clearloop

    ; mode select
    lda #22:jsr &ffee
    lda #2:jsr &ffee

    ; turn off cursor
    lda #10:sta &fe00
    lda #32:sta &FE01

.load_loop

IF HIDE_DISPLAY
    ; display off
    lda #19:jsr &fff4
	sei:lda #1:sta &fe00:lda #0:sta &fe01:cli
ENDIF

    ; reset the palette memory
    lda #0
    tax
.clear_palette
    sta LOAD_ADDR, x
    inx
    cpx #64
    bne clear_palette


    ; check if the next file exists
    ; we use OSFIND because unlike OSFILE it doesn't cause an exception on missing files.
	ldx #LO(file_name)
	ldy #HI(file_name)
    lda #&40    ; a=&40 = open file for read
    jsr &ffce   ; osfind
    bne file_exists

    ; reset sequence if not
    lda #'0'
    sta file_num+0
    lda #'1'
    sta file_num+1
    jmp load_loop

.file_exists

    ; it does, so close the file we opened & continue
    tay         ; y=file handle
    lda #0      ; a=0 = close file
    jsr &ffce   ; osfind

    ; fetch the file information
	ldx #LO(file_name)
	ldy #HI(file_name)

    stx osfile_params+0
    sty osfile_params+1

    ; set the file exec address to non zero, so that the file's own load address is used
    lda #255
    sta osfile_params+6

    ldx #LO(osfile_params)
    ldy #HI(osfile_params)

IF USE_SWR
    ldx #&ff    ; load file to specified memory & also put file info to param block
    lda has_swr
    beq normal_load
    ldx #5
.normal_load
    txa
ELSE
    lda #&ff
ENDIF
    jsr &ffdd   ; osfile

IF USE_SWR
    lda has_swr
    beq skip_swr_load

    ; copy filename
    lda file_num+0
    sta file_swr+0
    lda file_num+1
    sta file_swr+1

    lda #&80
    ldx #LO(file_swr)
    ldy #HI(file_swr)
    jsr disksys_load_file

.skip_swr_load
ENDIF


    if 0
    ; can load as well as get the file attributes


    ; load next file
	ldx #LO(load_file)
	ldy #HI(load_file)
	jsr &fff7	; oscli
    endif


    sei

    ; file loaded, so unpack it from load-address to exec-address
    ldx osfile_params+2
    ldy osfile_params+3

IF USE_SWR
    lda has_swr
    beq go_exo

    ; unpack from SWR instead of main ram
    ldx #0
    ldy #&80

.go_exo
ENDIF

	jsr exo_init_decruncher    

    ldx osfile_params+6
    ldy osfile_params+7

IF USE_SWR
    lda has_swr
    bne go_exo2

    ; exomizer doesn't decompress 'in place' so we have to leave a buffer, we just offset unpack address by one page to make the maths easier
    dey

.go_exo2
ELSE
    ; exomizer doesn't decompress 'in place' so we have to leave a buffer, we just offset unpack address by one page to make the maths easier
    dey
ENDIF

    jsr exo_unpack

    ; relocate the unpacked image by one page. nasty but necessary.
.relocate
    lda #&7e
    sta relocate_addr0+2
    lda #&7f
    sta relocate_addr1+2
    ldx #0
.relocate_loop
.relocate_addr0
    lda &ff00,x
.relocate_addr1
    sta &ff00,x
    inx
    bne relocate_loop
    dec relocate_addr0+2
    dec relocate_addr1+2
    lda relocate_addr1+2
    cmp #&2e
    bne relocate_loop

    ; set palette, if present
    lda LOAD_ADDR
    beq next_image

    ; palette must be written in a specific sequence
    ; 2 bytes written per palette entry
    ldx #0
.palette_loop
    lda LOAD_ADDR+32,x
    sta &fe23
    inx
    cpx #32
    bne palette_loop

    cli

IF HIDE_DISPLAY
    ; display on
    lda #19:jsr &fff4
	sei:lda #1:sta &fe00:lda #80:sta &fe01:cli
ENDIF

	; wait for keypress within 2 secs
    lda #&81:ldx #200:ldy #0:jsr &fff4 ; osbyte


.next_image

    ; advance to next file in sequence
    inc file_num+1
    lda file_num+1
    cmp #48+10
    bne continue
    lda #48
    sta file_num+1
    inc file_num+0

    ; forever more
.continue
    jmp load_loop

    rts
}



.end

SAVE "Main", start, end, main