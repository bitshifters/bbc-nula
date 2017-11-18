; VideoNuLA Gallery Program
; Plays back a slideshow of 16-colour MODE2 images that have been optimized for the 4096 colour palette VideoNuLA hardware mod
; See http://stardot.org.uk/forums/viewtopic.php?f=3&t=12150 for details
;
; https://github.com/simondotm/bbc-nula
;
; This module of code is portable and is included by the main assembly file
; It assumes that images are stored on the disk as numbered files from "A.01" to "A.NN"
; It cycles through the numbers until it cant find one and then restarts the sequence.
; This makes it easy to create various gallery disk images


LOAD_ADDR = &3000-64    ; hack, code should ideally use load address of file
PALETTE_ADDR = LOAD_ADDR+32 ; first 32 bytes are header

_RELEASE = TRUE ; TRUE overrides the defines below

IF _RELEASE

; "Release" build config
HIDE_DISPLAY = TRUE        ; set TRUE to hide screen until new image is available (only hides if no shadow ram available)
ENABLE_SWR = TRUE          ; set TRUE to use SWR if available (note all images must be <16Kb in size)
ENABLE_SHADOW = TRUE       ; set TRUE to use Shadow screen if available (makes transitions better)
ENABLE_FADE = TRUE         ; set TRUE to use fade in/out of each image

ELSE

; "Test" build config
HIDE_DISPLAY = FALSE        ; set TRUE to hide screen until new image is available (only hides if no shadow ram available)
ENABLE_SWR = FALSE          ; set TRUE to use SWR if available (note all images must be <16Kb in size)
ENABLE_SHADOW = FALSE       ; set TRUE to use Shadow screen if available (makes transitions better)
ENABLE_FADE = FALSE         ; set TRUE to use fade in/out of each image

ENDIF ; _RELEASE

OSFILE_WORKAROUND = TRUE   ; OSFIND is being awkward on SmartSPI systems

;-------------------------------------------------------------------
; ZP var allocations
;-------------------------------------------------------------------
ORG &00
GUARD &8F

INCLUDE "lib/exomiser.h.asm"

.has_swr        SKIP 1
.has_shadow     SKIP 1
.osfile_params	SKIP 18
.temp_zp        SKIP 2  

;-------------------------------------------------------------------
; EXE chunk
;-------------------------------------------------------------------
ORG &1400
GUARD LOAD_ADDR

.start
INCLUDE "lib/bbc.h.asm"
INCLUDE "lib/disksys.asm"
INCLUDE "lib/exomiser.asm"
INCLUDE "lib/swr.asm"
INCLUDE "lib/shadowram.asm"
INCLUDE "lib/nula.asm"

.file_os    EQUS "LOAD "
.file_name  EQUS "A."
.file_num   EQUS "01", 13
.file_swr   EQUS "XX     A" ; filename used by diskloader - a quirk of how the disksys works



;-------------------------------------------------------
; Clear all display memory
;-------------------------------------------------------
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




;-------------------------------------------------------
; Prepare to unpack an image from the given source address
; X,Y = Lo/Hi address of source image compressed data
;-------------------------------------------------------
.unpack_init
{
	jsr exo_init_decruncher    
    rts
}

;-------------------------------------------------------
; Unpack an image to a destination address
; X,Y = Lo/Hi address of destination address
;-------------------------------------------------------
.unpack_image
{

    ; if we are unpacking from SWR we can do that all in one go.
    ; if we are unpacking from main RAM we have to decompress and relocate due to the way that exomizer works.

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
    rts
}

;-------------------------------------------------------
; Begin sequence for a new image
;-------------------------------------------------------
.slide_begin
{
IF ENABLE_FADE

IF ENABLE_SHADOW
    lda has_shadow
    bne skip_display_off
ENDIF

    jsr nula_fade_out
.skip_display_off

ELSE

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
ENDIF

    ; reset the header/palette store
    lda #0
    tax
.clear_palette
    sta LOAD_ADDR, x
    inx
    cpx #64
    bne clear_palette

    rts
}



.slide_show
{

IF ENABLE_FADE


IF ENABLE_SHADOW
    lda has_shadow
    beq skip_swap

    ; with fade enabled we first fade out the current palette
    ; before showing the new image/palette
    jsr nula_fade_out

    jsr shadow_swap_buffers

    
.skip_swap
ENDIF    

    ; stash the new images' palette to cache
    ldx #LO(PALETTE_ADDR)
    ldy #HI(PALETTE_ADDR)
    jsr nula_load_palette

    ; fade it in
    jsr nula_fade_in

; experimental - tried to test the beeb remap but not working
;    jsr nula_reset
;    jsr set_beeb_palette

ELSE

    ; wait for vsync
    lda #19:jsr &fff4

    ; set palette, if present
    lda LOAD_ADDR
    beq no_palette

    ldx #LO(PALETTE_ADDR)
    ldy #HI(PALETTE_ADDR)
    jsr nula_set_palette

.no_palette

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
.skip_swap
ENDIF    

ENDIF


    rts
}


