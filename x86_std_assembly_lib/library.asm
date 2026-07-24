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

; string compare
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
;; Converts an unsigned 64-bit integer to a decimal ASCII string.
;;
;; Inputs:
;;      EDX:EAX - 64-bit value to convert (EDX = High 32 bits, EAX = Low 32 bits)
;;      DI      - Destination memory buffer (at least 21 bytes: 20 digits + null)
bin_to_dec_ascii64:
    pusha                              ; Preserve 16-bit registers

    ; Allocate local temporary variables on stack for 64-bit math
    push edx                           ; [BP-4] High 32 bits
    push eax                           ; [BP-8] Low 32 bits
    mov bp, sp                         ; BP points to local frame

    xor cx, cx                         ; CX = digit counter

    .divide_loop:
        ; --- Step 1: Divide High 32-bits by 10 ---
        mov eax, [bp + 4]                  ; Load High 32 bits
        xor edx, edx                       ; Clear upper dividend bits
        mov ebx, 10
        div ebx                            ; EAX = Quotient_High, EDX = Remainder1
        mov [bp + 4], eax                  ; Store updated High 32 bits

        ; --- Step 2: Divide (Remainder1 : Low 32-bits) by 10 ---
        mov eax, [bp]                      ; Load Low 32 bits
        ; EDX already contains Remainder1 from previous division!
        div ebx                            ; EAX = Quotient_Low, EDX = Remainder_Final
        mov [bp], eax                      ; Store updated Low 32 bits

        ; --- Step 3: Record Digit ---
        add dl, '0'                        ; Convert remainder (0-9) to ASCII
        push dx                            ; Push onto stack
        inc cx                             ; Increment character counter

        ; --- Step 4: Check if total 64-bit Quotient is Zero ---
        mov eax, [bp + 4]                  ; EAX = High 32 bits
        or eax, [bp]                       ; OR with Low 32 bits
        jnz .divide_loop                   ; If result != 0, keep dividing

        ; Clean up local stack frame
        add sp, 8

    .pop_loop:
        pop dx                             ; Pop digit in reverse order
        mov [di], dl                       ; Write ASCII character to buffer
        inc di                             ; Advance buffer pointer
        loop .pop_loop                     ; Loop CX times

        mov byte [di], 0x0                 ; Append null terminator
        popa                               ; Restore registers
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

; -----------------------------------------------------------------------------
; print_memory_map
; Prints every E820 entry gathered by get_memory_map in the form:
;   <index> : 0x<16-digit base hex> : length (bytes) <decimal> | type: <decimal>
; -----------------------------------------------------------------------------
print_memory_map:
    pusha

    mov si, mem_msg
    call print_string

    mov cx, [0x9E00]
    test cx, cx
    jz .done

    xor bx, bx                          ; 0-based entry index

    .entry_loop:
        ; BP = 0x9000 + (BX * 24) -> pointer to the current entry
        mov ax, 24
        mul bx
        add ax, 0x9000
        mov bp, ax

        ; --- 1-indexed entry number ---------------------------------------
        inc bx
        mov ax, bx
        mov di, entry_num
        call bin_to_dec_ascii16

        mov si, entry_num
        call print_string
        mov si, spacer
        call print_string

        ; --- 64-bit base address, hex --------------------------------------
        ; Two calls back to back: high 32 bits first, then low 32 bits.
        ; bin_to_hex_ascii32 leaves DI advanced, so the second call
        ; continues writing right after the first — together they form one
        ; 16-digit hex string.
        mov di, base_addr
        mov cx, 8
        mov eax, [bp + 4]
        push bx                          ; protect the entry index across the call
        call bin_to_hex_ascii32
        pop bx

        mov cx, 8
        mov eax, [bp]
        push bx
        call bin_to_hex_ascii32
        pop bx

        mov si, base_addr
        call print_string
        mov si, length_msg
        call print_string

        ; --- 64-bit length, decimal -----------------------------------------
        mov dword edx, [bp + 12]         ; high 32 bits
        mov dword eax, [bp + 8]          ; low 32 bits

        call format_size_human

        ; --- type, decimal ---------------------------------------------------
        mov dword eax, [bp + 16]
        mov di, type
        call bin_to_dec_ascii32

        mov si, type_msg
        call print_string
        mov si, type
        call print_string

        mov si, return_msg
        call print_string

        cmp bx, [0x9E00]
        jl .entry_loop

    .done:
        popa
        ret

