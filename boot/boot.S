#include <inc/mmu.h>

# Start the CPU: switch to 32-bit protected mode, jump into C.
# The BIOS loads this code from the first sector of the hard disk into
# memory at physical address 0x7c00 and starts executing in real mode
# with %cs=0 %ip=7c00.

.set PROT_MODE_CSEG, 0x8         # kernel code segment selector
.set PROT_MODE_DSEG, 0x10        # kernel data segment selector
.set CR0_PE_ON,      0x1         # protected mode enable flag

.globl start
start:
  .code16                     # Assemble for 16-bit mode
  cli                         # Disable interrupts 关闭所有中断,,因为BIOS运行时可能打开了中断
  cld                         # String operations increment 指定之后发生的串处理操作的指针移动方向

  # Set up the important data segment registers (DS, ES, SS).
  xorw    %ax,%ax             # Segment number zero
  movw    %ax,%ds             # -> Data Segment BIOS之后不能保证以下三个寄存器中的值,统一清零,为进入保护模式准备
  movw    %ax,%es             # -> Extra Segment
  movw    %ax,%ss             # -> Stack Segment

  # Enable A20:
  #   For backwards compatibility with the earliest PCs, physical
  #   address line 20 is tied low, so that addresses higher than
  #   1MB wrap around to zero by default.  This code undoes this.
  #   inb/outb是IO端口命令,对外部设备进行操作
seta20.1:
  inb     $0x64,%al               # Wait for not busy
  testb   $0x2,%al                # 检查bit1输入缓冲区是否已满(CPU传给控制器的数据是否被取走)
  jnz     seta20.1                # 不为0则反复检查

  movb    $0xd1,%al               # 0xd1 -> port 0x64
  outb    %al,$0x64               # 0xd1这条数据写入到0x64端口,代表向键盘控制器804x发送指令

  # 0xd1指令代表下一次写入0x60端口的数据将被写入给804x控制器的输出端口,即下一个写入0x60端口的数据是一个控制指令

seta20.2:
  inb     $0x64,%al               # Wait for not busy
  testb   $0x2,%al                # 判断刚刚写入的0xd1指令是否已被读取
  jnz     seta20.2

  movb    $0xdf,%al               # 0xdf -> port 0x60
  outb    %al,$0x60               # 0xdf指令作用是开启A20线,可以进入保护模式

  # Switch from real to protected mode, using a bootstrap GDT
  # and segment translation that makes virtual addresses 
  # identical to their physical addresses, so that the 
  # effective memory map does not change during the switch.
  lgdt    gdtdesc                 # 把gdtdesc的值送入GDTR(全局映射描述符表)寄存器
  movl    %cr0, %eax
  orl     $CR0_PE_ON, %eax        # CR0寄存器的bit0设为1,开启保护模式启动位
  movl    %eax, %cr0
  
  # Jump to next instruction, but in 32-bit code segment.
  # Switches processor into 32-bit mode.
  ljmp    $PROT_MODE_CSEG, $protcseg

  .code32                     # Assemble for 32-bit mode
protcseg:
  # Set up the protected-mode data segment registers
  movw    $PROT_MODE_DSEG, %ax    # Our data segment selector
  movw    %ax, %ds                # -> DS: Data Segment 重新加载所有段寄存器
  movw    %ax, %es                # -> ES: Extra Segment
  movw    %ax, %fs                # -> FS
  movw    %ax, %gs                # -> GS
  movw    %ax, %ss                # -> SS: Stack Segment
  
  # Set up the stack pointer and call into C.
  movl    $start, %esp            # 保存当前esp寄存器的值
  call bootmain                   # 跳转到 main.c 的 bootmain

  # If bootmain returns (it shouldn't), loop.
spin:
  jmp spin

# Bootstrap GDT
.p2align 2                                # force 4 byte alignment
gdt: # 3个GDT表项,3x8=24 bytes
  SEG_NULL				# null seg
  SEG(STA_X|STA_R, 0x0, 0xffffffff)	  # code seg 起始地址为0x0,大小4G
  SEG(STA_W, 0x0, 0xffffffff)	        # data seg SEG()子程序构造GDT表项(in mmu.h)

gdtdesc:
  .word   0x17                            # sizeof(gdt) - 1 GDT表大小=24(0x18)
  .long   gdt                             # address gdt GDT起始地址

