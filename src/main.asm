INCLUDE "includes/hardware.inc"
INCLUDE "includes/dma.inc"

MAP_TILES EQU _VRAM
SPRITE_TILES EQU $8800 ; 2nd VRAM

VRAM_WIDTH EQU 32
VRAM_HEIGHT EQU 32
VRAM_SIZE EQU VRAM_WIDTH * VRAM_HEIGHT
SCRN_WIDTH EQU 20
SCRN_HEIGHT EQU 18

; temporary, useful for testing
; in practice maps will have their own entrances/exits
PLAYER_START_X EQU 8
PLAYER_START_Y EQU 8

SECTION "OAMData", WRAM0, ALIGN[8]
Sprites: ; OAM Memory is for 40 sprites with 4 bytes per sprite
  ds 40 * 4
.end:
 
SECTION "CommonRAM", WRAM0

; all the bits we need for inputs 
_PAD: ds 2

; directions
RIGHT EQU %00010000
LEFT  EQU %00100000
UP    EQU %01000000
DOWN  EQU %10000000

A_BUTTON EQU %00000001
B_BUTTON EQU %00000010

; world position
PLAYER_WORLD_X: ds 1
PLAYER_WORLD_Y: ds 1

; enough bytes to buffer the whole _SCRN
MAP_BUFFER_WIDTH EQU SCRN_WIDTH
MAP_BUFFER_HEIGHT EQU SCRN_HEIGHT
MAP_BUFFER: ds MAP_BUFFER_WIDTH * MAP_BUFFER_HEIGHT
MAP_BUFFER_END:

; an array of indexes into an instruction table, with fixed instructions
; eg (draw top row) or (draw one tile)
; zero terminated
DRAW_INSTRUCTION_QUEUE: ds 8 ; 8 instructions per frame

; address of the next free instruction
DRAW_INSTRUCTION_QUEUE_POINTER: ds 2 ; two bytes to store an address

NO_OP EQU 0
DRAW_RIGHT_COLUMN EQU 1
DRAW_LEFT_COLUMN EQU 2
DRAW_TOP_ROW EQU 3
DRAW_BOTTOM_ROW EQU 4

; this is $80 because the tiles are in the
; second tile set which starts at $80
; obviously this will change when we get new graphics
TILE_BLANK EQU $80 + 0

; Hardware interrupts
SECTION "vblank", ROM0[$0040]
  jp DMA_ROUTINE
SECTION "hblank", ROM0[$0048]
  reti
SECTION "timer",  ROM0[$0050]
  reti
SECTION "serial", ROM0[$0058]
  reti
SECTION "joypad", ROM0[$0060]
  reti

Section "start", ROM0[$0100]
  jp init

SECTION "main", ROM0[$150]

init:
  di

  dma_Copy2HRAM	; sets up routine from dma.inc that updates sprites

  call ZeroOutWorkRAM ; it is easier to inspect this way
  call initPalettes
  call turnOffLCD

  call resetDrawInstructionQueuePointer

  ; @TODO placeholder graphics lol
  ld hl, ArkanoidTiles
  ld b, ArkanoidTiles.end - ArkanoidTiles
  ld de, MAP_TILES
  call loadTileData

  ld hl, ArkanoidGraphics
  ld b, ArkanoidGraphics.end - ArkanoidGraphics
  ld de, SPRITE_TILES
  call loadTileData

  ; @TODO the event that moved the player
  ; should determine where the player appears
  ld hl, PLAYER_WORLD_X ; world position
  ld a, PLAYER_START_X
  ld [hl], a

  ld hl, PLAYER_WORLD_Y ; world position
  ld a, PLAYER_START_Y
  ld [hl], a

  call blankVRAM
  call writeOverworldToBuffer

  call drawBuffer
  call turnOnLCD

  ei

main:
  halt

  nop

  ; if there was no input last frame, skip drawing
  ld a, [_PAD]
  and a
  jp z, .skipDrawing

  ; draw only the relevant part of the buffer
  ; call updateVRAM

  ; the stupid way, to test the buffer
  call turnOffLCD
  call drawBuffer
  call turnOnLCD

  ; but don't do anythihng else, we want to wait
  ; for a frame with no input... ie the user has to lift the key
  ; with each input. this is just temporary to prevent duplicate inputs
  call readInput
  jp main

.skipDrawing
  call readInput

  ; if there is not input this frame, skip thinking
  ld a, [_PAD]
  and a
  jp z, main

  call doPlayerMovement
  call writeOverworldToBuffer

  jp main
; -- END MAIN --

