
IF !DEF(RUINS_TWO_INC)
RUINS_TWO_INC = 1

Section "ruins_two", ROM0
ruins_two:
db height, width, HIGH(ruins_twoAutoEvents), LOW($ruins_twoAutoEvents)
db $01, $04, $04, $04, $0b, $0b, $0b, $0b, $0b, $01, $06, $0c, $06, $01, $01, $01, $01, $01, $01, $01, 
db $04, $04, $04, $04, $0b, $0b, $0b, $0b, $0b, $06, $06, $0c, $06, $01, $0b, $0b, $0b, $01, $01, $01, 
db $04, $04, $04, $04, $0b, $0b, $0b, $0b, $06, $0c, $0c, $0c, $06, $01, $0b, $04, $0b, $01, $01, $01, 
db $04, $04, $04, $04, $0b, $0b, $0b, $0b, $0b, $06, $06, $0c, $06, $01, $0b, $0b, $0b, $01, $01, $01, 
db $04, $04, $04, $04, $0b, $0b, $0b, $0b, $0b, $01, $06, $0c, $06, $01, $01, $01, $01, $01, $01, $01, 
db $04, $04, $04, $04, $01, $01, $01, $01, $01, $01, $06, $0c, $06, $01, $04, $04, $04, $01, $01, $01, 
db $04, $04, $04, $04, $01, $01, $01, $01, $01, $01, $06, $0c, $06, $04, $04, $06, $04, $04, $04, $01, 
db $04, $04, $04, $04, $01, $01, $0b, $0b, $0b, $0b, $0b, $0c, $06, $04, $06, $06, $06, $04, $04, $04, 
db $04, $04, $04, $04, $01, $01, $0b, $0b, $0b, $0b, $0b, $0c, $06, $04, $01, $0d, $01, $01, $04, $04, 
db $04, $04, $04, $04, $01, $01, $0b, $0b, $0b, $0b, $06, $0c, $06, $04, $01, $01, $01, $01, $04, $04, 
db $04, $04, $04, $04, $01, $01, $0b, $0b, $0b, $0b, $0b, $06, $06, $04, $01, $01, $01, $04, $04, $04, 
db $04, $04, $04, $04, $01, $01, $0b, $0b, $0b, $0b, $0b, $01, $01, $04, $01, $01, $04, $04, $04, $04, 
db $04, $04, $04, $04, $01, $01, $01, $01, $01, $01, $01, $01, $01, $04, $01, $04, $04, $04, $04, $04, 
db $04, $04, $04, $04, $04, $01, $01, $01, $01, $01, $01, $01, $04, $04, $04, $04, $04, $04, $04, $04, 
db $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, 
db $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, 
db $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, 
db $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, $04, 

ruins_twoAutoEvents:
  AllocateTransportEvent 8, 7, HIGH(Smallworld), LOW(Smallworld), 4, 1
  EndList
        