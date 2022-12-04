INCLUDE "includes/hardware.inc"
INCLUDE "includes/dma.inc"
INCLUDE "includes/resolvers.inc"

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

; current map
CURRENT_MAP_HIGH_BYTE: ds 1
CURRENT_MAP_LOW_BYTE: ds 1

; world position
PLAYER_WORLD_X: ds 1
PLAYER_WORLD_Y: ds 1

; enough bytes to buffer the whole _SCRN
MAP_BUFFER_WIDTH EQU SCRN_WIDTH
MAP_BUFFER_HEIGHT EQU SCRN_HEIGHT
MAP_BUFFER:
TOP_MAP_BUFFER: ds MAP_BUFFER_WIDTH * 2
MIDDLE_MAP_BUFFER: ds MAP_BUFFER_WIDTH * (MAP_BUFFER_HEIGHT - 4)
BOTTOM_MAP_BUFFER: ds MAP_BUFFER_WIDTH * 2
MAP_BUFFER_END:

; a buffer storing either a column or row of tiles for VRAM
SCROLLING_TILE_BUFFER: ds SCRN_WIDTH * 2

; an array of indexes into an instruction table, with fixed instructions
; eg (draw top row) or (draw one tile)
; zero terminated
ACTION_QUEUE: ds 8 ; 8 instructions per frame

; address of the next free instruction
ACTION_QUEUE_POINTER: ds 2 ; two bytes to store an address

NO_OP EQU 0
PLAYER_MOVE_RIGHT EQU 1
PLAYER_MOVE_LEFT EQU 2
PLAYER_MOVE_UP EQU 3
PLAYER_MOVE_DOWN EQU 4

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

  ; player starts in the overworld
  ld hl, CURRENT_MAP_HIGH_BYTE
  ld a, HIGH(Overworld)
  ld [hl], a
  ld hl, CURRENT_MAP_LOW_BYTE
  ld a, LOW(Overworld)
  ld [hl], a

  ; initial position
  ld hl, PLAYER_WORLD_X ; world position
  ld a, PLAYER_START_X
  ld [hl], a

  ld hl, PLAYER_WORLD_Y ; world position
  ld a, PLAYER_START_Y
  ld [hl], a

  call blankVRAM
  ld hl, Overworld
  call writeMapToBuffer

  call drawBuffer
  call turnOnLCD

  ei

main:
  halt

  nop

  ; @TODO right now we are limiting input to 1 action per keydown
  ; so we check for input each frame and we only do game logic
  ; if there was no input last frame
  ld a, [_PAD]
  and a
  jp z, .doneDrawing

  ; draw only the relevant part of the buffer
  ; @TODO my first test will be to try to render
  ; just one row or column from the buffer, but still
  ; let the back-side of the main loop load the whole buffer
  ; just to see if that works.
  ; @TODO Then part II will be loading only one row/col into the buffer
  ; at one time
  ; @TODO stretch goal is to break the loading up so that it loads a little
  ; each frame while the screen is scrolling, rather than all at once before
  ; or after the scroll
  call updateVRAM
  call updateScrolling

  ; but don't do anythihng else, we want to wait
  ; for a frame with no input... ie the user has to lift the key
  ; with each input. this is just temporary to prevent duplicate inputs
  call clearInstructionQueue
  call readInput
  jr main

.doneDrawing
  call clearInstructionQueue

  ; -- INPUT PHASE JUST RECORDS ACTIONS --
  call readInput

  ; if there is not input this frame, skip thinking
  ld a, [_PAD]
  and a
  jp z, main

  ; record intents
  call doPlayerMovement

  ; -- UPDATE STATE BASED ON ACTIONS --

  call updatePlayer

  call updateBuffer
  ; call writeMapToBuffer

  jp main
; -- END MAIN --

HALF_SCREEN_WIDTH EQU SCRN_WIDTH / 2 ; 10 meta tiles
HALF_SCREEN_HEIGHT EQU SCRN_HEIGHT / 2 ; 9 meta tiles

