module ascon_top (
  input logic clk,
  input logic rst,
  input logic asc_en,
  input logic enc_start,  // Signal to start the encryption process
  input logic dec_start,  // Signal to start the decryption process

  input logic [127:0] key,     // Secret key for encryption/decryption       || Constant
  input logic [127:0] nonce,  // Public nonce for ensuring uniqueness of the ciphertext || Make sure this is not kept as constant
  input logic [31:0] inPlaintext,  // Input plaintext data to be encrypted
  input logic [159:0] inCiphertext,  // Input ciphertext data to be decrypted

  output logic [127:0] enc_tag_value, // Tag value generated during decryption of cipher text finalization;
  output logic [31:0] outCiphertext,  // Output ciphertext resulting from the encryption process
  output logic [ 31:0] outDecrypted,             // Output decrypted data resulting from the decryption process
  output logic decryptionFaild,
  output logic authentication_done,
  output logic decrypting,
  output logic encrypting,
  output logic process_done
);

logic [127:0] in_tag; 
logic start_permutation, permutation_counter;  // Control signals for permutation operation
logic init_xor, init_key_xor;  // Signals for initialization key XOR operations
logic domain_separation_xor;  // Signal for domain separation XOR operation
logic finalization_xor_key, finalization_permutation;  // Signals for finalization steps
logic tag_generation_big_end;  // Signal for big-endian tag generation

// State machine states for ASCON operation
typedef enum logic [2:0] {
  IDLE,
  INITIALIZATION,
  DOMAIN_SEPARATION,
  PROCESS_DATA,
  FINALIZATION,
  TAG_GENERATION
} ascon_state_t;

typedef enum logic [2:0] {
  INITIALIZE,
  STATE_1,
  STATE_2,
  STATE_3,
  STATE_DONE
} state_t;

// State machine states for encryption/decryption mode
typedef enum logic [2:0] {
  ENCRYPTION,
  DECRYPTION,
  HALT
} enc_dec_state_t;

// Current and next states for the main state machine
ascon_state_t enc_current_state, enc_next_state;
enc_dec_state_t enc_dec_current_state;
state_t process_state, process_state_2;

// Ascon state registers
logic [63:0] x0, x1, x2, x3, x4;  // State variables for ASCON algorithm
logic [31:0] x0_cihper;           // Temporary register for ciphertext processing
logic [63:0] x0_next, x1_next, x2_next, x3_next, x4_next;  // Next state values

// Control signals to indicate completion of various stages
logic init_done, domain_sep_done , final_done, tag_done, permutation_done;

// Instance of ASCON permutation module
ascon_permutation ascon_per (
    .clk(clk),
    .rst_n(rst),
    .asc_en(asc_en),
    .permutation_en(start_permutation),  // Enable signal for permutation
    .state_in({x0, x1, x2, x3, x4}),  // Current state input
    .rounds(asc_en? 4'd12: 4'd0),  // Number of rounds (12 for initialization and finalization)
    .state_out({x0_next, x1_next, x2_next, x3_next, x4_next}),  // Next state output
    .done(permutation_done)  // Signal indicating permutation completion
);

always_comb begin
   if (rst) begin
      in_tag = 0;
   end else if(dec_start) begin
      in_tag = {inCiphertext[63:0], inCiphertext[127:64]};
    end else if(!asc_en) in_tag = 0;
end

// Main state machine for ASCON operation
always_ff @(posedge clk or posedge rst) begin
  if (rst) begin
    enc_current_state <= IDLE;  // Reset to IDLE state
  end else begin
    enc_current_state <= enc_next_state;  // Update state on clock edge
  end
end