updateVRAM:
  ; iterate down the list until we hit 0
  ; switch on each instruction and call a subroutine
  ld hl, DRAW_INSTRUCTION_QUEUE

  ; loop until the instruction is NO_OP
.loop
  ld a, [hl]
  cp a, NO_OP
  jp z, .done

  push hl

  ; perform the instruction
  cp a, DRAW_LEFT_COLUMN
  call z, drawLeftColumn
  cp a, DRAW_RIGHT_COLUMN
  call z, drawRightColumn
  cp a, DRAW_TOP_ROW
  call z, drawTopRow
  cp a, DRAW_BOTTOM_ROW
  call z, drawBottomRow

  pop hl

  ld [hl], 0
  inc hl
  jr .loop
  
.done

  call resetDrawInstructionQueuePointer

  ret

resetDrawInstructionQueuePointer:
  ; point the draw instruction queue pointer to the draw instruction queue
  ld hl, DRAW_INSTRUCTION_QUEUE
  ld a, h
  ld [DRAW_INSTRUCTION_QUEUE_POINTER], a
  ld a, l
  ld [DRAW_INSTRUCTION_QUEUE_POINTER + 1], a

  ret

drawLeftColumn:
  ret

drawRightColumn:
  ret

drawTopRow:
  ld a, [rSCY]
  ld b, a
  ld a, [rSCX]
  ld c, a
  call getTopLeftScreenPointer

  ; loop over the buffer, copying to VRAM
  ld de, MAP_BUFFER

  ld b, SCRN_WIDTH
  call drawRow

  ; advance to the start of the next row
  ld c, VRAM_WIDTH - SCRN_WIDTH
  ld b, 0
  add hl, bc

  ld b, SCRN_WIDTH
  call drawRow

  ret

drawBottomRow:
  call getBottomLeftScreenPointer

  ld de, MAP_BUFFER_END
  ld a, e
  ld e, MAP_BUFFER_WIDTH
  sub a, e
  jr nc, .noCarry1
  dec d
.noCarry1
  sub a, e
  jr nc, .noCarry2
  dec d
.noCarry2
  ld e, a ; now de has the map address to draw

  ld b, SCRN_WIDTH
  call drawRow

  ; advance to the start of the next row
  ld c, VRAM_WIDTH - SCRN_WIDTH
  ld b, 0
  add hl, bc

  ld b, SCRN_WIDTH
  call drawRow

  ret

; @param de - row to draw
; @param hl - where to draw it
; @param b - count, destroyed
drawRow:
.loop
  ld a, [de]
  inc de
  ld [hl+], a
  dec b
  jr nz, .loop

  ret

; @return hl - pointer to the top left corner of the visible screen
getTopLeftScreenPointer:
  ld a, [rSCY]
  ld l, a
  ld a, 0
  ld h, a

  ; y is in pixels but we need it as an index
  ; so divide by 8
  ; then multiply by 32 to get the row as an index
  ; (but y * 32 / 8 = y * 4 so we just do two rotations)
  sla l
  adc a, 0
  
  sla a ; don't forget to multiply the high byte
  sla l
  adc a, 0

  ld h, a ; we built up the high byte in a

  ; now de points to the correct row

  ; get the x
  ld a, [rSCX]
  srl a
  srl a
  srl a ; divide by 8 to get the index

  add a, l ; add x to de
  ld l, a
  ld a, 0
  adc a, h ; add the carry
  ld h, a ; now de has de + x

  ; convert to an address in VRAM
  ld de, _SCRN0
  add hl, de

  ret

; @return hl - pointer to the top left corner of the visible screen
getBottomLeftScreenPointer:
  ld a, [rSCY]
  ld l, a

  ; y is in pixels but we need it as an index
  ; so divide by 8
  srl l
  srl l
  srl l ; divide by 8 to get the index space

  ; in the index space determine if we are
  ; wrapping around, and adjust

  ; hl's index is pointing to the first row of the screen
  ; if it is greater than 32 - 18, then
  ; the bottom of the screen will have wrapped around
  ; so we can subtract 32 to put it up above the
  ; bottom, and then subtract 18 to get an index into the bottom

  ld a, VRAM_HEIGHT - SCRN_HEIGHT
  cp a, l
  jr nc, .skip 

  ; if e > VRAM_HEIGHT - SCRN_HEIGHT
  ; subtract VRAM_HEIGH

  ld a, l
  ld l, VRAM_HEIGHT

  sub a, l ; index - 32
  jr nc, .skip ; no carry
  dec h ; borrow
  ld l, a

