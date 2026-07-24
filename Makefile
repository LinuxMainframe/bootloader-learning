NASM = nasm
QEMU = qemu-system-x86_64

BUILD_DIR = build
TARGET_IMAGE = $(BUILD_DIR)/image.bin

all: $(TARGET_IMAGE)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(BUILD_DIR)/boot.bin: boot.asm | $(BUILD_DIR)
	$(NASM) -f bin boot.asm -o $@

$(BUILD_DIR)/second.bin: second.asm | $(BUILD_DIR)
	$(NASM) -f bin second.asm -o $@

$(TARGET_IMAGE): $(BUILD_DIR)/boot.bin $(BUILD_DIR)/second.bin
	cat $(BUILD_DIR)/boot.bin $(BUILD_DIR)/second.bin > $@

run: $(TARGET_IMAGE)
	$(QEMU) -fda $(TARGET_IMAGE) -m 8G

clean:
	rm -rf $(BUILD_DIR)

.PHONY: all run clean