META_TILES_TO_SCRN_LEFT EQU SCRN_WIDTH / 2 / 2
META_TILES_TO_SCRN_RIGHT EQU SCRN_WIDTH / 2 / 2 + 1
META_TILES_TO_TOP_OF_SCRN EQU SCRN_HEIGHT / 2 / 2
META_TILES_TO_BOTTOM_OF_SCRN EQU META_TILES_TO_TOP_OF_SCRN
META_TILES_PER_SCRN_ROW EQU SCRN_WIDTH / 2
META_TILE_ROWS_PER_SCRN EQU SCRN_HEIGHT / 2

; @return hl - address of current map
getCurrentMap:
  ld hl, CURRENT_MAP_HIGH_BYTE
  ld a, [hl+]

  ld l, [hl]
  ld h, a

  ret

writeLeftColumnToBuffer:
  call getCurrentMap

  ; subtract from player y, x to get top left corner
  ld a, [PLAYER_WORLD_X]
  sub a, META_TILES_TO_SCRN_LEFT
  ld de, SCROLLING_TILE_BUFFER

  ; if x is negative, draw a blank row
  cp a, $80
  jr nc, .writeBlank

  ld b, a

  ; safe to write a row
  call writeMapColumnToBuffer
  ret

.writeBlank
  call writeBlankColumnToBuffer

  ret

writeRightColumnToBuffer:
  ret

writeBottomRowToBuffer:
  call getCurrentMap

  ; subtract from player y, x to get top left corner
  ld a, [PLAYER_WORLD_Y]
  add a, META_TILES_TO_BOTTOM_OF_SCRN
  ld de, SCROLLING_TILE_BUFFER

  ld b, a
  ; if y > map height, draw a blank row

  ; load map height from map
  ld a, [hl]
  dec a ; map height - 1

  ; stop if map height - 1 < y
  cp b
  jr c, .writeBlank

  ; safe to write a row
  call writeMapRowToBuffer
  ret

.writeBlank
  call writeBlankRowToBuffer
  ret

; @param hl - map to write
writeTopRowToBuffer:
  call getCurrentMap

  ; subtract from player y, x to get top left corner
  ld a, [PLAYER_WORLD_Y]
  sub a, META_TILES_TO_TOP_OF_SCRN
  ld de, SCROLLING_TILE_BUFFER

  ; if y is negative, draw a blank row
  cp a, $80
  jr nc, .writeBlank

  ld b, a

  ; safe to write a row
  call writeMapRowToBuffer
  ret

.writeBlank
  call writeBlankRowToBuffer
  ret

; @param hl - map
writeMapToBuffer:
  ; subtract from player y, x to get top left corner
  ld a, [PLAYER_WORLD_Y]
  sub a, META_TILES_TO_TOP_OF_SCRN
  ld de, MAP_BUFFER
  ld b, a

  ; while y is negative, draw blanks
.loop1
  ld a, b
  cp a, $80 ; is y negative?
  jr c, .done1

  call writeBlankRowToBuffer
  inc b

  jr .loop1
.done1

.loop2
  ; load map height from map
  ld a, [hl]
  dec a ; map height - 1

  ; stop if map height - 1 < y
  cp b
  jr c, .done2

  ; 
  ld a, [PLAYER_WORLD_Y]
  sub a, META_TILES_TO_TOP_OF_SCRN
  add a, META_TILE_ROWS_PER_SCRN - 1

  ; stop if we're past the last row we wanted to write
  cp b
  jr c, .done2

  call writeMapRowToBuffer
  inc b

  jr .loop2
.done2

  ; at this point y will always be equal to the map height
  ; because we've written as much map as we could
  ; and a < b so b - a = rows we wrote
  ; rows we wrote - rows per screen = rows to write
  ; b - a - rows per screen = rows to write
  ; a - b + rows per screen = - rows to write
  ld a, [PLAYER_WORLD_Y]
  sub a, META_TILES_TO_TOP_OF_SCRN ; start y
  sub b ; minus map height, - rows we wrote
  add META_TILE_ROWS_PER_SCRN ; rows to write?

  ld b, a ; be has rows to write