.skip
  ; go to the bottom of the screen
  ld a, l
  ld l, SCRN_HEIGHT
  add a, l
  ld l, a 
  dec l
  dec l ; now l is an index to second to last row on the screen

  ; now translate into address space, building up
  ; the high byte in a
  ld a, 0 ; build up the high byte in here

  sla l
  adc a, 0
  
  sla a ; don't forget to multiply the high byte
  sla l
  adc a, 0

  sla a ; don't forget to multiply the high byte
  sla l
  adc a, 0

  sla a ; don't forget to multiply the high byte
  sla l
  adc a, 0

  sla a ; don't forget to multiply the high byte
  sla l
  adc a, 0

  ld h, a ; we built up the high byte in a

  ; get the x
  ld a, [rSCX]
  srl a
  srl a
  srl a ; divide by 8 to get the index

  add a, l ; add x to hl
  ld l, a
  ld a, 0
  adc a, h ; add the carry
  ld h, a ; now hl has hl + x

  ; convert to an address in VRAM
  ld de, _SCRN0
  add hl, de

  ret

drawBuffer:
  ld hl, MAP_BUFFER
  ld de, _SCRN0
  ld b, SCRN_HEIGHT

.loop
  call drawBufferRow
  REPT 12 ; advance to the next visible row
    inc de
  ENDR
  dec b
  jr nz, .loop
.done
  ret

drawBufferRow:
  ld c, SCRN_WIDTH
.loop
  ld a, [hl]
  ld [de], a
  inc hl
  inc de
  dec c
  jr nz, .loop
.done
  ret

waitForVBlank:
.loop
  ld a, [rLY]
  cp 145
  jr nz, .loop

  ret

initPalettes:
  ; darkest to lightest
  ld a, %11100100
  ld [rBGP], a
  ld [rOBP0], a

  ret

turnOffLCD:
  ld a, [rLCDC]
  rlca
  ret nc

  call waitForVBlank

  ; in VBlank
  ld a, [rLCDC]
  res 7, a
  ld [rLCDC], a

  ret

turnOnLCD:
  ; configure and activate the display
  ld a, LCDCF_ON|LCDCF_BG8000|LCDCF_BG9800|LCDCF_BGON|LCDCF_OBJ8|LCDCF_OBJON
  ld [rLCDC], a

	ld a, IEF_VBLANK
	ld [rIE], a	; Set only Vblank interrupt flag

  ret

readInput:
  ; read the cruzeta (the d-pad)
  ld a, %00100000 ; select the d-pad
  ld [rP1], a

  ; read the d-pad several times to avoid bouncing
  ld a, [rP1] ; could also do
  ld a, [rP1] ; rept 4
  ld a, [rP1] ; ld a, [rP1]
  ld a, [rP1] ; endr

  and $0F
  swap a
  ld b, a

  ; we go for the buttons
  ld a, %00010000 ; bit 4 to 1 bit 5 to 0 (enable buttons, disable d-pad)
  ld [rP1], a

  ; read the buttons several times to avoid bouncing
  ld a, [rP1] ; could also do
  ld a, [rP1] ; rept 4
  ld a, [rP1] ; ld a, [rP1]
  ld a, [rP1] ; endr

  and $0F
  or b

  ; we now have a with 0 for down and 1 for up
  cpl ; complement so 1 means down :D
  ld [_PAD], a
.done
  ret

doPlayerMovement:
  ; if there is no input bail
  ld a, [_PAD]
  and a
  ret z

  ; now we update the player depending on the buttons
  ld a, [_PAD]
  and RIGHT
  jr nz, .moveRight ; move right

  ld a, [_PAD]
  and LEFT
  jr nz, .moveLeft ; move left

  ld a, [_PAD]
  and UP
  jr nz, .moveUp ; move up

  ld a, [_PAD]
  and DOWN
  jr nz, .moveDown ; move down

.moveRight
  ld a, [PLAYER_WORLD_X]
  inc a
  ld [PLAYER_WORLD_X], a

  ; adjust the view port
  ; ld a, [rSCX]
  ; add a, 16
  ; ld [rSCX], a

  ld b, DRAW_RIGHT_COLUMN
  call recordDrawInstruction

  ret
.moveLeft
  ld a, [PLAYER_WORLD_X]
  dec a
  ld [PLAYER_WORLD_X], a

  ; ld a, [rSCX]
  ; sub a, 16
  ; ld [rSCX], a

  ld b, DRAW_LEFT_COLUMN
  call recordDrawInstruction

  ret
.moveUp
  ld a, [PLAYER_WORLD_Y]
  dec a
  ld [PLAYER_WORLD_Y], a

  ; ld a, [rSCY]
  ; sub a, 16
  ; ld [rSCY], a

  ld b, DRAW_TOP_ROW
  call recordDrawInstruction

  ret