always_comb begin
  if (rst) begin
    enc_dec_current_state = HALT;  // Reset to IDLE state
  end else begin
    enc_next_state = enc_current_state;  // Default next state is current state

    case (enc_current_state)
      IDLE: begin
        if (enc_start) begin
          enc_next_state = INITIALIZATION;  // Move to INITIALIZATION state on encryption start
          enc_dec_current_state = ENCRYPTION;  // Set mode to ENCRYPTION
        end else if (dec_start) begin
          enc_next_state = INITIALIZATION;  // Move to INITIALIZATION state on decryption start
          enc_dec_current_state = DECRYPTION;  // Set mode to DECRYPTION
        end
      end

      INITIALIZATION: begin
        if (init_done)
          enc_next_state = DOMAIN_SEPARATION; // Move to DOMAIN_SEPARATION on initialization completion
      end

      DOMAIN_SEPARATION: begin
        if (domain_sep_done)
          enc_next_state = PROCESS_DATA;  // Move to PROCESS_DATA on domain separation completion
      end

      PROCESS_DATA: begin
        if (process_done)
          enc_next_state = FINALIZATION;        // Move to FINALIZATION on data processing completion in ENCRYPTION mode
      end

      FINALIZATION: begin
        if (final_done)
          enc_next_state = TAG_GENERATION;  // Move to TAG_GENERATION on finalization completion
      end

      TAG_GENERATION: begin
        if (tag_done) begin
          enc_next_state = IDLE;  // Move to IDLE on tag generation completion
          enc_dec_current_state = HALT;
        end
      end

      default: enc_next_state = IDLE;  // Default to IDLE state
    endcase
  end
end

