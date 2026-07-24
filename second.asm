; =============================================================================
; second.asm — Stage Two Bootloader
; =============================================================================
;     AUTHOR : AIDAN A. BRADLEY
;     DATE   : July 22nd, 2026
;     VERSION: v0.6.1
; -----------------------------------------------------------------------------
; Loaded by the MBR (boot.asm) at physical address 0x7E00 and entered via a
; far jump. Running in 16-bit real mode.
;
; Responsibilities:
;   1. Print a confirmation banner so we know stage two loaded correctly.
;   2. Query BIOS INT 13h/AH=08h for the boot drive's CHS geometry.
;   3. Query BIOS INT 15h/AX=E820h for the system's physical memory map.
;   4. Print the memory map in human-readable hex/decimal form.
;   5. Probe BIOS via INT 0x15 AX=0x2403
;
; Build:
;   nasm second.asm -o second.bin
;
; Memory map used by this stage (physical addresses):
;   0x7E00 - ~0x8515 : this file's own code and data (grows as code is added) (max 
;                      size before hitting 0x9000 is 4600 bytes, as determined 
;                      in the boot.asm)
;   0x9000 - 0x9BFF  : E820 memory map entries (128 max * 24 bytes = 3072 bytes)
;   0x9C00 - 0x9DFF  : per-entry ECX size returned by BIOS (128 * 4 bytes)
;   0x9E00           : word — total number of E820 entries retrieved
;
; NOTE: the 0x9000+ region is placed well clear of this file's own code/data
; on purpose. An earlier revision stored the E820 table right after the code
; (~0x8100) and it silently grew into the running code/buffers as more
; entries came back from BIOS — always leave generous headroom here as this
; file grows.
; -----------------------------------------------------------------------------
; References:
;       https://www.cs.cmu.edu/~ralf/files.html - Ralph Brown's Interrup List
;       https://mirror.math.princeton.edu/pub/oldlinux/Linux.old/docs/interrupts/int-html/int-15.htm
; =============================================================================

[org 0x7E00]
[bits 16]

; -----------------------------------------------------------------------------
; Entry point (must be first — boot.asm far-jumps straight to 0x7E00)
; -----------------------------------------------------------------------------
stagetwo:
    jmp entry                          ; skip over the data block below

; =============================================================================
; DATA SECTION
; =============================================================================

; --- Static strings ----------------------------------------------------------
stagemsg            db "STAGE 2: FAR JUMP SUCCESSFUL", 0x0D, 0x0A, 0
driveprms           db "    READING DRIVE PARAMETERS...", 0x0D, 0x0A, 0
read_err            db "Failed to read drive parameters", 0x0D, 0x0A, 0
cyl_msg             db "You have the following cylinders available: 0x", 0
hd_msg              db "You have the following heads available: 0x", 0
sec_msg             db "You have the following sectors available: 0x", 0
mem_msg             db "Memory Allocation Table:", 0x0D, 0x0A, 0
memory_mapping      db "MEMORY ALLOCATION :    0x", 0
with                db " with ", 0
mem_size            db " bytes, is ", 0
allowed             db "free", 0x0D, 0x0A, 0
allocated           db "not free", 0x0D, 0x0A, 0
e820_err_msg        db "Error: SMAP signature not returned on INT 0x15 (AX=0xE820)", 0x0D, 0x0A, 0
cf_err_msg          db "Error: CF set during INT 0x15 return", 0x0D, 0x0A, 0
hit_max_entries_msg db "Error: max entries of INT 0x15 (AH=0xE820)", 0x0D, 0x0A, 0
open_paren          db " (", 0
closed_paren        db ")", 0
return_msg          db 0x0D, 0x0A, 0
spacer              db " : 0x", 0
length_msg          db " : length (bytes) ", 0
type_msg            db " | type: ", 0
a20_probe           db "    CHECKING A20 SUPPORT...", 0x0D, 0x0A, 0
a20_err_msg         db "Error when probing A20 line", 0x0D, 0x0A, 0
reserved_err_msg    db "AH not zero, either reserved or other", 0x0D, 0x0A, 0
no_fast_a20         db "Fast A20 via 0x92 support, NOT AVAILABLE", 0x0D, 0x0A, 0
a20_not_supported   db "A20 support, NOT AVAILABLE", 0x0D, 0x0A, 0
a20_gate            db "Checking if A20 active...", 0x0D, 0x0A, 0
a20_gate_err_msg    db "Error when checking if A20 active", 0x0D, 0x0A, 0
normal_mode         db "Keyboard Controller in Normal Mode", 0x0D, 0x0A, 0
secure_mode         db "Keyboard Controller in Secure Mode", 0x0D, 0x0A, 0
a20_disabled        db "A20 gate not enabled!", 0x0D, 0x0A, 0
a20_enabled         db "A20 gate enabled!", 0x0D, 0x0A, 0
a20_failed_simple   db "A20 gate failed to be enabled via simple method", 0x0D, 0x0A, 0
a20_success_simple  db "A20 gate enabled succesfully (check with memory wraparound test).", 0x0D, 0x0A, 0


