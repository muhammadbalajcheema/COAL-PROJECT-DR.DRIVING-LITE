[org 0x0100]

    jmp start

; =========================================================================
; STRINGS & DATA
; =========================================================================
title_str:      db 'DR DRIVING LITE', 0
score_lbl:      db 'SCORE : 0000', 0
coins_lbl:      db 'COINS : 00', 0
fuel_lbl:       db 'FUEL  :', 0
fuel_bar:       db '[||||||||  ]', 0
gear_lbl:       db 'GEAR  : D', 0
speed_lbl:      db 'SPEED : 60 KM/H', 0
ctrl_title:     db '--- CONTROLS ---', 0
ctrl_left:      db 'LEFT  : Steer L', 0
ctrl_right:     db 'RIGHT : Steer R', 0
ctrl_exit:      db 'ESC   : Exit', 0
prompt_msg:     db 'PHASE 1 READY - PRESS ANY KEY', 0

; =========================================================================
; HELPER: PRINT NULL-TERMINATED STRING AT (ROW, COL) WITH ATTRIBUTE
; Inputs: DH = row, DL = col, BL = attribute, SI = string offset
; =========================================================================
print_str:
    push ax
    push bx
    push dx
    push di
    push si

    mov al, dh
    mov cl, 80
    mul cl
    xor ch, ch
    mov cl, dl
    add ax, cx
    shl ax, 1
    mov di, ax

    mov ah, bl
.next_char:
    lodsb
    cmp al, 0
    je .done
    mov [es:di], ax
    add di, 2
    jmp .next_char

.done:
    pop si
    pop di
    pop dx
    pop bx
    pop ax
    ret

; =========================================================================
; DRAW BACKGROUND: GRASS, ROAD, BORDERS & LANE DIVIDERS
; =========================================================================
draw_road:
    mov ax, 0xB800
    mov es, ax
    xor di, di
    xor bx, bx                  ; BX = current row (0..24)

.row_loop:
    xor cx, cx                  ; CX = current col (0..79)

.col_loop:
    cmp cx, 19
    jb .left_grass
    je .road_border
    cmp cx, 60
    je .road_border
    ja .right_panel

    ; Inside road (cols 20..59)
    cmp cx, 33
    je .lane_divider
    cmp cx, 46
    je .lane_divider

    ; Dark gray asphalt
    mov word [es:di], 0x0820
    jmp .advance

.left_grass:
    ; Green grass with subtle texture
    mov ax, bx
    add ax, cx
    test al, 1
    jz .grass_light
    mov word [es:di], 0x2AB0
    jmp .advance
.grass_light:
    mov word [es:di], 0x2220
    jmp .advance

.road_border:
    ; Alternating yellow and white curb stripes
    test bl, 1
    jz .curb_yellow
    mov word [es:di], 0x7FDB
    jmp .advance
.curb_yellow:
    mov word [es:di], 0x6EDB
    jmp .advance

.lane_divider:
    ; Dashed white lane lines (draw on rows where row % 4 < 2)
    mov al, bl
    and al, 3
    cmp al, 2
    jae .asphalt_gap
    mov word [es:di], 0x0FB3
    jmp .advance
.asphalt_gap:
    mov word [es:di], 0x0820
    jmp .advance

.right_panel:
    ; Dark blue dashboard background (cols 61..79)
    mov word [es:di], 0x1720

.advance:
    add di, 2
    inc cx
    cmp cx, 80
    jb .col_loop

    inc bx
    cmp bx, 25
    jb .row_loop
    ret

; =========================================================================
; DRAW CAR AT (DH = TOP ROW, DL = LEFT COL, BL = BODY COLOR ATTRIBUTE)
; Car size: 5 columns wide x 3 rows tall
; =========================================================================
draw_car:
    push ax
    push bx
    push cx
    push dx
    push di

    ; Calculate starting video offset: (DH * 80 + DL) * 2
    mov al, dh
    mov cl, 80
    mul cl
    xor ch, ch
    mov cl, dl
    add ax, cx
    shl ax, 1
    mov di, ax

    ; Row 0: Front hood + headlights
    mov byte [es:di], 0xDC          ; Left headlight
    mov byte [es:di+1], 0x0E        ; Yellow headlight
    mov byte [es:di+2], 0xDF
    mov byte [es:di+3], bl
    mov byte [es:di+4], 0xDB
    mov byte [es:di+5], bl
    mov byte [es:di+6], 0xDF
    mov byte [es:di+7], bl
    mov byte [es:di+8], 0xDC        ; Right headlight
    mov byte [es:di+9], 0x0E

    ; Row 1: Windshield & cabin
    add di, 160
    mov byte [es:di], 0xDB          ; Left front wheel
    mov byte [es:di+1], 0x07
    mov byte [es:di+2], 0xB1        ; Windshield
    mov byte [es:di+3], 0x3B
    mov byte [es:di+4], 0xDB        ; Roof
    mov byte [es:di+5], bl
    mov byte [es:di+6], 0xB1        ; Windshield
    mov byte [es:di+7], 0x3B
    mov byte [es:di+8], 0xDB        ; Right front wheel
    mov byte [es:di+9], 0x07

    ; Row 2: Rear bumper + taillights
    add di, 160
    mov byte [es:di], 0xDF          ; Left taillight
    mov byte [es:di+1], 0x0C        ; Red taillight
    mov byte [es:di+2], 0xDB
    mov byte [es:di+3], bl
    mov byte [es:di+4], 0xDB
    mov byte [es:di+5], bl
    mov byte [es:di+6], 0xDB
    mov byte [es:di+7], bl
    mov byte [es:di+8], 0xDF        ; Right taillight
    mov byte [es:di+9], 0x0C

    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; =========================================================================