.loop3
  ld a, b
  or a
  jr z, .done3

  call writeBlankRowToBuffer
  dec b

  jr .loop3
.done3

  ret

; bc is used by seekIndex
; @param b - y to write
; @param hl - map to read
; @param de - where to write
writeMapRowToBuffer:
  push bc
  push hl

  ; subtract from player x to get extreme left
  ld a, [PLAYER_WORLD_X]
  sub a, META_TILES_TO_SCRN_LEFT
  ld c, a ; now bc has y, x

  ; while x is negative, draw blanks
.loop1
  ld a, c
  cp a, $80 ; is y negative?
  jr c, .done1

  call writeBlankRowTileToBuffer
  inc c

  jr .loop1
.done1

.loop2
  ; load map width height from map
  inc hl
  ld a, [hl]
  dec hl
  dec a ; map width - 1

  ; stop if map width - 1 < x
  cp c
  jr c, .done2

  ; 
  ld a, [PLAYER_WORLD_X]
  sub a, META_TILES_TO_SCRN_LEFT
  add a, META_TILES_PER_SCRN_ROW - 1

  ; stop if we're past the last row we wanted to write
  cp c
  jr c, .done2

  push hl
  ; seek past map meta data
  inc hl
  inc hl

  call seekIndex
  ; now hl has the map index to start reading from

  call writeMapTileToBuffer
  pop hl

  inc c

  jr .loop2
.done2

  ld a, [PLAYER_WORLD_X]
  sub a, META_TILES_TO_SCRN_LEFT
  sub c ; minus map width, - cols we wrote
  add META_TILES_PER_SCRN_ROW

  ld c, a ; be has blank tiles to write
.loop3
  ld a, c
  or a
  jr z, .done3

  call writeBlankRowTileToBuffer
  dec c

  jr .loop3
.done3

  ; after writing two rows of tiles (1 row of meta tiles)
  ; de will be pointing to the end of the top row
  ; so we have to advance de by MAP_BUFFER_WIDTH

  ld a, e
  add a, MAP_BUFFER_WIDTH
  ld e, a
  ld a, 0
  adc a, d
  ; de advanced one row

  pop hl
  pop bc

  ret

; @param hl - the map
writeMapColumnToBuffer:
  ; subtract from player y, x to get top left corner
  ld a, [PLAYER_WORLD_Y]
  sub a, META_TILES_TO_TOP_OF_SCRN
  ld b, a

  ld a, [PLAYER_WORLD_X]
  sub a, META_TILES_TO_SCRN_LEFT
  ld c, a

  ; bc has y, x

  ld de, SCROLLING_TILE_BUFFER

  ; while y is negative, draw blanks
.loop1
  ld a, b
  cp a, $80 ; is y negative?
  jr c, .done1

  call writeBlankColumnTileToBuffer
  inc b

  jr .loop1
.done1

.loop2
  ; load map height from map
  ld a, [hl]
  dec a ; map height - 1

  ; stop if map height - 1 < y
  cp b
  jr c, .done2

  ; 
  ld a, [PLAYER_WORLD_Y]
  sub a, META_TILES_TO_TOP_OF_SCRN
  add a, META_TILE_ROWS_PER_SCRN - 1

  ; stop if we're past the last row we wanted to write
  cp b
  jr c, .done2

  push hl
  inc hl
  inc hl ; advance to map data
  call seekIndex
  call writeColumnMapTileToBuffer
  inc b
  pop hl

  jr .loop2
.done2

  ; at this point y will always be equal to the map height
  ; because we've written as much map as we could
  ; and a < b so b - a = rows we wrote
  ; rows we wrote - rows per screen = rows to write
  ; b - a - rows per screen = rows to write
  ; a - b + rows per screen = - rows to write
  ld a, [PLAYER_WORLD_Y]
  sub a, META_TILES_TO_TOP_OF_SCRN ; start y
  sub b ; minus map height, - rows we wrote
  add META_TILE_ROWS_PER_SCRN ; rows to write?

  ld b, a ; be has rows to write
