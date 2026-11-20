[org 0x0100]

    jmp start

; =========================================================================
; GAME STATE & HUD STRINGS
; =========================================================================
title_str:      db 'DR DRIVING LITE', 0
score_lbl:      db 'SCORE : ', 0
score_buf:      db '0000', 0
time_lbl:       db 'TIME  :', 0
fuel_lbl:       db 'FUEL  :', 0
bar_buf:        db '[||||||||||]', 0
gear_lbl:       db 'GEAR  : D', 0
speed_lbl:      db 'SPEED : 80 KM/H', 0
ctrl_title:     db '--- CONTROLS ---', 0
ctrl_left:      db 'LEFT/A  : Left', 0
ctrl_right:     db 'RIGHT/D : Right', 0
ctrl_exit:      db 'ESC     : Quit', 0
status_run:     db 'PHASE 2: COLLECT FUEL & DODGE TRAFFIC!', 0

end_win_msg:    db '*** LEVEL COMPLETE! ***', 0
end_crash_msg:  db '*** GAME OVER: COLLISION! ***', 0
end_fuel_msg:   db '*** GAME OVER: OUT OF FUEL! ***', 0
end_score_msg:  db 'FINAL SCORE: ', 0
end_exit_msg:   db 'Press any key to exit...', 0

; Gameplay variables
player_lane:    db 1            ; 0 = left (col 24), 1 = center (col 37), 2 = right (col 50)
player_col:     db 37
scroll_phase:   db 0
last_tick:      dw 0
frame_count:    dw 0

score:          dw 0
time_val:       db 100          ; 0..100 (10 bars)
fuel_val:       db 100          ; 0..100 (10 bars)
end_reason:     db 0            ; 1 = Win (Time up), 2 = Collision, 3 = Out of fuel

; Traffic Car 1
obs1_active:    db 1
obs1_row:       db 2
obs1_col:       db 24
obs1_color:     db 0x0C         ; Red

; Traffic Car 2
obs2_active:    db 1
obs2_row:       db 11
obs2_col:       db 50
obs2_color:     db 0x0E         ; Yellow

; Fuel Pickup
fuel_active:    db 1
fuel_row:       db 6
fuel_col:       db 38

; =========================================================================
; HELPER: PRINT NULL-TERMINATED STRING AT (DH = ROW, DL = COL, BL = ATTR)
; =========================================================================
print_str:
    push ax
    push bx
    push cx
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
    pop cx
    pop bx
    pop ax
    ret

; =========================================================================
; HELPER: FORMAT 4-DIGIT SCORE INTO score_buf
; =========================================================================
update_score_buf:
    push ax
    push bx
    push cx
    push dx
    push di

    mov ax, [score]
    mov di, score_buf + 3
    mov cx, 4
    mov bx, 10
.div_loop:
    xor dx, dx
    div bx
    add dl, '0'
    mov [di], dl
    dec di
    loop .div_loop

    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; =========================================================================
; HELPER: DRAW PROGRESS BAR (AL = VALUE 0..100, DH = ROW, DL = COL, BL = ATTR)
; =========================================================================
draw_meter:
    push ax
    push bx
    push cx
    push dx
    push di
    push si

    ; Convert AL (0..100) into filled segments (0..10)
    xor ah, ah
    mov cl, 10
    div cl                      ; AL = number of '|' bars (0..10)
    mov cl, al

    mov di, bar_buf + 1
    mov ch, 0
.fill_loop:
    cmp ch, 10
    jae .render
    cmp ch, cl
    jb .put_bar
    mov byte [di], ' '
    jmp .next_seg
.put_bar:
    mov byte [di], '|'
.next_seg:
    inc di
    inc ch
    jmp .fill_loop

.render:
    mov si, bar_buf
    call print_str

    pop si
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; =========================================================================
; DRAW SCROLLING ROAD, GRASS, CURBS & LANE DIVIDERS
; =========================================================================
draw_road:
    mov ax, 0xB800
    mov es, ax
    xor di, di
    xor bx, bx                  ; BX = row (0..24)

.row_loop:
    xor cx, cx                  ; CX = col (0..79)

