[org 0x7E00]
[bits 16]

stagetwo:
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

e820_max_entries dw 128 ; limits to max of 128 entries, which is at most 3KB of space, perfectly sized
smap_sign dd 0x534D4150

read_err db "Failed to read drive parameters", 0x0D, 0x0A, 0
cyl_msg db "You have the following cylinders available: 0x", 0
hd_msg db "You have the following heads available: 0x", 0
sec_msg db "You have the following sectors available: 0x", 0

mem_msg db "Memory Allocation Table:", 0x0D, 0x0A, 0
memory_mapping db "MEMORY ALLOCATION :    0x", 0
_64bit_add db 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0
with db " with ", 0
mem_size db " bytes, is ", 0
allowed db "free", 0x0D, 0x0A, 0
allocated db "not free", 0x0D, 0x0A, 0

_32bit_buffer db 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0

e820_err_msg db "Error: SMAP signature not returned on INT 0x15 (AX=0xE820)", 0x0D, 0x0A, 0
cf_err_msg db "Error: CF set during INT 0x15 return", 0x0D, 0x0A, 0
hit_max_entries_msg db "Error: max entries of INT 0x15 (AH=0xE820)", 0x0D, 0x0A, 0
open_paren db " (", 0
closed_paren db ")", 0
return_msg db 0x0D, 0x0A, 0

entry_idx dd 0

entry:
    mov si, stagemsg
    call print_string
    mov [dl_loc], dl
    call get_drive_params
    call get_memory_map
    call print_memory_map
    jmp $


;; print string
;; caller must set SI to the starting address of the character array (char *buffer[])
;; caller must supply null terminated character array
;; uses AL for internal logic
;; uses AH for internal calls
;;
;;    example usage:
;;        msg db "Hello World", 0
;;        mov si, msg
;;        call print_string
print_string:
    lodsb
    or al,al ; have we hit a null terminator?
    jz .zero ; yes? then return, otherwise loop

    mov ah, 0x0E ; teletype mode
    int 0x10 ; call interrupt
    jmp print_string
    .zero:
        ret

;; binary to ASCII-HEX 16 bit version
;; caller must set AX to proper hex to be converted
;; caller must set CX to the number of digits
;; caller must set DI to pointer to array of size 16bits
;; clears out BX for internal logic
;; you will need to explicitly declare a buffer
;;
;;     example usage:
;;         buffer db 0x0, 0x0, 0x0, 0x0, 0 ; null terminated
;;         val dw 0x1234
;;         convert_hex_to_ascii:
;;             mov di, buffer          ; move the buffer address (char *buffer[]) into DI
;;             mov ax, [val]           ; move the value stored in val (our number to convert to ASCII HEX) into AX
;;             mov cx, 0x04            ; pass in the number of digits into CX
;;             call bin_to_hex_ascii16 ; call the function
bin_to_hex_ascii16:
    xor bx, bx ; clear out BX
    .loop:
        rol ax, 4 ; rotate left to getting the highest 4 bits
        mov bx, ax ; mov the contents into BX
        and al, 0x0F ; mask the lowest bits

        add al, 0x90 ; add 0x90, begins the conversion trick
        daa ; add 0x06 if needed, set CF=1
        add al, 0x40 ; now add 0x40
        daa ; check if low bits need compensation

        mov [di], al ; mov contents of AL into DI, which points to a buffer of 16 bits
        dec cx ; decrement CX to iterate through to the next value
        inc di ; increment the buffer address
        mov ax, bx ; mov BX into AX
        cmp cx, 0 ; check if CX has reached zero (have we read all of the values to convert?)
        jg .loop ; loop again if we still have a positive CX (still have values to read)
        ret

