+++
title = "First steps into shellcodes"
date = "2020-12-30T12:11:19+02:00"
tags = ["assembly", "buffer overflow", "c", "exploitation", "shellcode", "x86_64"]
description = "First steps into writing shellcodes and executing them."
+++

The term shellcode simply represent machine code in places where it is not normally found, such as a char array.

## Create the first payload

First let's create a simple payload: a one that just... exits. Here, with status code 0.

In C, it would looks like:

```c
int main(){
    exit(0);
}
```

This program uses the exit *syscall*, giving it the value 0.

In assembly (x86_64, Intel syntax), the same code looks like:

```asm
section .text
global _start

_start:
    mov rdi, 0   ; set return code to 0
    mov rax, 60  ; use syscall number 60, which is exit
    syscall
```

Let's compile and try it:

```
$ nasm -f elf64 -o exit.o exit.asm
$ ld exit.o -o exit
$ ./exit
$ echo $?
0
```

We can look at the object file using `objdump`:

```
$ objdump -M intel -d exit

exit:     file format elf64-x86-64


Disassembly of section .text:

0000000000401000 <_start>:
  401000:       bf 00 00 00 00          mov    edi,0x0
  401005:       b8 3c 00 00 00          mov    eax,0x3c
  40100a:       0f 05
```

The opcode of our payload are the bytes in the middle column:

```
bf 00 00 00 00
b8 3c 00 00 00
0f 05
```

which can be converted to this char array: `char doexit[] = "\xbf\x00\x00\x00\x00\xb8\x3c\x00\x00\x00\x0f\x05"`. Theorically, we can execute it as follows:

```c
char doexit[] = "\xbb\x00\x00\x00\x00\xb8\x01\x00\x00\x00\xcd\x80";

int main(int argc, char **argv)
{
  int (*func)();
  func = (int (*)()) doexit;
  (int)(*func)();
}
```

However, this will cause an issue. In C, the `0x00` character (also known as *null byte*) mark the end of a string. So our shellcode will only be partially interpreted.

## Change the assembly code to avoid null bytes

There is different ways to avoid null bytes in our opcodes.

The first instruction that causes problem is `mov rdi, 0`. The null bytes exists because we are using the value `0x0`. The trick here is to use the XOR logical operator. When XOR-ing 2 identical values (in our case: registers), the result of the operation will be 0. So, to put the 0 value in the RDI register, we can simply do `xor rdi, rdi` which result in the opcode `48 31 ff`.

The second problematic instruction is `mov rax, 1`. The null bytes appears because we are moving a one-byte value (`0x1`) in a longer register. As a register can be accessed without using their full size, we can move `0x1` into the AL register which is the first byte of the RAX register. We end up having `mov al, 1` which corrsponds to `b0 3c` opcode. The final assembly code looks like:

```asm
section .text
global _start

_start:
    xor rdi, rdi ; XOR the RDI register and store the result in it
    mov al, 60   ; use AL resgister instead of full RAX
    syscall
```

With `objdump`:

```
$ objdump -M intel -d exit

exit:     file format elf64-x86-64


Disassembly of section .text:

0000000000401000 <_start>:
  401000:       48 31 ff                xor    rdi,rdi
  401003:       b0 3c                   mov    al,0x3c
  401005:       0f 05                   syscall
```

So our shellcode went from 12 to 7 bytes length, and all the null bytes are removed !

Let's use it in our C code:

```c
char doexit[] = "\x48\x31\xff\xb0\x3c\x0f\x05";

int main(){
    int (*func)();
    func = (int (*)()) doexit;
    (int)(*func)();
}
```

How does this code works ? In C, functions are just variables that point to executable code. Here, we create a function called `func` that will simply point to our code stored in `doexit`.

Now compile the program and launch it:

```
$ gcc shellcode.c -z execstack
$ ./a.out
$ echo $?
0
```

Our shellcode worked !

Note that we must use the `-z execstack` option with GCC, because it is intelligent enough to detect stack smashing attempts, and will abort the program execution.

Let's try with another exit value, for exemple 2:

```
$ objdump -M intel -d exit

exit:     file format elf64-x86-64


Disassembly of section .text:

0000000000401000 <_start>:
  401000:       40 b7 02                mov    dil,0x2
  401003:       b0 3c                   mov    al,0x3c
  401005:       0f 05
```

Replace the char array in the C code to `char doexit[] = "\x40\xb7\x02\xb0\x3c\x0f\x05"` and compile and execute it:

```
$ gcc shellcode.c -z execstack
$ ./a.out
$ echo $?
2
```

## Automate opcodes extraction 

As you can see, parsing opcodes from `objdump` can be annoying. That's why we will automate this task with a simple `bash` function:

```bash
objdumptoshellcode (){
    for i in $(objdump -d $1 -M intel | grep "^ " | cut -f2); do 
        echo -En '\x'$i
    done
    echo 
}
```

When we use it on `exit` executable, we get:

```
$ objdumptoshellcode exit
\xb3\x02\xb0\x01\xcd\x80
```

This will make our task easier in the next steps !

## Shellcode development techniques

There is multiple way to write code that will create a shellcode, and all doesn't have the same assets and drawbacks. I'll talk about jmp, call, pop and the stack techniques.

### JMP, CALL, POP

Consider the following assembly skeleton:

```asm
jmp end

main:
    pop rsi
    ...

end:
    call main
    hello: db "hello", 0xa
```

The first instruction set the instruction pointer (stored in the RIP register) to point to "end" function, so after the jump we will go inside it. The first instruction in the "end" function is `call main`. When we execute it, the address of the next instruction is pushed on the stack (in our case, the address of the string "hello\n"). This way, when we execute `pop rsi` in the "main" function, the RSI register will contain the address of our string !

