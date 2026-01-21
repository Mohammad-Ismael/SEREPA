    .data
dead_beef_ct:
    .word 0x0             # memory for storing the variable

    .text
    .globl main
main:
    # --------------------------
    # Parameters
    # --------------------------
    li  x12, 0xdeadbeef       # initial variable value
    la  x15, dead_beef_ct     # address of memory variable
    senc  x12, 16(x15)          # store initial value             # x12 is now secure 

    li  x30, 5000             # Number of loops (change this for testing)

    # --------------------------
    # Other complex math NOT related to x12/x20 (to increase cycles)
    # --------------------------
    li  x5, 1
    li  x6, 2
    li  x7, 3
    li  x8, 4
    li  x9, 5
    li  x13, 6                                             # x13 is now not secure
    li  x14, 7                                             # x14 is now not secure
    li  x20, 8                                             # x20 is now not secure
    # long independent computations
    mul x5, x5, x6
    mul x6, x6, x7
    mul x7, x7, x8
    mul x8, x8, x9
    add x9, x5, x6
    sub x5, x7, x8
    add x6, x9, x5
    mul x7, x6, x9
    add x8, x7, x6
    sub x9, x8, x5
    mul x5, x5, x6
    mul x6, x6, x7
    mul x7, x7, x8
    mul x8, x8, x9
    add x9, x5, x6
    sub x5, x7, x8
    add x6, x9, x5
    mul x7, x6, x9
    add x8, x7, x6
    sub x9, x8, x5
    li  x12, 0                                              # x12 is not now secure                                          
    
loop_start:
    # --------------------------
    # Load variable and do complex math
    # --------------------------
    li  x9, 0
    li  x10, 0
    li  x11, 0
    lenc  x13, 16(x15)          # load variable from memory                                  # x13 is now secure
    add x14, x13, 1
    add x15, x13, 2
    add x16, x13, 3
    add x17, x13, 4
    add x18, x13, 5
    add x19, x13, 6
    add x20, x13, 7
    add x21, x13, 7
    add x22, x13, 8
    add x23, x13, 9
    add x24, x13, 10
    add x25, x13, 11

    # Example of complex math using minimal registers (x13, x14, x20)                      # x14 is now secure
    add x14, x13, x13         # x14 = x13 * 2
    mul x14, x14, x13         # x14 = x14 * x13
    addi x14, x14, 7          # x14 += 7
    slli x14, x14, 2          # x14 <<= 2
    sub x20, x14, x13         # x20 = result   
    add x9, x5, x6
    sub x5, x7, x8
    add x6, x9, x5
    mul x7, x6, x9
    add x9, x5, x6
    sub x5, x7, x8
    add x6, x9, x5
    mul x7, x6, x9
    add x8, x25, x6                                            # x20 is now secure
    add x9, x5, x6
    add x13, x13, x30
    add  x5, x13, 1
    add  x6, x13, 2
    add  x7, x13, 3
    add  x8, x13, 4
    add  x9, x13, 5
    add  x13, x13, 6                                             # x13 is now not secure
    add  x14, x13, 7                                             # x14 is now not secure
    add  x20, x13, 8                                             # x20 is now not secure
    sub x5, x7, x8
    add x6, x25, x5
    mul x7, x6, x9
    add x9, x5, x6
    sub x5, x7, x8
    add x6, x9, x5
    mul x7, x6, x9
    add x8, x7, x6
    senc  x13, 16(x15)                                            # x20 is now secure

    # Store the final result (any memory location, here just reuse dead_beef_ct)

    # --------------------------
    # Other complex math NOT related to x12/x20 (to increase cycles)
    # --------------------------
    li  x5, 1
    li  x6, 2
    li  x7, 3
    li  x8, 4
    li  x9, 5
    li  x10, 6
    li  x11, 11
    li  x12, 12
    li  x13, 0                                             # x13 is now not secure
    li  x14, 0                                             # x14 is now not secure
    li  x15, 0                                             # x14 is now not secure
    li  x16, 0                                             # x20 is now not secure
    li  x17, 0                                             # x20 is now not secure
    li  x18, 0                                             # x20 is now not secure
    li  x19, 0                                             # x20 is now not secure
    li  x25, 0                                             # x20 is now not secure
    li  x20, 0                                             # x20 is now not secure
    li x21, 0
    li x22, 0
    li x23, 0
    li x24, 0
    li x25, 0
    # long independent computations
    mul x5, x5, x6
    mul x6, x6, x7
    mul x7, x7, x8
    mul x8, x8, x9
    add x9, x5, x6
    sub x5, x7, x8
    add x6, x9, x5
    mul x7, x6, x9
    add x8, x7, x6
    sub x9, x8, x5
    mul x5, x5, x6
    mul x6, x6, x7
    mul x7, x7, x8
    mul x8, x8, x9
    mul x5, x5, x6
    mul x6, x6, x7
    mul x7, x7, x8
    mul x8, x8, x9
    add x9, x5, x6
    sub x5, x7, x8
    add x6, x9, x5
    mul x7, x6, x9
    add x8, x7, x6
    sub x9, x8, x5
    mul x5, x5, x6
    mul x6, x6, x7
    mul x7, x7, x8
    mul x8, x8, x9
    li x9, 0x1997 


    # --------------------------
    # Loop control
    # --------------------------
    addi x30, x30, -1
    bnez x30, loop_start
    
    li x31, 0xdeaddead 

    # --------------------------
    # Success exit
    # --------------------------
    li x10, 1              # return code = 1 (success)
    ecall