; --- Drive geometry state (get_drive_params) --------------------------------
dl_loc              dw 0x0000           ; boot drive number, saved from DL at entry
cyl_max             dw 0x0000           ; max cylinder index reported by BIOS
sec_max             dw 0x0000           ; max sector-per-track count reported by BIOS
hd_max              dw 0x0000           ; max head index reported by BIOS
det_drives          db 0x00             ; (reserved, unused)
param_table_pntr    dw 0x00             ; (reserved, unused)

; --- Reserved / currently unreferenced ---------------------------------------
; Present in the source but not read or written by any routine below.
; Kept as-is rather than removed, in case they're earmarked for later use.
_64bit_add    db 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0
_32bit_buffer db 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0
entry_idx     dd 0                      ; (reserved, unused)

; --- Scratch conversion buffers, reused by multiple print routines ----------
; Sized generously (null-terminated) for the largest value each can hold.
data_out_ascii      db 0x00, 0x00, 0x00, 0x00, 0x00, 0                                     ; 4 hex digits + null
bin_ascii           db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
                    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0                    ; 16-bit decimal + null
entry_num           db 0x0, 0x0, 0x0, 0x0, 0x0, 0                                           ; entry index, decimal + null
base_addr           db 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
                    db 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0                            ; 64-bit base, 16 hex digits + null
length              db 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
                    db 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0                       ; 64-bit length, up to 20 decimal digits + null
type                db 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0                            ; type field, decimal + null
unit_bytes          db " Bytes", 0
unit_kib            db " KiB", 0
unit_mib            db " MiB", 0
unit_gib            db " GiB", 0
a20_support         dw 0
a20_gate_status     db 0x0
a20_enable_flag     db 0x0

; --- E820 (BIOS memory map) inputs ------------------------------------------
e820_max_entries dw 128            ; cap: 128 entries * 24 bytes = 3KB table
smap_sign        dd 0x534D4150     ; ASCII 'SMAP', required signature for INT 15h/E820h


; =============================================================================
; CODE SECTION
; =============================================================================

; -----------------------------------------------------------------------------
; entry
; Stage-two main routine. Prints the banner, runs BIOS geometry + memory
; detection, prints the results, then halts.
; -----------------------------------------------------------------------------
entry:
    mov si, stagemsg
    call print_string
    mov si, driveprms
    call print_string

    mov [dl_loc], dl                    ; DL still holds the BIOS boot-drive number here
    call get_drive_params               ; Get drive parameters printed
    call get_memory_map                 ; Get the memory mapped to hardcoded 0x9000, with info stored at 0x9C00
    call print_memory_map               ; Get the memory mapped printed out

    jmp $                               ; nothing left to do — halt


; =============================================================================
; STRING / NUMBER OUTPUT HELPERS
; =============================================================================

; -----------------------------------------------------------------------------
; print_string
; Prints a null-terminated string via BIOS teletype output.
;
; In:  SI = pointer to null-terminated char buffer
; Uses: AL, AH internally
;
; Example:
;       msg db "Hello World", 0
;       mov si, msg
;       call print_string
; -----------------------------------------------------------------------------
print_string:
    lodsb                               ; AL = [SI], SI++
    or al, al                           ; hit the null terminator?
    jz .zero                            ; yes -> return
    mov ah, 0x0E                        ; BIOS teletype function
    int 0x10
    jmp print_string
    .zero:
        ret


