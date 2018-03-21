KERNEL=./arch/x86/boot/bzImage
DISK=./arch/x86/boot/qemu-image.img

gdb:
	gdb \
		-ex "add-auto-load-safe-path $(pwd)" \
		-ex "file vmlinux" \
		-ex 'set arch i386:x86-64:intel' \
		-ex 'target remote localhost:1234' \
		-ex 'break start_kernel' \
		-ex 'continue' \
		-ex 'disconnect' \
		-ex 'set arch i386:x86-64' \
		-ex 'target remote localhost:1234'

qemu: $(IMAGE)
	qemu-system-x86_64 \
		-kernel $(KERNEL) \
		-hda $(DISK) \
		-append "root=/dev/sda console=ttyS0" \
		-gdb tcp::1234 \
		--nographic \
		-S

kernel:
	make -j8 bzImage