We must do this because we are injecting our shellcode inside a program that is already running, which means that we can't know the exact address of the string. This is called a [position-independent executable](https://en.wikipedia.org/wiki/Position-independent_code) (also known as *PIE*).

Let's try this technique to display a message. To begin, we need to write the assembly code:

```asm
section .text
global _start

_start:
    jmp caller

    main:
        pop rsi      ; get the address of the string
        xor rax, rax ; clear the registers
        xor rdi, rdi
        xor rdx, rdx

        ; write string to stdout
        mov al, 1   ; write is syscall function 1
        mov dil, 1  ; use fd 1 (stdout)
        mov dl, 6   ; length of the string (letters + line return)
        syscall

        ; exit
        mov al, 60 ; exit is syscall function 60
        syscall

    caller:
        call main  ; put the string address on the stack
        msg: db "hello", 0xa
```

We can extract the opcodes from the executable file with our function:

```
$ objdumptoshellcode hello
\xeb\x17\x5e\x48\x31\xc0\x48\x31\xff\x48\x31\xd2\xb0\x01\x40\xb7\x01\xb2\x06\x0f\x05\xb0\x3c\x0f\x05\xe8\xe4\xff\xff\xff\x68\x65\x6c\x6c\x6f\x0a
```

and replace the char array in our C code by `char code[] = "\xeb\x17\x5e\x48\x31\xc0\x48\x31\xff\x48\x31\xd2\xb0\x01\x40\xb7\x01\xb2\x06\x0f\x05\xb0\x3c\x0f\x05\xe8\xe4\xff\xff\xff\x68\x65\x6c\x6c\x6f\x0a"`.

Then, we compile and execute it:

```
$ gcc shellcode.c -z execstack
$ ./a.out 
hello
```

### Stack technique

One of the advantage of this technique is the size of the shellcode. However, as we use the stack to store values, it is important to keep in mind the endianness of our CPU architecture. Here is the code for the same exploit, using the stack technique:

```asm
section .text
global _start

_start:
    ; clear the registers
    xor rax, rax
    xor rdi, rdi
    xor rdx, rdx    
    
    ; setting the stack
    push rdx         ; push rdx to the stack. It is empty, and
                     ; will be used as null byte
    push 0x0a6f6c6c  ; push "\noll" to the stack
    push word 0x6568 ; push "eh" to the stack
    mov al, 1        ; syscall 1 (write)
    mov dil, 1       ; fd 1 (stdout)
    mov rsi, rsp     ; we give in argument to write the stack pointer
                     ; which is pointing to our string
    mov dl, 6        ; length of the string
    syscall             
    
    ; exit
    mov al, 60  ; exit is syscall 60
    syscall
```

Firstly, we clear the registers. Next, we push RDX to stack, which will behave has null byte. After that, we push the string. As x86_64 in little endian, we start by the end of the string. Once this is done, we simply call the function as seen before, and we exit.

The corresponding opcode is: `\x48\x31\xc0\x48\x31\xff\x48\x31\xd2\x52\x68\x6c\x6c\x6f\x0a\x66\x68\x68\x65\xb0\x01\x40\xb7\x01\x48\x89\xe6\xb2\x06\x0f\x05\xb0\x3c\x0f\x05`.

So we went from a 36-byte-long shellcode with the jmp, call, pop technique to a 35-byte-long shellcode with the stack technique. In our case, the gain is minor, but still exists.

### RIP relative addressing technique

The x86_64 architecture allows another development technique because of the introduction of a new command: `rel`. This allows us to write code which is position-independent. The address in question is calculated relatively to the RIP pointer. Here is the same shellcode, written following this technique:

```asm
section .text
global _start

; we declare our variable containing the string
_start:
    jmp main
    hello: db "hello", 0xa

main:
    ; clear the registers
    xor rax, rax
    xor rdi, rdi
    xor rdx, rdx

    ; set the syscall parameters as usual
    mov al, 1
    mov dil, 1
    lea rsi, [rel hello] ; move the relative address of the string
                         ; into RSI
    mov dl, 6 ; length of the string
    syscall
    
    ; exit
    mov al, 60
    syscall
```

The corresponding shellcode is: `\xeb\x06\x68\x65\x6c\x6c\x6f\x0a\x48\x31\xc0\x48\x31\xff\x48\x31\xd2\xb0\x01\x40\xb7\x01\x48\x8d\x35\xe5\xff\xff\xff\xb2\x06\x0f\x05\xb0\x3c\x0f\x05`. Is has a lentgh of 37 bytes.

If we check the compiled object with `objdump`, we clearly see that the address stored in RSI is relative to RPI:

```
$ objdump -M intel -d hellorel

hellorel:     format de fichier elf64-x86-64


Disassembly of section .text:

0000000000401000 <_start>:
  401000:	eb 06                	jmp    401008 <main>

0000000000401002 <hello>:
  401002:	68 65 6c 6c 6f       	push   0x6f6c6c65
  401007:	0a                   	.byte 0xa

0000000000401008 <main>:
  401008:	48 31 c0             	xor    rax,rax
  40100b:	48 31 ff             	xor    rdi,rdi
  40100e:	48 31 d2             	xor    rdx,rdx
  401011:	b0 01                	mov    al,0x1
  401013:	40 b7 01             	mov    dil,0x1
  401016:	48 8d 35 e5 ff ff ff 	lea    rsi,[rip+0xffffffffffffffe5]        # 401002 <hello>
  40101d:	b2 06                	mov    dl,0x6
  40101f:	0f 05                	syscall 
  401021:	b0 3c                	mov    al,0x3c
  401023:	0f 05                	syscall
```