;-------------------------------------------------------
; Main code entry point
;-------------------------------------------------------
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
    jsr nula_reset

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

IF OSFILE_WORKAROUND
    ; load & cache the disk catalogue - dont change disk though! :)
    jsr disksys_read_catalogue    
ENDIF

    ; show the nula logo at startup, no loading required as it is encoded into the EXE
.show_logo

    ; set palette to black to hide initial logo screen
    lda #19:jsr &fff4
    jsr nula_set_black_palette

    ; show the logo
    ldx #LO(logo_image_data)
    ldy #HI(logo_image_data)
    jsr unpack_init
    jsr slide_begin
    ldx #LO(LOAD_ADDR)
    ldy #HI(LOAD_ADDR)
    jsr unpack_image
    jsr slide_show

	; wait for keypress within 2 secs
    lda #&81:ldx #200:ldy #0:jsr &fff4 ; osbyte

.load_loop

    jsr slide_begin


IF OSFILE_WORKAROUND

    ; copy filename
    lda file_num+0
    sta file_swr+0
    lda file_num+1
    sta file_swr+1

    ldx #LO(file_swr)
    ldy #HI(file_swr)
    jsr disksys_find_file
    bpl file_exists

    ; reset sequence if not
    lda #'0'
    sta file_num+0
    lda #'1'
    sta file_num+1
    jmp load_loop

.file_exists

    ; got file ID in A
    ; get the file info into X,Y
    jsr disksys_file_info

    ; X,Y point to file attribute block address
    ; first 2 bytes are the load address conveniently
    stx temp_zp+0
    sty temp_zp+1

    ; stash the load address LO/HI byte in the osfile param block so that post load unpack code below works ok.
    ldy #0
    lda (temp_zp),y
    sta osfile_params+2
    iny
    lda (temp_zp),y
    sta osfile_params+3

    ; stash the exec address LO/HI byte in the osfile param block too.
    iny
    lda (temp_zp),y
    sta osfile_params+6
    iny
    lda (temp_zp),y
    sta osfile_params+7


IF ENABLE_SWR
    lda has_swr
    beq skip_swr_load


    ; page in SWR slot 0
    lda #0
    jsr swr_select_slot

    ; load to SWR address &8000
    lda #&80
    ldx #LO(file_swr)
    ldy #HI(file_swr)
    jsr disksys_load_file

    lda #0
    sta osfile_params+2
    lda #&80
    sta osfile_params+3

    jmp load_complete
.skip_swr_load
ENDIF

    ; otherwise use standard OS *LOAD to file's load address
    ldx #LO(file_os)
    ldy #HI(file_os)
    jsr &fff7 ; oscli *LOAD


.load_complete


	; wait for keypress within 2 secs
    lda #&81:ldx #200:ldy #0:jsr &fff4 ; osbyte



;---------------------------------------------------------------
ELSE

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

ENDIF ; OSFILE_WORKAROUND


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

    jsr unpack_init
   
    ; now unpack to the execute address of the loaded file
    ldx osfile_params+6
    ldy osfile_params+7

    jsr unpack_image

    cli


    jsr slide_show


IF ENABLE_SHADOW
    ; skip keypress with shadow mode - no need
    lda has_shadow
    bne next_image
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



; hacky routine - reads the 'remapped' 16-byte palette from the header and calls VDU19,N,X,0,0,0
; works on standard beebs, but problem is that on NULA beebs, the VDU19 remapping still applies.
; not used atm
.set_beeb_palette
{
    ldx #0
.loop
    lda #19:jsr &ffee
    txa:jsr &ffee
    lda LOAD_ADDR+16,x
    jsr &ffee
    lda #0:jsr &ffee:jsr &ffee:jsr &ffee
    inx
    cpx #16
    bne loop
    rts
}

; include the nula logo. Try to keep this simple and small in size to maximize disk space.
.logo_image_data
INCBIN "gallery/output/logo/nula.png.bbc.exo"

.end

PRINT "Gallery program is &", ~(end-start), "bytes (", (end-start)/1024, "Kb), (", (end-start)/256, "sectors) in size"
SAVE "!Boot", start, end, main