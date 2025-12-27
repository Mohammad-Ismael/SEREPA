module ascon_permutation (
  input logic clk,
  input logic rst_n,
  input logic asc_en,
  input logic permutation_en,
  input logic [319:0] state_in,
  input logic [3:0] rounds,
  output logic [319:0] state_out,
  output logic done
);

// Internal control signals
logic load_state, update_state;
logic [3:0] round_counter;
logic [7:0] round_constant;


// Controller instantiation
ascon_controller controller_inst (
  .clk(clk),
  .rst_n(rst_n),
  .asc_en(asc_en),
  .permutation_en(permutation_en),
  .rounds(rounds),
  .load_state(load_state),
  .round_counter(round_counter),
  .round_constant(round_constant),
  .update_state(update_state),
  .done(done)
);

// Datapath instantiation
ascon_datapath datapath_inst (
  .clk(clk),
  .asc_en(asc_en),
  .rst_n(rst_n),
  .state_in(state_in),
  .load_state(load_state),
  .update_state(update_state),
  .round_constant(round_constant),
  .state_out(state_out)
);

endmodule

module ascon_controller (
  input logic clk,
  input logic rst_n,
  input logic asc_en,
  input logic permutation_en,
  input logic [3:0] rounds,
  output logic load_state,
  output logic [3:0] round_counter,
  output logic [7:0] round_constant,
  output logic update_state,
  output logic done
);

// State machine - NEED 4 STATES TO MATCH WORKING CODE TIMING
typedef enum logic [1:0] {
  IDLE,
  LOAD, // NEW STATE: Load the input state
  ROUND,
  FINISH
} state_t;

state_t current_state, next_state;

// Round constants
const logic [7:0] RC[12] = '{
  8'hf0, 8'he1, 8'hd2, 8'hc3, 8'hb4, 8'ha5,
  8'h96, 8'h87, 8'h78, 8'h69, 8'h5a, 8'h4b
};

// State register
(* optimize_power *)
always_ff @(posedge clk or posedge rst_n) begin
  if (rst_n) current_state <= IDLE;
  else current_state <= next_state;
end

// Next state logic
(* optimize_power *)
always_comb begin
  next_state = current_state;
  case (current_state)
    IDLE: if (permutation_en) next_state = LOAD;
    LOAD: next_state = ROUND; // After loading, go to ROUND
    ROUND: if (round_counter == rounds) next_state = FINISH;
    FINISH: next_state = IDLE;
  endcase
end

// Round counter - RESET at LOAD, not IDLE
(* optimize_power *)
always_ff @(posedge clk or posedge rst_n) begin
  if (rst_n) round_counter <= 4'd0;
  else if (current_state == LOAD) round_counter <= 4'd1;
  else if (current_state == ROUND) round_counter <= round_counter + 4'd1;
  else if (current_state == FINISH) round_counter <= 0;
end

// Control signals - FIXED TIMING
assign load_state = (current_state == LOAD);
assign update_state = (current_state == ROUND);
assign done = (current_state == FINISH);

// Round constant selection - CRITICAL FIX: round_counter starts at 0 AFTER LOAD
assign round_constant = (current_state == ROUND) ? RC[12 - rounds + round_counter - 4'd1] : 8'h0;

endmodule


module ascon_datapath (
input logic clk,
input logic rst_n,
input logic asc_en,
input logic [319:0] state_in,
input logic load_state,
input logic update_state,
input logic [7:0] round_constant,
output logic [319:0] state_out
);

// State registers
logic [63:0] x0_reg, x1_reg, x2_reg, x3_reg, x4_reg;


logic [63:0] s0, s1, s2, s3, s4;
logic [63:0] xtemp;

(* optimize_power *)
always_comb begin
if(asc_en) begin
// Start with current registers


s0 = x0_reg;
s1 = x1_reg;
s2 = x2_reg ^ {56'b0, round_constant}; // Add round constant
s3 = x3_reg;
s4 = x4_reg;

// S-box (EXACT SAME AS WORKING CODE)
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

// Linear diffusion (EXACT SAME AS WORKING CODE)
s0 = s0 ^ {s0[18:0], s0[63:19]} ^ {s0[27:0], s0[63:28]};
s1 = s1 ^ {s1[60:0], s1[63:61]} ^ {s1[38:0], s1[63:39]};
s2 = s2 ^ {s2[0:0], s2[63:1]} ^ {s2[5:0], s2[63:6]};
s3 = s3 ^ {s3[9:0], s3[63:10]} ^ {s3[16:0], s3[63:17]};
s4 = s4 ^ {s4[6:0], s4[63:7]} ^ {s4[40:0], s4[63:41]};

end else begin
  s0 = 0;
  s1 = 0;
  s2 = 0;
  s3 = 0;
  s4 = 0;
  xtemp = 0;
end
end
(* optimize_power *)

// ========== STATE REGISTERS ==========
always_ff @(posedge clk) begin
if (asc_en && (load_state || update_state)) begin
    if (load_state) begin
      x0_reg <= state_in[319:256];
      x1_reg <= state_in[255:192];
      x2_reg <= state_in[191:128];
      x3_reg <= state_in[127:64];
      x4_reg <= state_in[63:0];
    end else begin
      x0_reg <= s0;
      x1_reg <= s1;
      x2_reg <= s2;
      x3_reg <= s3;
      x4_reg <= s4;
    end
  end else begin
    x0_reg <= 0;
    x1_reg <= 0;
    x2_reg <= 0;
    x3_reg <= 0;
    x4_reg <= 0;
end
end

// Output assignments
always_comb begin 
if(asc_en) begin 
  state_out = {x0_reg, x1_reg, x2_reg, x3_reg, x4_reg};
end else begin 
  state_out = 0;
end
end

endmodule