.moveDown
  ld a, [PLAYER_WORLD_Y]
  inc a
  ld [PLAYER_WORLD_Y], a

  ; ld a, [rSCY]
  ; add a, 16
  ; ld [rSCY], a

  ld b, DRAW_BOTTOM_ROW
  call recordDrawInstruction

  ret
; -- END readInput --

; given x and y in world space (0 - 127)
; write one meta tile to the buffer
; afterwards hl is pointing to the next buffer address
; @param bc - y, x in world space
; @parah de - address of map 
writeTileToBuffer:
  push bc

  ; multiply y by 32 to get the row index in ba
  ld a, b ; low byte in a
  ld b, 0 ; high byte in b

  sla a
  jr nc, .no_carry1
  inc b
.no_carry1

  REPT 4
    sla b
    sla a
    jr nc, .no_carry2\@
    inc b
  .no_carry2\@
  ENDR

  add a, c
  jr nc, .no_carry3
  inc b
.no_carry3

  ld c, a
  ; now bc has the index of y, x

  ; add bc to de to get address in meta tile map
  ld a, LOW(bc)
  add e
  ld e, a
  ld a, HIGH(bc)
  adc d ; add possible carry from a + e
  ld d, a

  ; de has the address of the meta tile index
  ; the meta tile index is an index into the 16 * 4 array
  ; of tiles packages with each map


  ; convert to address in tile map de
  ld a, LOW(MAP_BUFFER)
  add c
  ld c, a
  ld a, HIGH(MAP_BUFFER)
  adc b ; add possible carry from a + e
  ld b, a

  ; now de has where to write

  ; add MAP_BUFFER to convert index to address space in de
  ; get the meta tile number
  ; meta tile address into de
  ; write out the tiles
  ret

; @param b - instruction to record
recordDrawInstruction:
  ; request tiles to draw
  ld a, [DRAW_INSTRUCTION_QUEUE_POINTER]
  ld h, a
  ld a, [DRAW_INSTRUCTION_QUEUE_POINTER + 1]
  ld l, a

  ld a, b ; the instruction code
  ld [hl+], a
  
  ld a, h
  ld [DRAW_INSTRUCTION_QUEUE_POINTER], a
  ld a, l
  ld [DRAW_INSTRUCTION_QUEUE_POINTER + 1], a

  ret

; write the blank tile to the whole SCRN0
blankVRAM:
  ld hl, _SCRN0
  ld de, VRAM_SIZE
.loop
  ld a, TILE_BLANK
  ld [hl], a
  dec de
  ld a, d
  or e
  jp z, .done
  inc hl
  jp .loop
.done
  ret

; @param hl - start
; @param b - width
; @param c - the y to seek
; @return hl - the row
seekRow:
  push de

  ld a, c
  or a ; if y is zero we are done
  jr z, .done
  rlca ; if y is negative we are done
  jr c, .done

  ld a, c

  ; de gets the width
  ld d, 0
  ld e, b
.loop
  add hl, de
  dec a
  jr nz, .loop
.done
  pop de
  ret

HALF_SCREEN_WIDTH EQU SCRN_WIDTH / 2 ; 10 meta tiles
HALF_SCREEN_HEIGHT EQU SCRN_HEIGHT / 2 ; 9 meta tiles

META_TILES_TO_SCRN_LEFT EQU SCRN_WIDTH / 2 / 2
META_TILES_TO_TOP_OF_SCRN EQU SCRN_HEIGHT / 2 / 2
META_TILES_PER_SCRN_ROW EQU SCRN_WIDTH / 2
META_TILE_ROWS_PER_SCRN EQU SCRN_HEIGHT / 2

; based on the player's overworld position (0 - 128)
; fill the visible screen
; from the overworld data
writeOverworldToBuffer:
  ld a, [PLAYER_WORLD_Y]
  sub a, META_TILES_TO_TOP_OF_SCRN
  ld c, a ; world y to start drawing

  ; seek to c
  ld hl, Overworld
  ld b, OVERWORLD_WIDTH
  call seekRow
  ; now hl points to the first row

  ld de, MAP_BUFFER

; assumption, b and c are positive
; ie the player cannot approach the edges of the overworld
  ld b, META_TILE_ROWS_PER_SCRN ; we write 9 rows of meta tiles
.loop
  call writeOverworldRowToBuffer
  dec b
  jr nz, .loop

.done
  ret

