; =============================================================================
; boot.asm — Stage One Bootloader
; =============================================================================
;     AUTHOR : AIDAN A. BRADLEY
;     DATE   : July 22nd, 2026
;     VERSION: v0.6.0
; -----------------------------------------------------------------------------
[org 0x7C00]
[bits 16]

start:
    cli ; stop interrupts momentarily
    jmp 0x0000:bootstrap ; far jump to set up CS

dl_loc dw 0x0000
errmsg db "Error occured during read", 0x0D, 0x0A, 0
msg db "STAGE 1: READY TO JUMP", 0x0D, 0x0A, 0

bootstrap:
    ; setup basics, zero things out
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00 ; move stack pointer to where we start
    cld ; turn interupts back on
    sti

    mov si, msg
    call print_string ; print loading message

    mov [dl_loc], dl ;  load drive ID
    mov ah, 0x02 ; read sectors from drive
    mov al, 0x05 ; how many sectors to read
    mov ch, 0x00 ; cylinder
    mov dh, 0x00 ; head
    mov cl, 0x02 ; sector start (1 indexed)
    mov bx, 0x7E00 ; ES:BX (far jump shape)
    mov dl, [dl_loc] ; load drive ID back into dl for later
    int 0x13 ; call the 0x13 disk read interrupt
    jc .error ; on carry flag, jump to error
    jmp 0x0000:0x7E00 ; far jump into ram
    .error:
        mov si, errmsg
        call print_string
        jmp $ ; halt on error

; basic string printing function
print_string:
    lodsb
    or al,al
    jz .zero

    mov ah, 0x0E ; teletype mode
    int 0x10 ; call interrupt
    jmp print_string
    .zero:
        ret

; pad the rest out and append magic bytes
times (510-($-$$)) db 0
dw 0xAA55
