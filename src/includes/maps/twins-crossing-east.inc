IF !DEF(TWINS_CROSSING_EAST_INC)
TWINS_CROSSING_EAST_INC = 1

/** the top left corner metatile is the "blank" tile
 * which is used to fill in anything that falls off the
 * map... tree for a forest, water for an island, black
 * or stone for a cave... */

Section "TwinsCrossingEast", ROM0
TwinsCrossingEast:
  db 9, 10, HIGH(TwinsCrossingEastEvents), LOW(TwinsCrossingEastEvents)
  db $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, 
  db $01, $01, $01, $06, $01, $01, $01, $01, $06, $01, 
  db $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, 
  db $01, $01, $01, $01, $0c, $06, $0c, $01, $0c, $06, 
  db $06, $01, $01, $06, $01, $01, $0c, $01, $01, $01, 
  db $01, $01, $01, $0c, $01, $01, $0c, $01, $01, $01, 
  db $01, $01, $01, $0d, $01, $01, $06, $06, $06, $01, 
  db $01, $06, $01, $01, $01, $01, $06, $04, $06, $01, 
  db $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, 

TwinsCrossingEastEvents:
  AllocateTransportEvent 3, 9, HIGH(Overworld), LOW(Overworld), 31, 29
  AllocateTransportEvent 6, 3, HIGH(Underworld), LOW(Underworld), 62, 58
  EndList

ENDC