; -----------------------------------------------------------------------------
; bin_to_hex_ascii16
; Converts a 16-bit value to ASCII hex digits (most significant digit first).
;
; In:  AX = value to convert
;      CX = number of hex digits to emit
;      DI = destination buffer (caller must size it: CX bytes + null)
; Clobbers: BX
;
; Example:
;       buffer db 0x0, 0x0, 0x0, 0x0, 0     ; null terminated
;       val    dw 0x1234
;       mov di, buffer
;       mov ax, [val]
;       mov cx, 0x04
;       call bin_to_hex_ascii16
; -----------------------------------------------------------------------------
bin_to_hex_ascii16:
    xor bx, bx
    .loop:
        rol ax, 4                       ; rotate the next nibble into the low 4 bits
        mov bx, ax                      ; stash the rest of the value
        and al, 0x0F                    ; isolate that nibble

        ; classic nibble -> ASCII hex trick using DAA
        add al, 0x90
        daa
        add al, 0x40
        daa

        mov [di], al
        dec cx
        inc di
        mov ax, bx                      ; restore the value for the next nibble
        cmp cx, 0
        jg .loop
        mov byte [di], 0x00
        ret


; -----------------------------------------------------------------------------
; bin_to_hex_ascii32
; 32-bit counterpart of bin_to_hex_ascii16. Same nibble/DAA conversion trick,
; scaled up to EAX/EBX so it can also be called twice in a row (high half,
; then low half) to build a 64-bit hex string, since DI is left advanced
; after each call.
;
; In:  EAX = value to convert
;      CX  = number of hex digits to emit
;      DI  = destination buffer
; Clobbers: EBX
;
; Example:
;       buffer db 0x0,0x0,0x0,0x0,0x0,0x0,0x0,0x0, 0
;       val    dd 0x12345678
;       mov di, buffer
;       mov eax, [val]
;       mov cx, 0x08
;       call bin_to_hex_ascii32
; -----------------------------------------------------------------------------
bin_to_hex_ascii32:
    xor ebx, ebx
    .loop:
        rol eax, 4
        mov ebx, eax
        and al, 0x0F

        add al, 0x90
        daa
        add al, 0x40
        daa

        mov [di], al
        dec cx
        inc di
        mov eax, ebx
        cmp cx, 0
        jg .loop
        mov byte [di], 0x00
        ret


; -----------------------------------------------------------------------------
; bin_to_dec_ascii16
; Converts an unsigned 16-bit value (0-65535) to a decimal ASCII string.
; Preserves all caller registers.
;
; In:  AX = value to convert
;      DI = destination buffer (at least 6 bytes: 5 digits + null)
;
; Example:
;       buffer db "     ", 0
;       val    dw 12345
;       mov di, buffer
;       mov ax, [val]
;       call bin_to_dec_ascii16
; -----------------------------------------------------------------------------
bin_to_dec_ascii16:
    pusha

    xor cx, cx                          ; digit counter
    mov bx, 10                          ; divisor

    .divide_loop:
        xor dx, dx                          ; DX:AX / BX, so clear DX first
        div bx                              ; AX = quotient, DX = remainder (0-9)
        add dl, '0'
        push dx                             ; stash digits on the stack; last digit
                                             ; computed is least significant, so
                                             ; popping later reverses them into order
        inc cx

        test ax, ax                         ; quotient reached zero?
        jnz .divide_loop

    .pop_loop:
        pop dx                              ; most-significant digit comes off first
        mov [di], dl
        inc di
        loop .pop_loop

        mov byte [di], 0x0
        popa
        ret