.loop3
  ld a, b
  or a
  jr z, .done3

  call writeBlankColumnTileToBuffer
  dec b

  jr .loop3
.done3
  ret

; @param hl - map to read
; @param de - where to write
writeBlankColumnToBuffer:
  push bc

  ld a, META_TILE_ROWS_PER_SCRN
  ld b, a
.loop
  ; the first tile in any map is the blank tile for that map
  call writeBlankColumnTileToBuffer

  dec b
  jr nz, .loop
.done

  pop bc
  
  ret

; @param hl - map to read
; @param de - where to write
writeBlankRowToBuffer:
  push bc

  ld a, META_TILES_PER_SCRN_ROW
  ld b, a
.loop
  ; the first tile in any map is the blank tile for that map
  call writeBlankRowTileToBuffer

  dec b
  jr nz, .loop
.done

  ; after writing two rows of tiles (1 row of meta tiles)
  ; de will be pointing to the end of the top row
  ; so we have to advance de by MAP_BUFFER_WIDTH

  ld a, e
  add a, MAP_BUFFER_WIDTH
  ld e, a
  ld a, 0
  adc a, d

  pop bc
  
  ret

; @param hl - meta tile to write
; @param de - write to address
writeColumnMapTileToBuffer:
  ld a, [hl] ; the meta tile

  push bc
  push hl

  ld hl, MetaTiles
  ld c, 4
  ld b, a
  call seekRow
  ; hl has the meta tile

  ld a, [hl+]
  ld [de], a
  inc de

  ld a, [hl+]
  ld [de], a
  inc de

  ld a, [hl+]
  ld [de], a
  inc de

  ld a, [hl+]
  ld [de], a
  inc de

  pop hl
  pop bc

  inc hl ; we wrote one meta tile

  ret

; @param hl - meta tile to write
; @param de - write to address
writeMapTileToBuffer:
  ld a, [hl] ; the meta tile

  push bc
  push hl
  push de

  ld hl, MetaTiles
  ld c, 4
  ld b, a
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

; @param hl - the map
; @param de - where to write to
writeBlankColumnTileToBuffer:
  push bc
  push hl

  inc hl
  inc hl ; skip the meta data
  ld a, [hl] ; the meta tile

  ld hl, MetaTiles
  ld c, 4
  ld b, a
  call seekRow
  ; hl has the meta tile

  ld a, [hl+]
  ld [de], a
  inc de

  ld a, [hl+]
  ld [de], a
  inc de

  ld a, [hl+]
  ld [de], a
  inc de

  ld a, [hl+]
  ld [de], a
  inc de

  pop hl
  pop bc

  ret

; @param hl - the map
; @param de - where to write to
writeBlankRowTileToBuffer:
  push bc
  push hl
  push de

  inc hl
  inc hl ; skip the meta data
  ld a, [hl] ; the meta tile

  ld hl, MetaTiles
  ld c, 4
  ld b, a
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

  inc de
  inc de ; we wrote two tiles

  ret

; @param bc - y, x in world space
; @param hl - address of map
; @result hl - index of meta tile in map
seekIndex:
  push bc

  dec hl ; the map width is before the map
  ld a, [hl] 
  ld c, a
  inc hl ; point to the start of the map
  call seekRow
  ; now hl points to the row

  pop bc

  ld a, c
  inc a
.loop
  dec a
  jr z, .done
  inc hl

  jr .loop
.done

  ret

; @param bc - y, x in screen space (0 - 255)
; @result hl - address in VRAM of that position
scrnPositionToVRAMAddress:
  ld hl, _SCRN0

  ; _SCRN0
  ; 1001 1000 0000 0000
  ; vvvt twyy yyyx xxxx

  ; set the high part of y
  ld a, b ; 000yyyyy
  srl a
  srl a
  srl a ; get just the high part 000000yy

  or a, h
  ld h, a

  ; 1001 10yy 0000 0000
  ; vvvt twyy yyyx xxxx

  ; set the low part of y
  ld a, b
  and $07 ; 00000111
  rrca
  rrca
  rrca
  or a, l
  ld l, a

  ; 1001 10yy yyy0 0000
  ; vvvt twyy yyyx xxxx

  ; set x
  ld a, c
  and $1F ; 00011111
  or a, l
  ld l, a

  ret

