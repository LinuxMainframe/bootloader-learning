[org 0x7E00]
[bits 16]

stagetwo:
    mov si, stagemsg
    call print_string
    jmp test

buffer db 0x0,0x0,0x0,0x0, 0x0D, 0x0A, 0
val dw 0x1234

test:
    mov di, buffer
    mov ax, [val]
    mov cx, 0x04
    call hex_to_decimal
    mov si, buffer
    call print_string
    jmp $


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


stagemsg db "Loaded stage two!", 0x0D, 0x0A, 0

print_string:
    lodsb
    or al,al
    jz .zero

    mov ah, 0x0E ; teletype mode
    int 0x10 ; call interrupt
    jmp print_string
    .zero:
        ret
