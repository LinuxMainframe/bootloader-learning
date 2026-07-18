[org 0x7E00]
[bits 16]

stagetwo:
    mov si, stagemsg
    call print_string
    jmp entry

stagemsg db "Loaded stage two!", 0x0D, 0x0A, 0
dl_loc dw 0x0000
cyl_max dw 0x0000
sec_max dw 0x0000
hd_max dw 0x0000
det_drives db 0x00
param_table_pntr dw 0x00

data_out_ascii db 0x00, 0x00, 0x00, 0x00, 0x00,  0
bin_ascii db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0

read_err db "Failed to read drive parameters!", 0x0D, 0x0A, 0
cyl_msg db "You have the following cylinders available: 0x", 0
hd_msg db "You have the following heads available: 0x", 0
sec_msg db "You have the following sectors available: 0x", 0
open_paren db " (", 0
closed_paren db ")", 0
return_msg db 0x0D, 0x0A, 0

entry:
    mov [dl_loc], dl
    call get_drive_params
    jmp $

; get drive parameters
; requires caller has set dl correctly if it has changed
; requires ax, bx, cx, dx, and si
; caller takes responsibility of making sure data is safe
get_drive_params:
    mov ah, 0x08
    mov dl, [dl_loc]
    int 0x13
    jc .failed_read
    mov word [cyl_max], 0
    xor bx, bx ; clear bx for usage
    mov bl, cl ; copy the low bits of cl into bl
    and bl, 0xC0 ; mask to keep only top 2 bits
    shl bx, 2 ; bit shift left 2
    and cl, 0x3F ; clearing 2 top bits to avoid garbage
    add bl, ch
    mov [cyl_max], bx ; 16 bits
    mov [sec_max], cl ; 8 bits
    mov [hd_max], dh ; 8 bits

    mov di, data_out_ascii
    mov ax, [cyl_max]
    mov cx, 0x04
    call hex_to_decimal

    mov si, cyl_msg
    call print_string

    mov si, data_out_ascii
    call print_string

    mov si, open_paren
    call print_string

    mov di, bin_ascii
    mov ax, [cyl_max]
    call binary_to_decimal
    mov si, bin_ascii
    call print_string

    mov si, closed_paren
    call print_string

    mov si, return_msg
    call print_string

    mov di, data_out_ascii
    mov ax, [hd_max]
    mov cx, 0x04
    call hex_to_decimal

    mov si, hd_msg
    call print_string

    mov si, data_out_ascii
    call print_string

    mov si, open_paren
    call print_string

    mov di, bin_ascii
    mov ax, [hd_max]
    call binary_to_decimal
    mov si, bin_ascii
    call print_string

    mov si, closed_paren
    call print_string

    mov si, return_msg
    call print_string

    mov di, data_out_ascii
    mov ax, [sec_max]
    mov cx, 0x04
    call hex_to_decimal

    mov si, sec_msg
    call print_string

    mov si, data_out_ascii
    call print_string

    mov si, open_paren
    call print_string

    mov di, bin_ascii
    mov ax, [sec_max]
    call binary_to_decimal
    mov si, bin_ascii
    call print_string

    mov si, closed_paren
    call print_string

    mov si, return_msg
    call print_string
    ret

    .failed_read:
        mov si, read_err
        call print_string
        jmp $

; binary to decimal
; uses div bl, which is AX / BL
; returns AL stores quotient and AH stores remainder
; uses di to store address to buffer that will store ascii text
; uses dx for handling pushing and popping to stack
binary_to_decimal:
    mov cx, 0x0
    xor dx, dx
    .loop:
        mov bl, 0x0A
        div bl        ; div by 10 (0x0A)
        mov bl, 0x30  ; we add by 0x30 to convert to ascii
        add ah, bl    ; add 0x30
        mov dl, ah    ; store 8 bits into 16 bit register
        push dx       ; push to stack before we store it
        inc cx
        xor bx, bx    ; clear bx
        mov bl, al    ; move bits into lower bits
        mov ax, bx    ; copy over the full bits over to ax, we converted an 8 bit to a 16bit value
        cmp al, 0x0   ; is the quotient zero?
        je .done
        jmp .loop
    .done:
        pop dx
        mov [di], dl
        dec cx
        inc di
        cmp cx, 0x0
        jne .done
        mov byte [di], 0x0
        ret

;buffer db 0x0,0x0,0x0,0x0, 0x0D, 0x0A, 0
;val dw 0x1234

;test:
;    mov di, buffer
;    mov ax, [val]
;    mov cx, 0x04
;    call hex_to_decimal
;    mov si, buffer
;    call print_string
;    jmp $


;; hex-to-decimal
;; caller must set AX to proper hex to be converted
;; caller must set CX to the number of hex digits
;; caller must set DI to pointer to array of size 16bits
;; clears bx for internal logic
;; you will need to explicitly declare a buffer
;; for the hex you want to store once translated
hex_to_decimal:
    xor bx, bx
.loop:
    rol ax, 4
    mov bx, ax
    and al, 0x0F

    add al, 0x90
    daa
    add al, 0x40
    daa

    mov [di], al
    dec cx
    inc di
    mov ax, bx
    cmp cx, 0
    jg .loop
    ret

print_string:
    lodsb
    or al,al
    jz .zero

    mov ah, 0x0E ; teletype mode
    int 0x10 ; call interrupt
    jmp print_string
    .zero:
        ret
