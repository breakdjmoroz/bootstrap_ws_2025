MEMORY {
  kernel_space (rwx) : ORIGIN = 0x80200000, LENGTH = 256K
}

SECTIONS {
  .text : {
    mini.o(.text.kernel)
  } > kernel_space
}