;; binary to ascii-hex 32 bit version
;; caller must set EAX to proper hex to be converted
;; caller must set CX to number of digits
;; caller must set DI to pointer to array of size 32bits
;; clears ebx for internal logic
;; you will need to explicitly declare a buffer
;; for the hex you want to store once translated
;;
;;     example usage:
;;         buffer db 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0 ; null terminated
;;         val dw 0x12345678
;;         convert_hex_to_ascii:
;;             mov di, buffer          ; move the buffer address (char *buffer[]) into DI
;;             mov eax, [val]          ; move the value stored in val (our number to convert to ASCII HEX) into AX
;;             mov cx, 0x08            ; pass in the number of digits into CX
;;             call bin_to_hex_ascii32 ; call the function
bin_to_hex_ascii32:
    xor ebx, ebx ; zero out ebx
    .loop:
        rol eax, 4 ; rotate left 4, grabbing the lowest bits for the conversion trick
        mov ebx, eax ; move eax into ebx
        and al, 0x0F ; mask the lowest bits

        add al, 0x90 ; add 0x90 to handle first part of conversion
        daa ; add 0x06 if CF was set to 1, or dont if not, and either way, end by setting CF=1
        add al, 0x40 ; add 0x40 to create the offset correctly
        daa ; do the same trick but for the higher bit

        mov [di], al ; move the first value into the buffer
        dec cx ; decrement cx to ensure we have kept track of the fact that we already did a rol operation
        inc di ; increment by one in the buffer address
        mov eax, ebx ; move ebx contents into eax for next conversion
        cmp cx, 0 ; have we run out of values to read?
        jg .loop ; if not, loop
        ret ;  otherwise return

;; binary to ascii-decimals 16 bit version
;; caller must set AX to the unsigned 16-bit integer to convert (0 - 65535)
;; caller must set DI to pointer to destination buffer (at least 6 bytes: 5 digits + null)
;; preserves register safety across call
;;
;;      example usage:
;;          buffer db "     ", 0      ; 5 digits max for 16-bit + null
;;          val    dw 12345
;;          convert_dec16:
;;              mov di, buffer         ; DI points to output buffer
;;              mov ax, [val]          ; AX contains number to convert
;;              call bin_to_dec_ascii16
bin_to_dec_ascii16:
    pusha                              ; preserve registers for caller

    xor cx, cx                         ; CX = digit counter
    mov bx, 10                         ; BX = divisor (10)

    .divide_loop:
        xor dx, dx                         ; clear DX for 32-bit / 16-bit division (DX:AX / BX)
        div bx                             ; AX = Quotient, DX = Remainder (0-9)
        add dl, '0'                        ; convert remainder (0-9) to ASCII ('0'-'9')
        push dx                            ; push ASCII char onto stack
        inc cx                             ; increment digit count

        test ax, ax                        ; is quotient zero?
        jnz .divide_loop                   ; if not, keep dividing

    .pop_loop:
        pop dx                             ; pop ASCII character in reverse order
        mov [di], dl                       ; store character into buffer
        inc di                             ; advance buffer pointer
        loop .pop_loop                     ; loop CX times

        mov byte [di], 0x0                 ; append null terminator
        popa                               ; restore caller's registers
        ret

;; binary to ascii-decimals 32 bit version
;; caller must set EAX to the unsigned 32-bit integer to convert (0 - 4,294,967,295)
;; caller must set DI to pointer to destination buffer (at least 11 bytes: 10 digits + null)
;; uses 32-bit registers (usable in 16-bit Real Mode)
;;
;;      example usage:
;;          buffer db "          ", 0  ; 10 digits max for 32-bit + null
;;          val    dd 3000000000
;;          convert_dec32:
;;              mov di, buffer         ; DI points to output buffer
;;              mov eax, [val]         ; EAX contains number to convert
;;              call bin_to_dec_ascii32
bin_to_dec_ascii32:
    push eax                           ; preserve registers modified by logic
    push ebx
    push ecx
    push edx
    push di

    xor ecx, ecx                       ; ECX = digit counter
    mov ebx, 10                        ; EBX = divisor (10)

    .divide_loop:
        xor edx, edx                       ; clear EDX for 64-bit / 32-bit division (EDX:EAX / EBX)
        div ebx                            ; EAX = Quotient, EDX = Remainder (0-9)
        add dl, '0'                        ; convert remainder to ASCII
        push dx                            ; push ASCII character onto stack
        inc ecx                            ; increment digit count

        test eax, eax                      ; is quotient zero?
        jnz .divide_loop                   ; if not, keep dividing

    .pop_loop:
        pop dx                             ; pop ASCII character
        mov [di], dl                       ; write to buffer
        inc di                             ; advance buffer pointer
        dec ecx                            ; decrement digit counter
        jnz .pop_loop                      ; continue until stack is empty

        mov byte [di], 0x0                 ; append null terminator

        pop di                             ; restore registers
        pop edx
        pop ecx
        pop ebx
        pop eax
        ret