; -----------------------------------------------------------------------------
; bin_to_dec_ascii32
; Converts an unsigned 32-bit value (0 - 4,294,967,295) to a decimal ASCII
; string. Same digit-reversal-via-stack technique as the 16-bit version.
;
; In:  EAX = value to convert
;      DI  = destination buffer (at least 11 bytes: 10 digits + null)
;
; Example:
;       buffer db "          ", 0
;       val    dd 3000000000
;       mov eax, [val]
;       call bin_to_dec_ascii32
; -----------------------------------------------------------------------------
bin_to_dec_ascii32:
    push eax
    push ebx
    push ecx
    push edx

    xor ecx, ecx
    mov ebx, 10

    .divide_loop:
        xor edx, edx
        div ebx
        add dl, '0'
        push dx
        inc ecx

        test eax, eax
        jnz .divide_loop

    .pop_loop:
        pop dx
        mov [di], dl
        inc di
        dec ecx
        jnz .pop_loop

        mov byte [di], 0x0

        pop edx
        pop ecx
        pop ebx
        pop eax
        ret


; -----------------------------------------------------------------------------
; bin_to_dec_ascii64
; Converts an unsigned 64-bit value to a decimal ASCII string using
; long-division by 10 across two 32-bit halves (avoids a native 64-bit
; divide, which real mode doesn't have).
;
; In:  EDX:EAX = 64-bit value (EDX = high 32 bits, EAX = low 32 bits)
;      DI      = destination buffer (at least 21 bytes: 20 digits + null)
;
; Stack frame layout while running:
;   BP points at two locals allocated on the stack right after PUSHAD:
;     [BP]     = low 32 bits  (running quotient, then scratch)
;     [BP + 4] = high 32 bits (running quotient, then scratch)
;   Each loop iteration additionally PUSHes one 16-bit ASCII digit; those
;   accumulate *above* BP (toward the top of stack) and must be fully POPped
;   by .pop_loop before the two locals are torn down — tearing them down
;   early would silently eat whichever digits hadn't been popped yet.
; -----------------------------------------------------------------------------
bin_to_dec_ascii64:
    pushad

    push edx                            ; [BP + 4] high 32 bits
    push eax                            ; [BP]     low 32 bits
    mov bp, sp

    xor cx, cx                          ; digit counter

    .divide_loop:
        ; Step 1: divide the high half by 10, keep the remainder for step 2
        mov eax, [bp + 4]
        xor edx, edx
        mov ebx, 10
        div ebx
        mov [bp + 4], eax

        ; Step 2: divide the low half by 10, folding in the previous remainder
        ; (EDX already holds it from step 1 — this is what makes the 64-bit
        ; division correct across the two 32-bit halves)
        mov eax, [bp]
        div ebx
        mov [bp], eax

        ; Step 3: remainder (0-9) is this digit
        add dl, '0'
        push dx
        inc cx

        ; Step 4: is the 64-bit quotient (high:low) now zero?
        mov eax, [bp + 4]
        or eax, [bp]
        jnz .divide_loop

    .pop_loop:
        pop dx                           ; drain every pushed digit first
        mov [di], dl
        inc di
        loop .pop_loop

        mov byte [di], 0x0

        add sp, 8                       ; NOW safe to drop the two locals —
                                         ; only after .pop_loop has emptied
                                         ; everything pushed above them
        popad
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
; BIOS DRIVE GEOMETRY (INT 13h, AH=08h)
; =============================================================================

; -----------------------------------------------------------------------------
; get_drive_params
; Queries BIOS drive geometry and prints max cylinder/head/sector values in
; both hex and decimal.
;
; In:  [dl_loc] - drive number (0x00 = floppy, 0x80 = first hard disk)
; Out: [cyl_max], [hd_max], [sec_max] populated
; -----------------------------------------------------------------------------
get_drive_params:
    pusha

    mov ah, 0x08
    mov dl, [dl_loc]
    int 0x13
    jc .failed_read

    ; ---------------------------------------------------------------------
    ; Decode CHS geometry from CX/DX per the INT 13h/AH=08h return format:
    ;   CH = low 8 bits of max cylinder
    ;   CL = bits 7:6 = high 2 bits of max cylinder, bits 5:0 = max sectors
    ;   DH = max head number (0-based)
    ; ---------------------------------------------------------------------

    ; Cylinder (10 bits total: CL[7:6] as high bits, CH as low 8 bits)
    mov bl, cl
    and bl, 0xC0
    rol bl, 2                           ; bits 7:6 -> bits 1:0
    mov bh, bl
    mov bl, ch
    mov [cyl_max], bx

    ; Sectors per track (bits 5:0 of CL)
    and cl, 0x3F
    mov [sec_max], cl

    ; Heads (DH)
    mov [hd_max], dh

    ; --- Print cylinder ----------------------------------------------------
    mov di, data_out_ascii
    mov ax, [cyl_max]
    mov cx, 0x04
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

    ; --- Print heads ---------------------------------------------------------
    mov di, data_out_ascii
    movzx ax, byte [hd_max]
    mov cx, 0x04
    call bin_to_hex_ascii16

    mov si, hd_msg
    call print_string
    mov si, data_out_ascii
    call print_string
    mov si, open_paren
    call print_string

    mov di, bin_ascii
    movzx ax, byte [hd_max]
    call bin_to_dec_ascii16
    mov si, bin_ascii
    call print_string

    mov si, closed_paren
    call print_string
    mov si, return_msg
    call print_string

    ; --- Print sectors-per-track --------------------------------------------
    mov di, data_out_ascii
    movzx ax, byte [sec_max]
    mov cx, 0x04
    call bin_to_hex_ascii16

    mov si, sec_msg
    call print_string
    mov si, data_out_ascii
    call print_string
    mov si, open_paren
    call print_string

    mov di, bin_ascii
    movzx ax, byte [sec_max]
    call bin_to_dec_ascii16
    mov si, bin_ascii
    call print_string

    mov si, closed_paren
    call print_string
    mov si, return_msg
    call print_string

    popa
    ret

    .failed_read:
        mov si, read_err
        call print_string
        jmp $                            ; unrecoverable — halt


; =============================================================================
; BIOS MEMORY MAP (INT 15h, AX=E820h)
; =============================================================================

; -----------------------------------------------------------------------------
; get_memory_map
; Walks the BIOS E820 memory map and stores every entry starting at 0x9000.
;
; Entry structure written at ES:DI (24 bytes each):
;   bytes 00-07 : base address   (64-bit)
;   bytes 08-15 : length         (64-bit)
;   bytes 16-19 : type (1=usable, 2=reserved, 3/4=ACPI, 5=unusable)
;   bytes 20-23 : extended attributes (ACPI 3.0+, pre-zeroed here)
;
; In:  smap_sign, e820_max_entries (see data section)
; Out: SI = total entries retrieved; results at 0x9000, count at 0x9E00
; -----------------------------------------------------------------------------
get_memory_map:
    pusha

    xor bx, bx
    mov es, bx                          ; ES = 0x0000, so ES:DI addresses are flat

    mov di, 0x9000                      ; entries table   (0x9000 - 0x9BFF)
    mov bp, 0x9C00                      ; ECX size table  (0x9C00 - 0x9DFF)
    xor ebx, ebx                        ; E820 continuation value — must start at 0
    xor si, si                          ; entry counter

    .loop:
        cmp si, [e820_max_entries]
        jge .hitmax

        ; BIOS may only write 20 of the 24 bytes on older implementations —
        ; pre-zero the extended-attributes field so we don't read garbage.
        mov dword [es:di + 20], 0

        ; Registers must be reloaded before every INT 15h/E820h call — BIOS
        ; overwrites EAX on return, and some BIOSes clobber ECX/EDX too.
        mov eax, 0xE820
        mov edx, [smap_sign]
        mov ecx, 24

        int 0x15

        jc .cfset                       ; carry = error, or end of list on some BIOSes
        cmp eax, [smap_sign]             ; BIOS should echo 'SMAP' back in EAX
        jne .error

        mov dword [bp], ecx              ; record how many bytes BIOS actually wrote
        add bp, 4

        add di, 24                       ; advance to next entry slot
        inc si

        test ebx, ebx                    ; EBX == 0 means that was the last entry
        jnz .loop

    .done:
        mov [0x9E00], si
        popa
        ret

    .error:
        mov si, e820_err_msg
        call print_string
        jmp $

    .cfset:
        ; Some BIOSes set CF on the final entry instead of returning EBX=0
        ; on a subsequent call — if we already have entries, treat this as
        ; normal completion rather than a hard error.
        test si, si
        jnz .done

        mov si, cf_err_msg
        call print_string
        jmp $

    .hitmax:
        mov si, hit_max_entries_msg
        call print_string
        jmp $


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


; =============================================================================
; BIOS A20 LINE INTERACTION (INT 15h, AH=240Xh) X = 1, 2, 3, 4
; =============================================================================

; Probe A20 support
;     AH = 0x2403
;     CF is error flag
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

; Get A20 gate status
;   AX = 0x2402
;   RETURNS:
;     AL = 0 if disabled, 1 if enabled, 0xF if error
get_a20_status:
    push bx
    push cx
    push dx
    push si

    mov si, a20_gate            ; Print initial status message
    call print_string

    mov ax, 0x2402              ; Query A20 status
    int 0x15
    jc .error                   ; Carry flag set = BIOS error

    ; Check Return Status in AH
    cmp ah, 0x00
    je .normal_mode
    cmp ah, 0x01
    je .secure_mode
    jmp .error                  ; AH >= 0x80 means unsupported/error

    .normal_mode:
        mov si, normal_mode
        call print_string
        jmp .check_gate_state

    .secure_mode:
        mov si, secure_mode
        call print_string

    .check_gate_state:
        ; AL holds gate status (0 = disabled, 1 = enabled)
        test al, al
        jz .disabled

    .enabled:
        mov si, a20_enabled
        call print_string
        mov al, 1
        jmp .done

    .disabled:
        mov si, a20_disabled
        call print_string
        mov al, 0
        jmp .done

    .error:
        mov si, a20_gate_err_msg
        call print_string
        mov al, 0x0F

    .done:
        pop si
        pop dx
        pop cx
        pop bx
        ret

; Enable A20 line, straightforward method
;   AX = 0x2401
;   int 0x15
;   RETURNS:
;     CF = 0 if successful
;     AL = 0 for failure
;     AL = 1 for success
enable_a20_s:
    pusha

    mov ax, 0x2401
    int 0x15
    jc .failed
    mov byte [a20_enable_flag], 0x1
    mov si, a20_success_simple
    call print_string
    jmp .return

    .failed:
        mov si, a20_failed_simple
        call print_string
        mov byte [a20_enable_flag], 0x0

    .return:
        popa
        mov al, [a20_enable_flag]
        ret

; Enable A20 line, fast method (Port 0x92)
; Safe version: ensures Bit 0 (Fast Reset) is NEVER set!
enable_a20_fast:
    push ax

    in al, 0x92
    test al, 2                  ; Is A20 already enabled?
    jnz .done                   ; If Bit 1 is already set, don't touch it!

    and al, 0xFE                ; Clear Bit 0 (prevent fast reboot!)
    or al, 0x02                 ; Set Bit 1 (enable A20)
    out 0x92, al

    .done:
        pop ax
        ret

; Memory wraparound test
; Tests 0x0000:0x0500 against 0xFFFF:0x0510 (1 MiB boundary)
; RETURNS: AL = 1 if enabled, 0 if disabled
memwrap_test:
    push bx
    push cx
    push ds
    push es
    push si
    push di

    ; DS:SI = 0x0000:0x0500
    xor ax, ax
    mov ds, ax
    mov si, 0x0500

    ; ES:DI = 0xFFFF:0x0510
    mov ax, 0xFFFF
    mov es, ax
    mov di, 0x0510

    ; Save original bytes so we don't corrupt BDA RAM
    mov cl, [ds:si]
    mov ch, [es:di]

    ; Write conflicting values
    mov byte [ds:si], 0x00
    mov byte [es:di], 0xFF

    ; Check if writing to [ES:DI] overwritten [DS:SI]
    cmp byte [ds:si], 0xFF

    ; Restore original memory contents immediately
    mov [ds:si], cl
    mov [es:di], ch

    je .disabled                ; Equal -> wrapped around -> A20 disabled

    .enabled:
        mov si, a20_enabled
        call print_string
        mov al, 1
        jmp .return

    .disabled:
        mov si, a20_disabled
        call print_string
        mov al, 0

    .return:
        pop di
        pop si
        pop es
        pop ds
        pop cx
        pop bx
        ret