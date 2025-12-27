`define CRYPTO_VERSION "1.2.7"
`define CRYPTO_KEYBYTES 16 // 16 byte
`define CRYPTO_NSECBYTES 0
`define CRYPTO_NPUBBYTES 16
`define CRYPTO_ABYTES 16
`define CRYPTO_NOOVERLAP 1
`define ASCON_AEAD_RATE 8

`define ASCON_128_PB_ROUNDS 6
`define ASCON_128_IV 0x80400c0600000000ull
`define RC(i) (i)
`define START(n) ((3 + (n)) << 4 | (12 - (n)))
`define INC -0x0f
`define END 0x3c

`define ASCON_KEYWORDS (CRYPTO_KEYBYTES + 7) / 8

`define ASCON_ABSORB 0x1
`define ASCON_SQUEEZE 0x2
`define ASCON_INSERT 0x4
`define ASCON_HASH 0x8
`define ASCON_ENCRYPT (ASCON_ABSORB | ASCON_SQUEEZE)
`define ASCON_DECRYPT (ASCON_ABSORB | ASCON_SQUEEZE | ASCON_INSERT)

`define ASCON_AEAD_ROUNDS ASCON_128_PB_ROUNDS

`define MAX_SIZE 1024 // Adjust the size as per your application's needs