;; bin_to_dec_ascii64
;; Hardware-safe 64-bit integer to decimal ASCII conversion.
;; Safely handles values up to 2^64 - 1 without triggering CPU #DE exceptions.
;;
;; Inputs:
;;      EDX:EAX - 64-bit value to convert (EDX = High 32 bits, EAX = Low 32 bits)
;;      DI      - Destination buffer (at least 21 bytes: 20 digits + null)
bin_to_dec_ascii64:
    pushad                             ; preserve 16-bit registers

    ; Allocate local temporary variables on stack frame
    push edx                           ; [BP-4] High 32 bits
    push eax                           ; [BP-8] Low 32 bits
    mov bp, sp                         ; BP points to stack frame

    xor cx, cx                         ; CX = digit counter

    .divide_loop:
        ; --- Step 1: High 32-bit division ---
        mov eax, [bp + 4]                  ; Load High 32 bits
        xor edx, edx                       ; Clear EDX (Dividend = 0:EAX)
        mov ebx, 10                        ; Divisor = 10
        div ebx                            ; EAX = Quotient_High, EDX = Remainder1
        mov [bp + 4], eax                  ; Store Quotient_High back to [BP+4]

        ; --- Step 2: Low 32-bit division using Remainder1 ---
        mov eax, [bp]                      ; Load Low 32 bits
        ; EDX already contains Remainder1 (0-9) from Step 1!
        div ebx                            ; EAX = Quotient_Low, EDX = Remainder_Final
        mov [bp], eax                      ; Store Quotient_Low back to [BP]

        ; --- Step 3: Store ASCII Digit ---
        add dl, '0'                        ; Convert remainder (0-9) to ASCII character
        push dx                            ; Push onto stack
        inc cx                             ; Increment digit count

        ; --- Step 4: Loop check (Is 64-bit Quotient zero?) ---
        mov eax, [bp + 4]                  ; EAX = High 32 bits
        or eax, [bp]                       ; Combine with Low 32 bits
        jnz .divide_loop                   ; If High OR Low != 0, keep dividing

        ; Clean up stack frame
        add sp, 8

    .pop_loop:
        pop dx                             ; Pop digit in reverse order
        mov [di], dl                       ; Write character to buffer
        inc di                             ; Advance pointer
        loop .pop_loop                     ; Loop CX times

        mov byte [di], 0x0                 ; Null-terminate string
        popad                              ; Restore caller's registers
        ret

;; get_drive_params
;; Queries BIOS drive geometry using INT 13h, AH=08h.
;; Decodes maximum Cylinder, Head, and Sector per Track (CHS) values.
;; Prints formatted hex and decimal values for each parameter.
;;
;; Inputs:
;;      [dl_loc] - Drive number (e.g., 0x00 for Floppy, 0x80 for 1st Hard Disk)
;; Outputs:
;;      [cyl_max] - Maximum cylinder count (0-based max index)
;;      [hd_max]  - Maximum head count (0-based max index)
;;      [sec_max] - Maximum sectors per track (1-based max count)
get_drive_params:
    pusha                              ; preserve registers across execution

    mov ah, 0x08                       ; INT 13h AH=08h: Read Drive Parameters
    mov dl, [dl_loc]                   ; load drive index
    int 0x13
    jc .failed_read                    ; Carry Flag set = Read Error

    ; -------------------------------------------------------------------------
    ; Decode Geometry
    ; CH = Low 8 bits of Maximum Cylinder
    ; CL = Bits 6-7: High 2 bits of Maximum Cylinder | Bits 0-5: Max Sectors
    ; DH = Maximum Head Number (0-based)
    ; -------------------------------------------------------------------------
    
    ; 1. Process Cylinder Number (10 bits total: CH + CL[7:6])
    mov bl, cl                         ; BL = CL
    and bl, 0xC0                       ; Mask out sectors, keeping top 2 bits (bits 6-7)
    rol bl, 2                          ; Rotate left 2 bits (moves bits 6-7 to bits 0-1)
    mov bh, bl                         ; BH = High 2 bits of cylinder
    mov bl, ch                         ; BL = Low 8 bits of cylinder
    mov [cyl_max], bx                  ; Store 10-bit cylinder value into 16-bit variable

    ; 2. Process Sector Count (Bits 0-5 of CL)
    and cl, 0x3F                       ; Mask off cylinder bits, keep 6-bit sector count
    mov [sec_max], cl                  ; Store max sector count

    ; 3. Process Head Count (DH)
    mov [hd_max], dh                   ; Store max head count

    ; -------------------------------------------------------------------------
    ; Print Maximum Cylinder Parameter
    ; -------------------------------------------------------------------------
    mov di, data_out_ascii
    mov ax, [cyl_max]                  ; 16-bit Cylinder value
    mov cx, 0x04                       ; 4 hex digits
    call bin_to_hex_ascii16

    mov si, cyl_msg
    call print_string

    mov si, data_out_ascii
    call print_string

    mov si, open_paren
    call print_string

    mov di, bin_ascii
    mov ax, [cyl_max]
    call bin_to_dec_ascii16
    mov si, bin_ascii
    call print_string

    mov si, closed_paren
    call print_string

    mov si, return_msg
    call print_string

    ; -------------------------------------------------------------------------
    ; Print Maximum Head Parameter
    ; -------------------------------------------------------------------------
    mov di, data_out_ascii
    movzx ax, byte [hd_max]            ; Zero-extend 8-bit head value into 16-bit AX
    mov cx, 0x04                       ; 4 hex digits
    call bin_to_hex_ascii16

    mov si, hd_msg
    call print_string

    mov si, data_out_ascii
    call print_string

    mov si, open_paren
    call print_string

    mov di, bin_ascii
    movzx ax, byte [hd_max]            ; Zero-extend 8-bit head value into AX
    call bin_to_dec_ascii16
    mov si, bin_ascii
    call print_string

    mov si, closed_paren
    call print_string

    mov si, return_msg
    call print_string

    ; -------------------------------------------------------------------------
    ; Print Maximum Sector Parameter
    ; -------------------------------------------------------------------------
    mov di, data_out_ascii
    movzx ax, byte [sec_max]           ; Zero-extend 8-bit sector value into 16-bit AX
    mov cx, 0x04                       ; 4 hex digits
    call bin_to_hex_ascii16

    mov si, sec_msg
    call print_string

    mov si, data_out_ascii
    call print_string

    mov si, open_paren
    call print_string

    mov di, bin_ascii
    movzx ax, byte [sec_max]           ; Zero-extend 8-bit sector value into AX
    call bin_to_dec_ascii16
    mov si, bin_ascii
    call print_string

    mov si, closed_paren
    call print_string

    mov si, return_msg
    call print_string

    popa                               ; restore registers
    ret

    .failed_read:
        mov si, read_err
        call print_string
        jmp $                              ; Halt execution on disk read failure

