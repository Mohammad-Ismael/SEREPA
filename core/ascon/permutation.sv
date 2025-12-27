

module ascon_permutation (
  input logic [319:0] state_in,
  input logic [7:0] round_constant,
  output logic [319:0] state_out
);

  logic [63:0] s0, s1, s2, s3, s4;
  logic [63:0] xtemp;

  always_comb begin
      s0 = state_in[319:256];
      s1 = state_in[255:192];
      s2 = state_in[191:128] ^ {56'b0, round_constant};
      s3 = state_in[127:64];
      s4 = state_in[63:0];

      // S-box
      s0 = s0 ^ s4;
      s4 = s4 ^ s3;
      s2 = s2 ^ s1;
      xtemp = s0 & ~s4;
      s0 = s0 ^ (s2 & ~s1);
      s2 = s2 ^ (s4 & ~s3);
      s4 = s4 ^ (s1 & ~s0);
      s1 = s1 ^ (s3 & ~s2);
      s3 = s3 ^ xtemp;
      s1 = s1 ^ s0;
      s3 = s3 ^ s2;
      s0 = s0 ^ s4;
      s2 = ~s2;

      // Linear diffusion
      s0 = s0 ^ {s0[18:0], s0[63:19]} ^ {s0[27:0], s0[63:28]};
      s1 = s1 ^ {s1[60:0], s1[63:61]} ^ {s1[38:0], s1[63:39]};
      s2 = s2 ^ {s2[0:0],  s2[63:1]}  ^ {s2[5:0],  s2[63:6]};
      s3 = s3 ^ {s3[9:0],  s3[63:10]} ^ {s3[16:0], s3[63:17]};
      s4 = s4 ^ {s4[6:0],  s4[63:7]}  ^ {s4[40:0], s4[63:41]};
  end

  assign state_out = {s0, s1, s2, s3, s4};

endmodule