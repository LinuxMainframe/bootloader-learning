[org 0x7C00]
[bits 16]

start:
    cli
    jmp 0x0000:bootstrap

dl_loc dw 0x0000
errmsg db "Error occured during read", 0x0D, 0x0A, 0
msg db "Hello World!", 0x0D, 0x0A, 0

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
    mov [dl_loc], dl
    mov ah, 0x02 ; read sectors from drive
    mov al, 0x04 ; how many sectors to read
    mov ch, 0x00 ; cylinder
    mov dh, 0x00 ; head
    mov cl, 0x02 ; sector start (1 indexed)
    mov bx, 0x7E00 ; ES:BX (far jump shape)
    mov dl, [dl_loc]
    int 0x13 ; call the 0x13 disk read interrupt
    jc .error
    jmp 0x0000:0x7E00 ; far jump into ram
    .error:
        mov si, errmsg
        call print_string
        jmp $ ; halt on error

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