.col_loop:
    cmp cx, 19
    jb .left_grass
    je .road_border
    cmp cx, 60
    je .road_border
    ja .right_panel

    ; Road interior (cols 20..59)
    cmp cx, 33
    je .lane_divider
    cmp cx, 46
    je .lane_divider

    mov word [es:di], 0x0820    ; Dark asphalt
    jmp .advance

.left_grass:
    mov ax, bx
    sub al, [scroll_phase]
    add ax, cx
    test al, 1
    jz .grass_light
    mov word [es:di], 0x2AB0
    jmp .advance
.grass_light:
    mov word [es:di], 0x2220
    jmp .advance

.road_border:
    mov al, bl
    sub al, [scroll_phase]
    test al, 1
    jz .curb_yellow
    mov word [es:di], 0x7FDB
    jmp .advance
.curb_yellow:
    mov word [es:di], 0x6EDB
    jmp .advance

.lane_divider:
    mov al, bl
    sub al, [scroll_phase]
    and al, 3
    cmp al, 2
    jae .asphalt_gap
    mov word [es:di], 0x0FB3
    jmp .advance
.asphalt_gap:
    mov word [es:di], 0x0820
    jmp .advance

.right_panel:
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
; DRAW CAR AT (DH = TOP ROW, DL = LEFT COL, BL = BODY COLOR)
; =========================================================================
draw_car:
    push ax
    push bx
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

    ; Row 0: Front hood + headlights
    mov byte [es:di], 0xDC
    mov byte [es:di+1], 0x0E
    mov byte [es:di+2], 0xDF
    mov byte [es:di+3], bl
    mov byte [es:di+4], 0xDB
    mov byte [es:di+5], bl
    mov byte [es:di+6], 0xDF
    mov byte [es:di+7], bl
    mov byte [es:di+8], 0xDC
    mov byte [es:di+9], 0x0E

    ; Row 1: Windshield & roof
    add di, 160
    mov byte [es:di], 0xDB
    mov byte [es:di+1], 0x07
    mov byte [es:di+2], 0xB1
    mov byte [es:di+3], 0x3B
    mov byte [es:di+4], 0xDB
    mov byte [es:di+5], bl
    mov byte [es:di+6], 0xB1
    mov byte [es:di+7], 0x3B
    mov byte [es:di+8], 0xDB
    mov byte [es:di+9], 0x07

    ; Row 2: Rear bumper + taillights
    add di, 160
    mov byte [es:di], 0xDF
    mov byte [es:di+1], 0x0C
    mov byte [es:di+2], 0xDB
    mov byte [es:di+3], bl
    mov byte [es:di+4], 0xDB
    mov byte [es:di+5], bl
    mov byte [es:di+6], 0xDB
    mov byte [es:di+7], bl
    mov byte [es:di+8], 0xDF
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

    mov word [es:di],   0x2F46      ; 'F' white on green
    mov word [es:di+2], 0x2F55      ; 'U'
    mov word [es:di+4], 0x2F45      ; 'E'
    mov word [es:di+6], 0x2F4C      ; 'L'

    pop di
    pop dx
    pop cx
    pop ax
    ret

; =========================================================================
; DRAW LIVE HUD (SCORE, TIME BAR, FUEL GAUGE, CONTROLS)
; =========================================================================
draw_hud:
    mov dh, 1
    mov dl, 2
    mov bl, 0x2F
    mov si, title_str
    call print_str

    mov dh, 2
    mov dl, 62
    mov bl, 0x1E
    mov si, title_str
    call print_str

    ; Score
    call update_score_buf
    mov dh, 4
    mov dl, 62
    mov bl, 0x1F
    mov si, score_lbl
    call print_str

    mov dh, 4
    mov dl, 70
    mov bl, 0x1E
    mov si, score_buf
    call print_str

    ; Time Remaining Bar
    mov dh, 6
    mov dl, 62
    mov bl, 0x1F
    mov si, time_lbl
    call print_str

    mov al, [time_val]
    mov dh, 7
    mov dl, 62
    mov bl, 0x1B
    call draw_meter

    ; Fuel Gauge Bar
    mov dh, 9
    mov dl, 62
    mov bl, 0x1F
    mov si, fuel_lbl
    call print_str

    mov al, [fuel_val]
    mov dh, 10
    mov dl, 62
    mov bl, 0x1A
    cmp al, 30
    ja .fuel_ok
    mov bl, 0x1C                ; Turns red when fuel <= 30%
