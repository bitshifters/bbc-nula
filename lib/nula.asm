; VideoNuLA routines


;-------------------------------------------------------
; Set the NULA palette back to BBC default palette.
;-------------------------------------------------------
.nula_reset
{
IF 1
    ; reset nula state
    lda #&40
    sta &fe22
ELSE
    ; this code is probably unnecessary due to above, but included anyway
    ; sets the nula extended palette to default beeb colours.
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
ENDIF
}

;-----------------------------------------------------
; set entire palette to black
;-----------------------------------------------------
.nula_set_black_palette
{
    ldx #15
.nula_loop
    txa
    asl a:asl a:asl a:asl a
    sta &fe23
    lda #0
    sta &fe23
    dex
    bpl nula_loop
    rts
}



;-----------------------------------------------------
; Palette fader table
;-----------------------------------------------------
; Palette fader implemented using a table of interpolated levels
; This is a brightness fader.
; Organised as 16 brightness levels * 16 frames of animation (from dark [0] to bright [15])
; Get the colour level of the palette for any R/G/B component, *16, then add the animation frame offset to get the new level 
;  ALIGN 256 ; doesn't have to be page aligned, just a small optimization
PALETTE_LEVELS = 16
PALETTE_FADE_STEPS = 16
.nula_palette_fade_table
    FOR i, 0, PALETTE_LEVELS-1
        a = (i+1) / PALETTE_FADE_STEPS
        PRINT a
        FOR n, 0, PALETTE_FADE_STEPS-1
            EQUB a*n
        NEXT
    NEXT


;-----------------------------------------------------
; Nula Palette local store
;-----------------------------------------------------
; we save a copy of the palette whenever it is set, so that we're able to fade out/in easily
; initialized as a completely black palette for all 16 colours
.nula_palette_store
    FOR n, 0, 15
        EQUW n*16
    NEXT



;-----------------------------------------------------
; initialise the local copy of a NULA compatible palette (32 bytes)
;-----------------------------------------------------
; X/Y = Lo/Hi address of palette to be initialized
; Does NOT actually set the palette.
.nula_load_palette
{
    stx copy_loop+1
    sty copy_loop+2
    ldx #31
.copy_loop 
    lda &ffff,x                 ; modified
    sta nula_palette_store,x
    dex
    bpl copy_loop
    rts
}







;-----------------------------------------------------
; set the NULA palette to hardware
;-----------------------------------------------------
; X/Y = Lo/Hi address of palette to be initialized
; call this during a vsync for best results.
; also copies the palette to local cache
.nula_set_palette
{
    stx palette_loop+1
    sty palette_loop+2    
    ; palette must be written in a specific sequence
    ; 2 bytes written per palette entry
    ldx #0
.palette_loop
    lda &ffff,x                 ; modified
    sta nula_palette_store,x
    sta &fe23
    inx
    cpx #32
    bne palette_loop    
    rts
}


;------------------------------------------------------------
; interpolate the palette from current level to target level
; where A=level (0-15, where 0 is zero brightness, 15 is full brightness
;------------------------------------------------------------
.nula_palette_interpolate
{
    ; A = animation frame, 0-15
    and #&0f
    sta &80

    ldx #0
.palette_update_loop
    lda nula_palette_store+0,x
    sta &82     ; temp

    ; get colour palette index, 0-15
    and #&f0
    sta &81     ; colour palette index

    ; interpolate red
    lda &82 ;:and #&0f    
    asl a:asl a:asl a:asl a
    ora &80
    tay
    lda nula_palette_fade_table,y
    ora &81

    ; send [index][red] to NuLA
    sta &fe23       

    ; fetch green/blue
    lda nula_palette_store+1,x
    sta &82
    
    ; interpolate green
    and #&f0   
    ora &80
    tay
    lda nula_palette_fade_table,y
    asl a:asl a:asl a:asl a    
    sta &81

    ; interpolate blue
    lda &82 ;:and #&0f    
    asl a:asl a:asl a:asl a
    ora &80
    tay
    lda nula_palette_fade_table,y
    ora &81
    
    ; send [green][blue] to NuLA    
    sta &fe23

    ; next palette entry
    inx
    inx

    cpx #32
    bne palette_update_loop


    rts
}

;-----------------------------------------------------
; Animate the palette from full brightness to black
;-----------------------------------------------------
.nula_fade_out
{
    lda #15:sta &84
.fade_loop
    lda #19:jsr &fff4
    lda &84:jsr nula_palette_interpolate
    dec &84
    bpl fade_loop
    rts
}

;-----------------------------------------------------
; Animate the palette from black to full brightness - uses the local palette store
;-----------------------------------------------------
.nula_fade_in
{
    lda #0:sta &84
.fade_loop
    lda #19:jsr &fff4
    lda &84:jsr nula_palette_interpolate
    inc &84
    lda &84
    cmp #16
    bne fade_loop


    rts
}