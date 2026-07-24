[org 0x7E00]
[bits 16]

stagetwo:
    mov si, stagemsg
    call print_string
    jmp $

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