scrollUp:
  ld a, [rSCY]
  sub a, 16
  ld [rSCY], a

  ret

scrollDown:
  ld a, [rSCY]
  add a, 16
  ld [rSCY], a

  ret

scrollLeft:
  ld a, [rSCX]
  sub a, 16
  ld [rSCX], a

  ret

scrollRight:
  ld a, [rSCX]
  add a, 16
  ld [rSCX], a

  ret

; empty the queue
clearInstructionQueue:
  ld hl, ACTION_QUEUE
  ld [hl], NO_OP

  call resetDrawInstructionQueuePointer

  ret

resetDrawInstructionQueuePointer:
  ; point the draw instruction queue pointer to the draw instruction queue
  ld hl, ACTION_QUEUE
  ld a, h
  ld [ACTION_QUEUE_POINTER], a
  ld a, l
  ld [ACTION_QUEUE_POINTER + 1], a

  ret

drawLeftColumn:
  ret

drawRightColumn:
  ret

; @param hl - address in VRAM to write
drawOneRowUp:
  ; _SCRN0
  ; 1001 1000 0000 0000
  ; vvvt twyy yyyx xxxx

  ; before we move "up" check if we need to wrap
  ; if yyyyy is 0 then we need to wrap

  ld a, h
  and a, $03 ; 0000 0011

  jr nz, .noWrap

  ld a, l
  and a, $E0 ; 1110 0000

  jr nz, .noWrap

  ; so we need y to be 32 (11111)

  ; set the low part of y
  ld a, $E0 ; 1110 0000
  or a, l
  ld l, a

  ld a, $03 ; 0000 0011
  or a, h
  ld h, a

  jr .done

.noWrap
  ; otherwise we can just decrement y twice
  ; we know y > 1 so there will not
  ; be a carry, so we can zero out x
  ; then decrement twice
  ; then put x back
  ld b, l ; save l
  ld a, l
  and a, $E0 ; zero out x
  ld l, a

  dec hl

  ; now x is 1F, and y is decremented

  ld a, l
  and a, $E0 ; 1110 0000 to drop the garbage
  ld l, a
  ld a, b
  and a, $1F ; get the x
  or a, l ; restore x
  ld l, a
  
.done

  ld de, SCROLLING_TILE_BUFFER

  ld b, l

  call drawRow

  ld l, b

  ret

drawTopRow2:
  call getTopLeftScreenPosition
  call scrnPositionToVRAMAddress
  call drawOneRowUp
  call drawOneRowUp

  ret

drawTopRow:
  ; @TODO should try to split this across 2 renders
  ; could even go so far as to have two buffers

  ; the correct data is in the buffer
  ; we just copy the top row from the buffer
  ; and then scroll
  ; the trick is figuring out where in VRAM to copy to

  ; get screen y, x
  call getTopLeftScreenPosition

  call scrnPositionToVRAMAddress

  ; _SCRN0
  ; 1001 1000 0000 0000
  ; vvvt twyy yyyx xxxx

  ; before we move "up" check if we need to wrap
  ; if yyyyy is 0 then we need to wrap

  ld a, h
  and a, $03 ; 0000 0011

  jr nz, .noWrap

  ld a, l
  and a, $E0 ; 1110 0000

  jr nz, .noWrap

  ; so we need y to be 31 (11110)
  ; since we always move 2 rows at a time

  ; set the low part of y
  ld a, $C0 ; 1100 0000
  or a, l
  ld l, a

  ld a, $03 ; 0000 0011
  or a, h
  ld h, a

  jr .done

