# Bootloader & OS Dev Playground

This repository contains my personal bootloader and x86 OS development code. It's a hands-on learning project where I'm exploring bare-metal assembly, x86 architecture, real mode BIOS interrupts, memory mapping, and system initialization.

The codebase is meant to grow over time as I learn more. It isn't a production operating system—just an active workspace where I try things out, document milestones, and break stuff until it works.

## Current Progress

* **Stage 1 (MBR):** Standard 512-byte boot sector loaded at `0x7C00`. Loads Stage 2 from disk using BIOS CHS reads and jumps to `0x7E00`.
* **Stage 2:** Real mode environment loaded at `0x7E00`.
  * Queries BIOS drive parameters (`INT 13h, AH=08h`).
  * Maps physical memory via E820 (`INT 15h, AX=E820h`) and formats the table output.
  * Queries A20 gate support (`INT 15h, AX=2403h`).

## Project Layout

* `boot.asm`: Stage 1 MBR source code.
* `second.asm`: Stage 2 bootloader source code.
* `x86_std_assembly_lib/`: Reusable assembly routines (string printing, number-to-ASCII conversions).
* `archive/`: Snapshots of previous working versions for quick reference and diffing.
* `build/`: Target binary outputs (ignored by git).

## Building & Running

Requirements: `nasm`, `make`, and `qemu-system-x86_64`.

To build the project and launch it in QEMU:

```bash
make all
make run
make clean
'''
