[org 0x7C00]
[bits 16]
start:
    cli
    jmp 0x0000:bootstrap
bootstrap:
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    cld
    sti
    call print_bytes

terminate:
    jmp $

msg db "HELLO WORLD!", 0x0D, 0x0A, 0
print_bytes:
    mov si, msg
    call print_string
    jmp terminate

print_string:
    lodsb
    or al,al
    jz .zero

    mov ah, 0x0E ; teletype mode
    int 0x10 ; call interrupt
    jmp print_string
    .zero:
        ret

strcmp:
    .loop:
        mov al, [si]
        mov bl, [di]
        cmp al, bl
        jne .not_equal

        cmp al, 0
        je .done

        inc di
        inc si
        jmp .loop
    .not_equal:
        clc
        ret
    .done:
        stc
        ret


times (510-($-$$)) db 0
dw 0xAA55