; -----------------------------------------------------------------------------
; format_size_human
; Converts a 64-bit byte length into a primary KiB/MiB/GiB decimal representation
; with remainder, then prints it out.
;
; In:   EDX:EAX = 64-bit length in bytes
; Uses: EAX, EBX, ECX, EDX, SI, DI
; -----------------------------------------------------------------------------
format_size_human:
    pushad

    ; --- Clear the length buffer (20 bytes) ---
    mov di, length
    mov cx, 20
    xor al, al
    rep stosb

    ; Restore original registers from stack (since rep stosb modified DI/AX/CX)
    popad
    pushad

    ; Check if EDX > 0 (Length >= 4 GiB)
    test edx, edx
    jnz .is_gib_64

    ; --- 32-BIT BOUNDS CHECKS ---
    cmp eax, 1024
    jb .is_bytes

    ; Convert to KiB
    shr eax, 10
    cmp eax, 1024
    jb .is_kib

    ; Convert to MiB
    shr eax, 10
    cmp eax, 1024
    jb .is_mib

    ; Convert to GiB
    shr eax, 10
    jmp .is_gib_32

    .is_bytes:
        mov di, length
        call bin_to_dec_ascii32
        mov si, length
        call print_string
        mov si, unit_bytes
        call print_string
        jmp .done

    .is_kib:
        mov di, length
        call bin_to_dec_ascii32
        mov si, length
        call print_string
        mov si, unit_kib
        call print_string
        jmp .done

    .is_mib:
        mov di, length
        call bin_to_dec_ascii32
        mov si, length
        call print_string
        mov si, unit_mib
        call print_string
        jmp .done

    .is_gib_32:
        mov di, length
        call bin_to_dec_ascii32
        mov si, length
        call print_string
        mov si, unit_gib
        call print_string
        jmp .done

    .is_gib_64:
        ; Scale EDX:EAX down by 30 bits (Bytes -> GiB)
        shrd eax, edx, 30
        shr edx, 30

        mov di, length
        call bin_to_dec_ascii64
        mov si, length
        call print_string
        mov si, unit_gib
        call print_string

    .done:
        popad
        ret

; =============================================================================
; BIOS A20 LINE INTERACTION (INT 15h, AH=240Xh) X = 1, 2, 3, 4
; =============================================================================

; Probe A20 support
;     AH = 2403
;     bit 0 of BX : is A20 supported at all?
;     bit 1 of BX : is Fast A20 via 0x92 supported?
;     if error    : return 0xFFFF in BX
get_a20_support:
    pusha ; save 8 caller gen. registers onto stack

    mov si, a20_probe ; print little debug message
    call print_string

    mov ax, 0x2403 ; prepare the 0x2403 call : ie. QUERY A20 GATE SUPPORT - SYSTEM - later PS/2s
    int 0x15 ; based on interupt 0x15
    jc .error ; if we get a CF error bit, then we jump 
    cmp ah, 0x0 ; check if AH == 0, 
    jnz .error_reserved

    test bx, 0x0001
    jz .not_supported

    test bx, 0x0002
    jz .no_fast_a20

    mov [a20_support], bx
    jmp .return

    .not_supported:
        mov [a20_support], bx

        mov si, a20_not_supported
        call print_string

        jmp .return

    .no_fast_a20:
        mov si, no_fast_a20
        call print_string
        mov [a20_support], bx
        jmp .return

    .error:
        mov si, a20_err_msg
        call print_string

        jmp .rexit

    .error_reserved:
        mov si, reserved_err_msg
        call print_string

        jmp .rexit

    .return:
        popa
        mov bx, [a20_support]
        ret

    .rexit:
        popa
        mov bx, 0xFFFF
        ret