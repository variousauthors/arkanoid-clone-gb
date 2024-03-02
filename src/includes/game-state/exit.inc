IF !DEF(EXIT_GAME_STATE_INC)
EXIT_GAME_STATE_INC = 1

/** the game state used when entering a door */
SECTION "ExitGameState", ROM0

exitState:
  call waitForVBlank

  ; fade out the screen slowly
  call count4In8Frames

  ld hl, FadeOutPalettes
  push af

  ; add a to hl
  add l
	ld l, a
	adc h
	sub l
	ld h, a

  ; get the next palette
  ld a, [hl]

  ld [rBGP], a
  ld [rOBP0], a
  
  pop af
  cp a, 3 ; are we done fading out?
  jp nz, .continue

  ; get the transition event
  call getCurrentEvent
  call doTransportRedraw
  call resetTime
  call toEnterState

  ret

.continue

  ret

toExitState:
  ld hl, GAME_STATE_LOW_BYTE
  ld a, LOW(exitState)
  ld [hl+], a
  ld a, HIGH(exitState)
  ld [hl], a

  ld hl, GAME_STATE_DRAW_LOW_BYTE
  ld a, LOW(exitStateDraw)
  ld [hl+], a
  ld a, HIGH(exitStateDraw)
  ld [hl], a

  ld hl, GAME_STATE_UPDATE_LOW_BYTE
  ld a, LOW(exitStateUpdate)
  ld [hl+], a
  ld a, HIGH(exitStateUpdate)
  ld [hl], a

  ld hl, GAME_STATE_IS_STEADY_LOW_BYTE
  ld a, LOW(exitStateIsSteady)
  ld [hl+], a
  ld a, HIGH(exitStateIsSteady)
  ld [hl], a

  ld hl, GAME_STATE_TRANSITION_FN_LOW_BYTE
  ld a, LOW(toExitState)
  ld [hl+], a
  ld a, HIGH(toExitState)
  ld [hl], a

  ret

exitStateDraw:
  ret

exitStateUpdate:
  ret

; @return z - yes, we are in a steady state
exitStateIsSteady:
  cp a ; no state to monitor
  ret

ENDC