; DRAW FUEL CANISTER AT (DH = ROW, DL = COL)
; =========================================================================
draw_fuel:
    push ax
    push cx
    push dx
    push di

    mov al, dh
    mov cl, 80
    mul cl
    xor ch, ch
    mov cl, dl
    add ax, cx
    shl ax, 1
    mov di, ax

    mov word [es:di],   0x4F46      ; 'F' white on red
    mov word [es:di+2], 0x4F55      ; 'U'
    mov word [es:di+4], 0x4F45      ; 'E'
    mov word [es:di+6], 0x4F4C      ; 'L'

    pop di
    pop dx
    pop cx
    pop ax
    ret

; =========================================================================
; DRAW SIDE HUD & LABELS
; =========================================================================
draw_hud:
    ; Top banner in grass area
    mov dh, 1
    mov dl, 2
    mov bl, 0x2F
    mov si, title_str
    call print_str

    ; Right panel HUD
    mov dh, 2
    mov dl, 62
    mov bl, 0x1E
    mov si, title_str
    call print_str

    mov dh, 5
    mov dl, 62
    mov bl, 0x1F
    mov si, score_lbl
    call print_str

    mov dh, 7
    mov dl, 62
    mov bl, 0x1E
    mov si, coins_lbl
    call print_str

    mov dh, 9
    mov dl, 62
    mov bl, 0x1F
    mov si, fuel_lbl
    call print_str

    mov dh, 10
    mov dl, 62
    mov bl, 0x1A
    mov si, fuel_bar
    call print_str

    mov dh, 12
    mov dl, 62
    mov bl, 0x1B
    mov si, gear_lbl
    call print_str

    mov dh, 14
    mov dl, 62
    mov bl, 0x1F
    mov si, speed_lbl
    call print_str

    mov dh, 17
    mov dl, 62
    mov bl, 0x1E
    mov si, ctrl_title
    call print_str

    mov dh, 19
    mov dl, 62
    mov bl, 0x17
    mov si, ctrl_left
    call print_str

    mov dh, 20
    mov dl, 62
    mov bl, 0x17
    mov si, ctrl_right
    call print_str

    mov dh, 21
    mov dl, 62
    mov bl, 0x17
    mov si, ctrl_exit
    call print_str

    ; Bottom status bar on road
    mov dh, 24
    mov dl, 25
    mov bl, 0x70
    mov si, prompt_msg
    call print_str
    ret

; =========================================================================
; MAIN PROGRAM ENTRY POINT
; =========================================================================
start:
    ; Set 80x25 color text mode (clears screen & hides cursor cleanly)
    mov ax, 0x0003
    int 0x10

    ; Hide blinking hardware cursor
    mov ah, 0x01
    mov cx, 0x2607
    int 0x10

    ; Draw road, borders, and HUD
    call draw_road
    call draw_hud

    ; Draw Player Car (Cyan/Blue body) in center lane
    mov dh, 19
    mov dl, 37
    mov bl, 0x0B
    call draw_car

    ; Draw Traffic Car 1 (Red body) in left lane
    mov dh, 4
    mov dl, 24
    mov bl, 0x0C
    call draw_car

    ; Draw Traffic Car 2 (Yellow/Brown body) in right lane
    mov dh, 10
    mov dl, 51
    mov bl, 0x0E
    call draw_car

    ; Draw Fuel pickup in center lane
    mov dh, 7
    mov dl, 38
    call draw_fuel

    ; Wait for any key before exiting
    mov ah, 0x00
    int 0x16

    ; Restore standard text mode and cursor before exit
    mov ax, 0x0003
    int 0x10

    mov ax, 0x4C00
    int 0x21