.fuel_ok:
    call draw_meter

    ; Gear & Speed
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

    ; Controls
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

    mov dh, 24
    mov dl, 21
    mov bl, 0x70
    mov si, status_run
    call print_str
    ret

; =========================================================================
; HANDLE KEYBOARD INPUT (NON-BLOCKING)
; =========================================================================
handle_input:
    mov ah, 0x01
    int 0x16
    jz .no_key

    mov ah, 0x00
    int 0x16

    cmp al, 27                  ; ESC key
    je .quit_game

    cmp ah, 0x4B                ; Left Arrow
    je .move_left
    cmp al, 'a'
    je .move_left
    cmp al, 'A'
    je .move_left

    cmp ah, 0x4D                ; Right Arrow
    je .move_right
    cmp al, 'd'
    je .move_right
    cmp al, 'D'
    je .move_right
    jmp .update_col

.move_left:
    cmp byte [player_lane], 0
    je .update_col
    dec byte [player_lane]
    jmp .update_col

.move_right:
    cmp byte [player_lane], 2
    je .update_col
    inc byte [player_lane]

.update_col:
    mov al, [player_lane]
    cmp al, 0
    je .lane0
    cmp al, 1
    je .lane1
    mov byte [player_col], 50
    ret
.lane0:
    mov byte [player_col], 24
    ret
.lane1:
    mov byte [player_col], 37
.no_key:
    ret

.quit_game:
    mov byte [end_reason], 1
    ret

; =========================================================================
; UPDATE WORLD: SCROLL, MOVE TRAFFIC & FUEL, CHECK COLLISIONS & METERS
; =========================================================================
update_world:
    inc byte [scroll_phase]
    inc word [frame_count]
    add word [score], 5

    ; Move Obstacle 1 down
    inc byte [obs1_row]
    cmp byte [obs1_row], 22
    jbe .move_obs2
    mov byte [obs1_row], 0
    ; Cycle obstacle 1 lane
    mov al, [obs1_col]
    cmp al, 24
    je .o1_to_37
    cmp al, 37
    je .o1_to_50
    mov byte [obs1_col], 24
    jmp .move_obs2
.o1_to_37:
    mov byte [obs1_col], 37
    jmp .move_obs2
.o1_to_50:
    mov byte [obs1_col], 50

.move_obs2:
    inc byte [obs2_row]
    cmp byte [obs2_row], 22
    jbe .move_fuel
    mov byte [obs2_row], 0
    mov al, [obs2_col]
    cmp al, 50
    je .o2_to_24
    cmp al, 24
    je .o2_to_37
    mov byte [obs2_col], 50
    jmp .move_fuel
.o2_to_24:
    mov byte [obs2_col], 24
    jmp .move_fuel
.o2_to_37:
    mov byte [obs2_col], 37

.move_fuel:
    inc byte [fuel_row]
    cmp byte [fuel_row], 23
    jbe .check_collisions
    mov byte [fuel_row], 1
    ; Shift fuel lane across frames
    mov al, [fuel_col]
    cmp al, 38
    je .f_to_25
    cmp al, 25
    je .f_to_51
    mov byte [fuel_col], 38
    jmp .check_collisions
.f_to_25:
    mov byte [fuel_col], 25
    jmp .check_collisions
.f_to_51:
    mov byte [fuel_col], 51

.check_collisions:
    ; Check Collision with Obstacle 1 (Player is at rows 19..21, height 3)
    mov al, [obs1_col]
    cmp al, [player_col]
    jne .check_obs2
    mov al, [obs1_row]
    cmp al, 17
    jb .check_obs2
    cmp al, 21
    ja .check_obs2
    mov byte [end_reason], 2
    ret

.check_obs2:
    mov al, [obs2_col]
    cmp al, [player_col]
    jne .check_fuel_pickup
    mov al, [obs2_row]
    cmp al, 17
    jb .check_fuel_pickup
    cmp al, 21
    ja .check_fuel_pickup
    mov byte [end_reason], 2
    ret

.check_fuel_pickup:
    mov al, [fuel_col]
    dec al                      ; Align canister col (25/38/51) with car col (24/37/50)
    cmp al, [player_col]
    jne .drain_meters
    mov al, [fuel_row]
    cmp al, 19
    jb .drain_meters
    cmp al, 21
    ja .drain_meters

    ; Refill fuel & award bonus points
    add byte [fuel_val], 35
    cmp byte [fuel_val], 100
    jbe .fuel_capped
    mov byte [fuel_val], 100