.noWrap
  ; otherwise we can just decrement y twice
  ; we know y > 1 so there will not
  ; be a carry, so we can zero out x
  ; then decrement twice
  ; then put x back
  ld b, l ; save l
  ld a, l
  and a, $E0 ; zero out x
  ld l, a

  dec hl

  ; same deal
  ld a, l
  and a, $E0 ; zero out x
  ld l, a

  dec hl

  ; same deal
  ld a, l
  and a, $E0 ; zero out x
  ld l, a

  ld a, b
  and a, $1F ; 0001 1111 to get x in a
  or a, l ; put x back in
  ld l, a
  
.done

  ld de, SCROLLING_TILE_BUFFER

  push hl

  call drawRow

  pop hl

; advance to the next row
; using basically the same technic
; max out x so we know y will increment
  ld b, l ; save l
  ld a, l
  or a, $1F ; max out x
  ld l, a

  inc hl

  ld a, b
  and a, $1F ; 0001 1111 to get x in a
  or a, l ; put x back in
  ld l, a

  call drawRow

  ret

drawBottomRow:
  ; the correct data is in the buffer
  ; we just copy the top row from the buffer
  ; and then scroll
  ; the trick is figuring out where in VRAM to copy to

  ; get screen y, x
  call getBottomLeftScreenPosition
  ; increment y by 1
  inc b 
  ; adjust for screen wrap if we wrapped
  ; if b > 31 subtract 32
  ; b was in 0 - 31 so we just need to check if it is now 32
  ; and since that is a power of two, we can just check bit 5
  bit 5, b
  jr z, .noWrap
  ld a, b
  sub VRAM_HEIGHT
  ld b, a
.noWrap

  ld de, SCROLLING_TILE_BUFFER

  call drawRow

  ; now get the next row in vram
  ; increment y by 1
  inc b 
  ; adjust for screen wrap if we wrapped
  ; if b > 31 subtract 32
  ; b was in 0 - 31 so we just need to check if it is now 32
  ; and since that is a power of two, we can just check bit 5
  bit 5, b
  jr z, .noWrap2
  ld a, b
  sub VRAM_HEIGHT
  ld b, a
.noWrap2

  call drawRow

  ret

; @param de - row to read
; @param hl - address in VRAM to write
drawRow:
  REPT SCRN_WIDTH
    ; draw tile
    ld a, [de]
    inc de
    ld [hl+], a

    ; _SCRN0
    ; 1001 1000 0000 0000
    ; vvvt twyy yyyx xxxx

    ; check if x is zero
    ; and if so, subtract 32

    ld a, l
    and a, $1F ; 00011111

    jr nz, .noSkip\@

    dec hl
    ld a, l
    ; reset x to zero
    and $E0 ; 11100000
    ld l, a
  .noSkip\@
  ENDR

  ret

; @return bc - y, x of the top left tile of VRAM
getTopLeftScreenPosition:
  ld a, [rSCY]

  ; divide by 8 to get the y
  srl a
  srl a
  srl a

  ld b, a

  ld a, [rSCX]
  ld c, a

  ; divide by 8 to get the x
  srl c
  srl c
  srl c

  ret

; @return bc - y, x of the bottom left tile of VRAM
getBottomLeftScreenPosition:
  ld a, [rSCY]

  ; divide by 8 to get the y in tile space
  srl a
  srl a
  srl a

  ; move to the bottom of the screen
  add SCRN_HEIGHT - 1

  ld b, a

  ld a, [rSCX]
  ld c, a

  ; divide by 8 to get the x
  srl c
  srl c
  srl c

  ret

drawBuffer:
  ld hl, MAP_BUFFER
  ld de, _SCRN0
  ld b, SCRN_HEIGHT

.loop
  call drawBufferRow
  REPT VRAM_WIDTH - SCRN_WIDTH ; advance to the next SCRN row
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