// Encryption FSM
always_ff @(posedge clk or posedge rst) begin
  if (rst) begin
    init_done <= 1'b0;
    enc_tag_value <= 'b0;
    domain_sep_done <= 1'b0;
    process_done <= 1'b0;
    final_done <= 1'b0;
    permutation_counter <= 1'b0;
    tag_generation_big_end <= 1'b0;
    x0_cihper <= 1'b0;

    outDecrypted <= 32'b0;
    x0 <= 64'h0;
    x1 <= 64'h0;
    x2 <= 64'h0;
    x3 <= 64'h0;
    x4 <= 64'h0;
    decryptionFaild <= 1'b0;
    authentication_done <= 1'b0;
    process_state_2 <= INITIALIZE;
    end else if(asc_en == 1) begin
        authentication_done <= 0;
        case (enc_current_state)
          INITIALIZATION: begin
            // Implement initialization logic here
            // Set x0 to IV, x1-x2 to key, x3-x4 to nonce
            process_state <= INITIALIZE;
            if (permutation_counter == 0) begin
              x0 <= 64'h80400c0600000000;
              x1 <= key[127:64];
              x2 <= key[63:0];
              x3 <= nonce[127:64];
              x4 <= nonce[63:0];
            end

            // Perform initial permutation
            if (start_permutation == 0 && permutation_counter == 0) begin
              start_permutation   <= 1;
              permutation_counter <= 1;
            end else start_permutation <= 0;

            if (permutation_done == 1) begin
              x0 <= x0_next;
              x1 <= x1_next;
              x2 <= x2_next;
              x3 <= x3_next;
              x4 <= x4_next;
              init_xor <= 1;
            end
            if (init_xor == 1'b1) begin
              x3 <= x3 ^ key[127:64];
              x4 <= x4 ^ key[63:0];
              init_key_xor <= 1'b1;
            end

            if (init_key_xor == 1'b1) begin
              init_done <= 1'b1;  // Initialization done
            end
          end

          DOMAIN_SEPARATION: begin
            permutation_counter <= 0;
            x4 <= x4 ^ 64'h1;  // Apply domain separation constant
            domain_separation_xor <= 1;

            if (domain_separation_xor == 1) domain_sep_done <= 1'b1;  // Domain separation done
          end

          PROCESS_DATA: begin
            if (enc_dec_current_state == ENCRYPTION) begin
              case (process_state)
                INITIALIZE: begin
                  x0 <= x0 ^ {inPlaintext, 32'h00000000};  // XOR plaintext with state
                  process_state <= STATE_1;
                end
                STATE_1: begin
                  x0_cihper <= x0[63:32];
                  x0 <= x0 ^ 64'h0000000080000000;  // Apply padding
                  process_state <= STATE_DONE;
                end
                STATE_DONE: begin
                  process_done <= 1'b1;  // Data processing done for decryption
                end
                default: begin
                  process_state <= INITIALIZE;
                end
              endcase
            end

            if (enc_dec_current_state == DECRYPTION) begin
              case (process_state)
                INITIALIZE: begin
                  x0 <= x0 ^ {inCiphertext[159:128], 32'h00000000};  // XOR ciphertext with state
                  process_state <= STATE_1;
                end
                STATE_1: begin
                  outDecrypted <= x0[63:32];
                  x0 <= {inCiphertext[159:128], x0[31:0]};
                  process_state <= STATE_2;
                end
                STATE_2: begin
                  x0 <= x0 ^ 64'h0000000080000000;  // Apply padding
                  process_state <= STATE_DONE;
                end
                STATE_DONE: begin
                  process_done <= 1'b1;  // Data processing done for decryption
                end
                default: begin
                  process_state <= INITIALIZE;
                end
              endcase
            end
          end
          FINALIZATION: begin

            if (permutation_counter == 0) begin
              x1 <= x1 ^ key[127:64];
              x2 <= x2 ^ key[63:0];
            end

            if (start_permutation == 0 && permutation_counter == 0) begin
              start_permutation   <= 1;
              permutation_counter <= 1;
            end else start_permutation <= 0;

            if (permutation_done == 1) begin
              x0 <= x0_next;
              x1 <= x1_next;
              x2 <= x2_next;
              x3 <= x3_next;
              x4 <= x4_next;
              finalization_permutation <= 1;
            end

            if (finalization_permutation == 1) begin
              x3 <= x3 ^ key[127:64];
              x4 <= x4 ^ key[63:0];
              finalization_permutation <= 0;
              finalization_xor_key <= 1;
            end

            if (finalization_xor_key == 1) final_done <= 1'b1;
          end
          TAG_GENERATION: begin
            if (enc_dec_current_state == ENCRYPTION) begin
              if (tag_generation_big_end == 0) begin
                enc_tag_value <= {x3, x4};
                tag_generation_big_end <= 1;
              end

              if (tag_generation_big_end == 1) begin
                // enc_tag_value <= 1'b0;
                tag_done <= 1'b1;
              end

            end else if (enc_dec_current_state == DECRYPTION) begin
              case (process_state_2)
                INITIALIZE: begin
                  process_state_2 <= STATE_1;
                end
                STATE_1: begin
                  decryptionFaild <= !({x3, x4} == in_tag);
                  authentication_done <= 1;
                  process_state_2 <= STATE_DONE;
                  outDecrypted <= 0;
                end
                STATE_DONE: begin
                  process_state_2 <= INITIALIZE;
                  tag_done <= 1'b1;
                end
              endcase

            end
          end

          default: begin
            init_done <= 1'b0;
            domain_sep_done <= 1'b0;
            process_done <= 1'b0;
            final_done <= 1'b0;
            tag_done <= 1'b0;
            start_permutation <= 1'b0;
            permutation_counter <= 1'b0;
            init_xor <= 1'b0;
            init_key_xor <= 1'b0;
            domain_separation_xor <= 1'b0;
            finalization_xor_key <= 1'b0;
            finalization_permutation <= 1'b0;
            tag_generation_big_end <= 1'b0;
            process_state <= INITIALIZE;
          end
        endcase
        end   
end


// Output logic
always_comb begin
  if (rst == 1) begin
    outCiphertext = 1'b0;
  end else if (enc_current_state == FINALIZATION && final_done && enc_dec_current_state == ENCRYPTION) begin
    outCiphertext = {x0_cihper};
  end 
  // else if (enc_current_state == IDLE) outCiphertext = 160'b0;
end

assign decrypting = ((enc_dec_current_state == DECRYPTION) && (process_done == 0)) ? 1 : 0;
assign encrypting = enc_dec_current_state == ENCRYPTION ? 1 : 0;

endmodule