.fuel_capped:
    add word [score], 100
    mov byte [fuel_row], 0

.drain_meters:
    ; Every 2 frames, drain Time & Fuel
    test word [frame_count], 1
    jnz .done_update

    ; Drain Time
    cmp byte [time_val], 2
    jbe .time_finished
    sub byte [time_val], 2
    jmp .drain_fuel
.time_finished:
    mov byte [time_val], 0
    mov byte [end_reason], 1    ; Level Complete!
    ret

.drain_fuel:
    cmp byte [fuel_val], 3
    jbe .fuel_empty
    sub byte [fuel_val], 3
    ret
.fuel_empty:
    mov byte [fuel_val], 0
    mov byte [end_reason], 3    ; Out of Fuel!
.done_update:
    ret

; =========================================================================
; END OF LEVEL SCREEN
; =========================================================================
show_end_screen:
    ; Draw centered dark popup box (rows 8..16, cols 22..57)
    mov ax, 0xB800
    mov es, ax
    mov bx, 8
.box_row:
    mov cx, 22
.box_col:
    mov al, bl
    mov dl, 80
    mul dl
    add ax, cx
    shl ax, 1
    mov di, ax
    mov word [es:di], 0x4F20    ; Red banner background
    inc cx
    cmp cx, 58
    jb .box_col
    inc bx
    cmp bx, 17
    jb .box_row

    ; Select message based on end_reason
    mov al, [end_reason]
    cmp al, 1
    je .win_banner
    cmp al, 2
    je .crash_banner
    mov si, end_fuel_msg
    jmp .print_end_title
.win_banner:
    mov si, end_win_msg
    jmp .print_end_title
.crash_banner:
    mov si, end_crash_msg

.print_end_title:
    mov dh, 10
    mov dl, 25
    mov bl, 0x4E
    call print_str

    call update_score_buf
    mov dh, 12
    mov dl, 31
    mov bl, 0x4F
    mov si, end_score_msg
    call print_str

    mov dh, 12
    mov dl, 44
    mov bl, 0x4E
    mov si, score_buf
    call print_str

    mov dh, 14
    mov dl, 28
    mov bl, 0x47
    mov si, end_exit_msg
    call print_str
    ret

; =========================================================================
; MAIN GAME LOOP
; =========================================================================
start:
    mov ax, 0x0003
    int 0x10

    mov ah, 0x01
    mov cx, 0x2607
    int 0x10

    ; Initialize timer reference
    mov ah, 0x00
    int 0x1A
    mov [last_tick], dx

game_loop:
    call handle_input
    cmp byte [end_reason], 0
    jne end_game

    ; Wait ~3 BIOS ticks (~165 ms per frame) for smooth gameplay
    mov ah, 0x00
    int 0x1A
    mov ax, dx
    sub ax, [last_tick]
    cmp ax, 3
    jb game_loop
    mov [last_tick], dx

    call update_world

    ; Render frame
    call draw_road
    call draw_hud

    ; Draw Obstacles
    mov dh, [obs1_row]
    mov dl, [obs1_col]
    mov bl, [obs1_color]
    call draw_car

    mov dh, [obs2_row]
    mov dl, [obs2_col]
    mov bl, [obs2_color]
    call draw_car

    ; Draw Fuel Canister
    mov dh, [fuel_row]
    mov dl, [fuel_col]
    call draw_fuel

    ; Draw Player Car (Flash red/white if collided)
    mov dh, 19
    mov dl, [player_col]
    mov bl, 0x0B
    cmp byte [end_reason], 2
    jne .render_player
    mov bl, 0x4E
.render_player:
    call draw_car

    cmp byte [end_reason], 0
    je game_loop

end_game:
    call show_end_screen

    ; Flush any buffered keypresses before waiting for exit key
.flush_keys:
    mov ah, 0x01
    int 0x16
    jz .wait_exit
    mov ah, 0x00
    int 0x16
    jmp .flush_keys

.wait_exit:
    mov ah, 0x00
    int 0x16

    mov ax, 0x0003
    int 0x10

    mov ax, 0x4C00
    int 0x21