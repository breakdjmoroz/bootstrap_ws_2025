.global _start
.section .text.kernel

_start: li a7, 0x4442434E
        li a6, 0x00
        li a0, 30
        lla a1, debug_string
        li a2, 0

        call virtio_blk_init

        bne a3, zero, loop
        ecall

        li a7, 0x4442434E
        li a6, 0x00
        li a0, 30
        lla a1, queue_str

        call virtqueue_init

        bne a3, zero, loop
        ecall

        li a7, 0x4442434E
        li a6, 0x00
        li a0, 29
        lla a1, read_blk

        call virtio_blk_read_request

        bne a3, zero, loop
        ecall

loop:   j loop

        .section .rodata
debug_string:
        .string "VirtIO device is initialized!\n"
queue_str:
        .string "Virtual queue is initialized!\n"
read_blk:
        .string "Block reading is successful!\n"