;; get_memory_map
;; Detects system RAM layout using BIOS interrupt 15h, AX=E820.
;;
;; Memory Layout:
;;   0x8100 - 0x8CFF : Memory map entries array (128 entries max * 24 bytes = 3KB)
;;   0x8D00          : Word storing total number of retrieved entries (N)
;;   0x8D04 + (i*4)  : Dword storing returned ECX size (20/24) for entry i
;;
;; Entry structure at ES:DI (24 bytes):
;;      bytes 00-07 : Base address (64-bit)
;;      bytes 08-15 : Length / size (64-bit)
;;      bytes 16-19 : Type (1=Usable, 2=Reserved, 3/4=ACPI, 5=Unusable)
;;      bytes 20-23 : Extended Attributes (ACPI 3.0+ bitfield, pre-zeroed)
;;
;; Inputs:
;;      smap_sign        - dword containing 'SMAP' (0x534D4150)
;;      e820_max_entries - word set to 128 max entries limit
;; Outputs:
;;      SI               - Total number of memory map entries retrieved
get_memory_map:
    pusha                              ; preserve registers for caller

    xor bx, bx                         ; ES = 0x0000
    mov es, bx
    
    mov di, 0x8100                     ; ES:DI points to memory map entries (0x8100)
    mov bp, 0x8D04                     ; BP points to ECX size tracking array
    xor ebx, ebx                       ; Continuation offset (must start at 0)
    xor si, si                         ; Entry counter index (starts at 0)

    .loop:
        ; Check if 128 max entries threshold reached
        cmp si, [e820_max_entries]
        jge .hitmax

        ; Zero out the last 4 bytes (ACPI attributes) to prevent reading garbage
        ; if BIOS only writes a 20-byte payload.
        mov dword [es:di + 20], 0

        ; CRITICAL: Reset registers before EVERY int 0x15 call
        mov eax, 0xE820                    ; E820 function code (overwritten by BIOS on return!)
        mov edx, [smap_sign]               ; EDX = 'SMAP' signature (0x534D4150)
        mov ecx, 24                        ; Request full 24-byte entry structure

        int 0x15                           ; Execute BIOS E820 Memory Map Call

        jc .cfset                          ; Carry flag set = Error or End of List
        
        cmp eax, [smap_sign]               ; Verify EAX echoed 'SMAP' signature
        jne .error                         ; If signature mismatch, BIOS call failed

        ; Store returned ECX size (20 or 24 bytes) into 0x8D04 + (SI * 4)
        mov dword [bp], ecx
        add bp, 4                          ; Advance size-array pointer

        ; Advance entry buffer pointer and entry count
        add di, 24                         ; Stride forward by 24 bytes
        inc si                             ; Increment entry count

        ; Check continuation flag
        test ebx, ebx                      ; EBX = 0 indicates final entry reached
        jnz .loop                          ; If EBX != 0, fetch next entry

    .done:
        mov [0x8D00], si                   ; Write total valid entries count to 0x8D00
        popa                               ; Restore caller's registers
        ret


    .error:
        mov si, e820_err_msg
        call print_string
        jmp $                              ; Halt execution on error

    .cfset:
        ; Graceful handling: Some BIOS chipsets set CF on the LAST valid entry
        ; instead of returning EBX=0 on a subsequent call.
        ; If SI > 0, treat CF as normal list completion.
        test si, si
        jnz .done

        mov si, cf_err_msg
        call print_string
        jmp $                              ; Halt execution on cold error

    .hitmax:
        mov si, hit_max_entries_msg
        call print_string
        jmp $                              ; Halt execution on overflow

