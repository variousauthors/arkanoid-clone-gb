IF !DEF(GAME_OVER_GAME_STATE_INC)
GAME_OVER_GAME_STATE_INC = 1

SECTION "GameOverGameState", ROM0

/** watching the game over happen */
gameOverGameState:
  call waitForVBlank

  ; hide the player
  ld a, LCDCF_ON|LCDCF_BG8000|LCDCF_BG9800|LCDCF_BGON|LCDCF_OBJ8|LCDCF_OBJOFF
  ld [rLCDC], a

  ; fade out the screen slowly
  call count4In4Seconds

  ld hl, WhiteOutPalettes
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

  ld a, 0
  ld [rIE], a
  halt ; forever

.continue

  ret

toGameOverState:
  ; set the game state to "GAME_OVER"
  ld hl, GAME_STATE_LOW_BYTE
  ld a, LOW(gameOverGameState)
  ld [hl+], a
  ld a, HIGH(gameOverGameState)
  ld [hl], a

  ld hl, GAME_STATE_DRAW_LOW_BYTE
  ld a, LOW(gameOverGameStateDraw)
  ld [hl+], a
  ld a, HIGH(gameOverGameStateDraw)
  ld [hl], a

  ld hl, GAME_STATE_UPDATE_LOW_BYTE
  ld a, LOW(gameOverGameStateUpdate)
  ld [hl+], a
  ld a, HIGH(gameOverGameStateUpdate)
  ld [hl], a

  ld hl, GAME_STATE_IS_STEADY_LOW_BYTE
  ld a, LOW(gameOverGameStateIsSteady)
  ld [hl+], a
  ld a, HIGH(gameOverGameStateIsSteady)
  ld [hl], a

  ld hl, GAME_STATE_TRANSITION_FN_LOW_BYTE
  ld a, LOW(toGameOverState)
  ld [hl+], a
  ld a, HIGH(toGameOverState)
  ld [hl], a

  ret

gameOverGameStateDraw:
  ret

gameOverGameStateUpdate:
  ret

; @return z - yes, we are in a steady state
gameOverGameStateIsSteady:
  cp a ; no state to monitor
  ret

ENDC