; @param b - index of the start tile
; @param c - OVERWORLD_WIDTH - index of the current tile
; @return nz - if we should draw
shouldDrawTile:
  ld a, OVERWORLD_WIDTH
  sub a, c
  ; now a has the index of the current tile to draw

  ; index < start tile => don't draw
  cp a, b
  jr c, .tooSoon

  ; index - screen_width >= start tile => don't draw
  sub a, META_TILES_PER_SCRN_ROW
  jr c, .draw ; if index < screen width, we certainly draw

  cp a, b
  jr z, .tooLate
  jr nc, .tooLate

.draw
  ; returning nz

  ret

.tooSoon
  cp a ; setting z
  ret

.tooLate
  cp a ; setting z
  ret

; @param hl - meta tile to write
; @param de - write to address
writeOverworldTileToBuffer:
  ld a, [hl] ; the meta tile

  push bc
  push hl
  push de

  ld hl, OverworldMetaTiles
  ld b, 4
  ld c, a
  call seekRow
  ; hl has the meta tile

  ld a, [hl+]
  ld [de], a
  inc de

  ld a, [hl+]
  ld [de], a
  dec de

  ; advance 1 row in the buffer
  ld a, e
  add a, MAP_BUFFER_WIDTH
  ld e, a
  ld a, 0
  adc a, d
  ld d, a

  ; @TODO should we check the carry here and maybe
  ; crash if we stepped wrongly?

  ld a, [hl+]
  ld [de], a
  inc de

  ld a, [hl+]
  ld [de], a

  pop de
  pop hl
  pop bc

  inc hl ; we wrote one meta tile
  inc de
  inc de ; we wrote two tiles

  ret

; @param hl - row to write
; @param de - MAP_BUFFER at row
writeOverworldRowToBuffer: 
  push bc
  ld a, [PLAYER_WORLD_X] ; PLAYER_POS_X
  sub a, META_TILES_TO_SCRN_LEFT
  ld b, a ; the meta tile at which to start drawing

  ; move across the whole row
  ; drawing only where we need to

  ; go until we write the whole row
  ld c, OVERWORLD_WIDTH
.loop
  ; determine if hl is inside visible bounds
  call shouldDrawTile
  jr z, .skip
.draw
  call writeOverworldTileToBuffer
  dec c
  jr nz, .loop
  jr z, .done
.skip
  inc hl ; we skipped one meta tile
  dec c
  jr nz, .loop
  jr z, .done

.done

  ; after writing one row de will be at the start of
  ; the next row of tiles... but we already wrote those
  ; so we must advance de one row
  ; to get to the started of the next row we want to write
  ld a, e
  add a, MAP_BUFFER_WIDTH
  ld e, a
  ld a, 0
  adc a, d
  ld d, a

  pop bc
  ret

; @param hl -- tileset
; @param de -- location
; @param b -- bytes
loadTileData:
  push de
  push bc

.loadData
  ld a, [hl]
  ld [de], a
  dec b
  jr z, .doneLoading
  inc hl
  inc de
  jr .loadData
.doneLoading

  pop bc
  pop de

  ret

ZeroOutWorkRAM:
  ld hl, _RAM
  ld de, $DFFF - _RAM ; number of bytes to write
.write
  ld a, $00
  ld [hli], a
  dec de
  ld a, d
  or e
  jr nz, .write
  ret

Section "overworld", ROM0
OVERWORLD_WIDTH EQU 16
OVERWORLD_HEIGHT EQU 16
OverworldMetaTiles:
  ; 16 meta tiles per map
  db 0, 0, 0, 0 ; the blank
  db 1, 1, 1, 1
  db 3, 3, 3, 3
  db 0, 0, 0, 0
  db 0, 0, 0, 0
  db 0, 0, 0, 0
  db 0, 0, 0, 0
  db 0, 0, 0, 0
  db 0, 0, 0, 0
  db 0, 0, 0, 0
  db 0, 0, 0, 0
  db 0, 0, 0, 0
  db 0, 0, 0, 0
  db 0, 0, 0, 0
  db 0, 0, 0, 0
  db 0, 0, 0, 0
Overworld:
  db 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2
  db 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1
  db 2, 1, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1
  db 2, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1
  db 2, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1
  db 2, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1
  db 2, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1
  db 2, 1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 1
  db 2, 1, 1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1
  db 2, 1, 1, 1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1
  db 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1, 1
  db 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 1
  db 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 1, 1, 1
  db 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 1, 1
  db 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 1
  db 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2
EndOverworld:

Section "GraphicsData", ROM0

ArkanoidTiles: INCBIN "assets/arkanoid-map.2bpp"
.end

ArkanoidGraphics: INCBIN "assets/arkanoid-graphics.2bpp"
.end

ArkanoidMap: INCBIN "assets/arkanoid-map.tilemap"
.end