entry_num db 0x0, 0x0, 0x0, 0x0, 0x0, 0
spacer db " : 0x", 0
length_msg db " : length (bytes) ", 0
type_msg db " | type: ", 0
base_addr db 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0
length db 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0
type db 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0


;; print_memory_map
;; Prints formatted E820 memory map entries stored at 0x8100.
;; Uses 64-bit decimal formatting for entry length and base address display.
print_memory_map:
    pusha

    mov si, mem_msg
    call print_string

    mov cx, [0x8D00]                   ; Load total entry count
    test cx, cx                        ; Are there entries?
    jz .done                           ; If 0 entries, exit

    xor bx, bx                         ; BX = 0-based entry index

    .entry_loop:
        ; BP = 0x8100 + (BX * 24)
        mov ax, 24
        mul bx                             ; AX = BX * 24
        add ax, 0x8100                     ; Base memory offset
        mov bp, ax                         ; BP points to current 24-byte entry

        ; -------------------------------------------------------------------------
        ; 1. Print 1-indexed Entry Index
        ; -------------------------------------------------------------------------
        inc bx                             ; Convert to 1-based index
        mov ax, bx
        mov di, entry_num
        call bin_to_dec_ascii16

        mov si, entry_num
        call print_string

        mov si, spacer
        call print_string

        ; -------------------------------------------------------------------------
        ; 2. Print 64-bit Base Address (Hexadecimal)
        ; -------------------------------------------------------------------------
        mov di, base_addr
        mov cx, 8
        mov eax, [bp + 4]                  ; High 32 bits of Base Address

        push bx                            ; PROTECT BX from bin_to_hex_ascii32
        call bin_to_hex_ascii32
        pop bx                             ; RESTORE BX

        mov cx, 8
        mov eax, [bp]                      ; Low 32 bits of Base Address

        push bx                            ; PROTECT BX from bin_to_hex_ascii32
        call bin_to_hex_ascii32
        pop bx                             ; RESTORE BX

        mov si, base_addr
        call print_string

        mov si, length_msg
        call print_string

        ; -------------------------------------------------------------------------
        ; 3. Print 64-bit Length (Decimal)
        ; -------------------------------------------------------------------------

        mov dword edx, [bp + 12]  ; move stored bits from get_memory_map into eax (higher bits first)
        mov dword eax, [bp + 8]   ; load the lower bytes into eax
        mov di, length            ; load buffer address
        call bin_to_dec_ascii64   ; convert

        mov si, length
        call print_string

        ; -------------------------------------------------------------------------
        ; 4. Print the allocation Type (Decimal)
        ; -------------------------------------------------------------------------
        mov dword eax, [bp + 16] ; move type value into eax (size 4 bytes, 32 bits)
        mov di, type
        call bin_to_dec_ascii32

        mov si, type_msg
        call print_string

        mov si, type
        call print_string

        ; -------------------------------------------------------------------------
        ; Loop Condition
        ; -------------------------------------------------------------------------
        mov si, return_msg
        call print_string

        cmp bx, [0x8D00]                   ; Compare 1-based index against total count
        jl .entry_loop                     ; Loop if BX < total count

    .done:
        popa
        ret