LOAD_ADDR = &3000-64    ; hack, code should ideally use load address of file

HIDE_DISPLAY = TRUE        ; set TRUE to hide screen until new image is available (only hides if no shadow ram available)
ENABLE_SWR = TRUE          ; set TRUE to use SWR if available (note all images must be <16Kb in size)
ENABLE_SHADOW = TRUE       ; set TRUE to use Shadow screen if available (makes transitions better)

; ZP var allocations
ORG 0
INCLUDE "lib/exomiser.h.asm"

.has_swr        SKIP 1
.has_shadow     SKIP 1

; EXE chunk
ORG &1900
GUARD LOAD_ADDR

.start
INCLUDE "lib/bbc.h.asm"
INCLUDE "lib/exomiser.asm"
INCLUDE "lib/swr.asm"
INCLUDE "lib/shadowram.asm"
INCLUDE "lib/disksys.asm"

;.load_file  EQUS "LOAD "
.file_name  EQUS "A."
.file_num   EQUS "01", 13

.file_swr   EQUS "XX     A" ; filename used by diskloader - a quirk of how the disksys works

.osfile_params			SKIP 18

.clear_vram
{
    lda #&30
    sta clearloop2+2
    ldy #&50
.clearloop
    ldx #0
    txa
.clearloop2
    sta &ff00,x
    inx
    bne clearloop2
    inc clearloop2+2
    dey
    bne clearloop    
    rts
}

.reset_nula
{
    ldx #0
.nula_loop
    lda nula_data,x
    sta &fe23
    inx
    cpx #32
    bne nula_loop
    rts
.nula_data
    EQUB &00, &00, &1f, &00, &20, &f0, &3f, &f0, &40, &0f, &5f, &0f, &60, &ff, &7f, &ff
    EQUB &80, &00, &8f, &00, &a0, &f0, &bf, &f0, &c0, &0f, &df, &0f, &e0, &ff, &ff, &ff
    
}

.main
{
    ; full reset on break
    lda #200:ldx #3:jsr &fff4

    ; initialize
    lda #0
    sta has_swr
    sta has_shadow

    ; reset palette
    lda #19:jsr &fff4
    jsr reset_nula

IF ENABLE_SWR
    ; detect sideways RAM if present
    jsr swr_init
    sta has_swr
ENDIF

IF ENABLE_SHADOW
    jsr shadow_check_master
    bne skip_master
    lda #1
    sta has_shadow
.skip_master
ENDIF

    ; clear display memory before mode switch for clean transition
    jsr clear_vram

IF ENABLE_SHADOW
    ; clear the shadow RAM too
    lda has_shadow
    beq skip_shadow_clear

    jsr shadow_select_ram   
    jsr clear_vram     

    ; setup double buffer
    lda #19:jsr &fff4
    jsr shadow_init_buffers


.skip_shadow_clear
ENDIF


    ; mode select
    lda #19:jsr &fff4
    lda #22:jsr &ffee
    lda #2:jsr &ffee

    ; turn off cursor
    lda #10:sta &fe00
    lda #32:sta &FE01

.load_loop

IF HIDE_DISPLAY
    ; display off
    lda #19:jsr &fff4

IF ENABLE_SHADOW
    lda has_shadow
    bne skip_display_off
ENDIF

	sei:lda #1:sta &fe00:lda #0:sta &fe01:cli
.skip_display_off
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


IF ENABLE_SWR
    ldx #&ff    ; load file to specified memory & also put file info to param block
    lda has_swr
    beq normal_load
    ldx #5
.normal_load
    txa
ELSE
    lda #&ff
ENDIF

    ldx #LO(osfile_params)
    ldy #HI(osfile_params)

    jsr &ffdd   ; osfile


IF ENABLE_SWR
    lda has_swr
    beq skip_swr_load

    ; copy filename
    lda file_num+0
    sta file_swr+0
    lda file_num+1
    sta file_swr+1

    ; page in SWR slot 0
    lda #0
    jsr swr_select_slot

    lda #&80
    ldx #LO(file_swr)
    ldy #HI(file_swr)
    jsr disksys_load_file

.skip_swr_load
ENDIF

    sei

    ; file loaded, so unpack it from load-address to exec-address
    ldx osfile_params+2
    ldy osfile_params+3

IF ENABLE_SWR
    ; unpack from SWR instead of main ram if SWR is present
    lda has_swr
    beq go_exo

    ; override exo source data stream
    ldx #&00
    ldy #&80

.go_exo
ENDIF

	jsr exo_init_decruncher    

    ; now unpack to the execute address of the loaded file
    ldx osfile_params+6
    ldy osfile_params+7

IF ENABLE_SWR
    ; skip the dey if SWR is detected since we're unpacking from SWR not RAM
    lda has_swr
    bne go_unpack
ENDIF

    ; exomizer doesn't decompress 'in place' so we have to leave a buffer, we just offset unpack address by one page to make the maths easier
    dey

.go_unpack
    jsr exo_unpack

IF ENABLE_SWR
    ; no need to relocate if SWR used
    lda has_swr
    bne skip_relocate
ENDIF

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

.skip_relocate

    cli

    ; wait for vsync
    lda #19:jsr &fff4

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


IF HIDE_DISPLAY
    ; display on
IF ENABLE_SHADOW
    lda has_shadow
    bne skip_display_on
ENDIF
    
	sei:lda #1:sta &fe00:lda #80:sta &fe01:cli
.skip_display_on
ENDIF

IF ENABLE_SHADOW
    lda has_shadow
    beq skip_swap
    jsr shadow_swap_buffers
    ; skip keypress with shadow mode - no need
    jmp next_image
.skip_swap
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

SAVE "!Boot", start, end, main