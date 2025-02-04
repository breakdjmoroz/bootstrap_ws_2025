all: build
	qemu-system-riscv64 -machine virt -drive id=hd0,file=text.txt,format=raw,if=none -device virtio-blk-device,drive=hd0,bus=virtio-mmio-bus.0 -kernel mini.bin

build: link

link: compile
	riscv64-elf-ld request.o virt_queue.o hd_drive.o mini.o -T mini.ld -o mini.bin

compile:
	riscv64-elf-as mini.s -o mini.o
	riscv64-elf-as hd_drive.s -o hd_drive.o
	riscv64-elf-as virt_queue.s -o virt_queue.o
	riscv64-elf-as request.s -o request.o