; @TODO for movement we want it to feel smooth
; so if the player was pressing down left
; and then they rolled their thumb onto down
; we want to be able to see "last frame we saw left
; but this frame we see left and down, so we will
; interpret this as down"
; for now though left > right > up > down
;
; while the player is walking around, we want to
; interpret their direction pad as movement
doPlayerMovement:
  ; if there is no input bail
  ld a, [_PAD]
  and a
  ret z

  ; now we dispatch actions based on the input

  ld a, [_PAD]
  and RIGHT
  ld b, PLAYER_MOVE_RIGHT
  jr nz, .done

  ld a, [_PAD]
  and LEFT
  ld b, PLAYER_MOVE_LEFT
  jr nz, .done ; move left

  ld a, [_PAD]
  and UP
  ld b, PLAYER_MOVE_UP
  jr nz, .done ; move up

  ld a, [_PAD]
  and DOWN
  ld b, PLAYER_MOVE_DOWN
  jr nz, .done ; move down

.done

  call dispatchAction

  ret

moveLeft:
  ld a, [PLAYER_WORLD_X]
  dec a
  ld [PLAYER_WORLD_X], a

  ret

moveRight:
  ld a, [PLAYER_WORLD_X]
  inc a
  ld [PLAYER_WORLD_X], a

  ret

moveUp:
  ld a, [PLAYER_WORLD_Y]
  dec a
  ld [PLAYER_WORLD_Y], a

  ret

moveDown:
  ld a, [PLAYER_WORLD_Y]
  inc a
  ld [PLAYER_WORLD_Y], a

  ret

; @param b - instruction to record
dispatchAction:
  ; request tiles to draw
  ld a, [ACTION_QUEUE_POINTER]
  ld h, a
  ld a, [ACTION_QUEUE_POINTER + 1]
  ld l, a

  ld a, b ; the instruction code
  ld [hl+], a
  
  ld a, h
  ld [ACTION_QUEUE_POINTER], a
  ld a, l
  ld [ACTION_QUEUE_POINTER + 1], a

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
; @param b - the y to seek
; @param c - width
; @return hl - the row
seekRow:
  push de

  ld a, b
  or a ; if y is zero we are done
  jr z, .done
  rlca ; if y is negative we are done
  jr c, .done

  ld a, b

  ; de gets the width
  ld d, 0
  ld e, c
.loop
  add hl, de
  dec a
  jr nz, .loop
.done
  pop de
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

Section "metatiles", ROM0
MetaTiles:
  db 0, 0, 0, 0
  db 1, 1, 1, 1
  db 2, 2, 3, 3
  db 3, 3, 3, 3
  db 4, 4, 4, 4

Section "overworld", ROM0
Overworld:
  db 16, 16
  db 4, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2
  db 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2
  db 2, 1, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 1, 2
  db 2, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 1, 2, 1, 1, 2
  db 2, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 2
  db 2, 1, 1, 1, 1, 2, 1, 1, 1, 1, 2, 1, 1, 1, 1, 2
  db 2, 1, 1, 1, 1, 1, 2, 1, 1, 2, 1, 1, 1, 1, 1, 2
  db 2, 1, 1, 1, 1, 1, 1, 2, 2, 1, 1, 1, 1, 1, 1, 2
  db 2, 1, 1, 1, 1, 1, 1, 2, 2, 1, 1, 1, 1, 1, 1, 2
  db 2, 1, 1, 1, 1, 1, 2, 1, 1, 2, 1, 1, 1, 1, 1, 2
  db 2, 1, 1, 1, 1, 2, 1, 1, 1, 1, 2, 1, 1, 1, 1, 2
  db 2, 1, 1, 1, 2, 1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 2
  db 2, 1, 1, 2, 1, 1, 1, 1, 1, 1, 1, 1, 2, 1, 1, 2
  db 2, 1, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 1, 2
  db 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2
  db 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2

Section "smallworld", ROM0
Smallworld:
  db 10, 4
  db 4, 2, 2, 2
  db 2, 2, 1, 2
  db 2, 1, 2, 2
  db 2, 1, 1, 2
  db 2, 1, 1, 2
  db 2, 1, 1, 2
  db 2, 1, 1, 2
  db 2, 2, 1, 2
  db 2, 1, 2, 2
  db 2, 2, 2, 2

Section "GraphicsData", ROM0

ArkanoidTiles: INCBIN "assets/arkanoid-map.2bpp"
.end

ArkanoidGraphics: INCBIN "assets/arkanoid-graphics.2bpp"
.end
