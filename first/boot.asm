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
    jmp $
times (510-($-$$)) db 0
dw 0xAA55
