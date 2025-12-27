module ascon_top (
  input logic clk,
  input logic rst,
  input logic asc_en,
  input logic enc_start,  
  input logic dec_start,  

  input logic [127:0] key,     
  input logic [127:0] nonce, 
   
  input logic [31:0] inPlaintext,  
  input logic [159:0] inCiphertext,  

  output logic [127:0] enc_tag_value,
  output logic [31:0] enc_dec_message,    

  output logic decryptionFaild,
  output logic authentication_done,
  output logic decrypting,
  output logic encrypting,
  output logic store_buffer_ready
 );

  logic [3:0] round_cnt;
  logic start_permutation;  
  logic init_xor, init_key_xor;  
  logic domain_separation_xor;  
  logic finalization_xor_key, finalization_permutation;  

  // State machine states for ASCON operation
  typedef enum logic [2:0] {
    IDLE,
    INITIALIZATION,
    DOMAIN_SEPARATION,
    PROCESS_DATA,
    FINALIZATION
  } ascon_state_t;

  typedef enum logic [2:0] {
    STATE_IDLE,
    STATE_0,
    STATE_1,
    STATE_2,
    STATE_DONE
  } state_t;

  state_t processing_stage;
logic [1:0] decryption_states;

  // State machine states for encryption/decryption mode
  typedef enum logic [2:0] {
    ENCRYPTION,
    DECRYPTION,
    HALT
  } enc_dec_state_t;

  ascon_state_t ascon_current_state, ascon_next_state;
  enc_dec_state_t enc_dec_current_state, enc_dec_current_next_state;

  logic [63:0] x0, x1, x2, x3, x4;  
  logic [63:0] x0_next, x1_next, x2_next, x3_next, x4_next;

  logic init_done, domain_sep_done , final_done, encryption_done, process_done;

  logic [7:0] round_constant;

  ascon_permutation ascon_per (
      .state_in({x0, x1, x2, x3, x4}),  
      .round_constant(round_constant),
      .state_out({x0_next, x1_next, x2_next, x3_next, x4_next})  
  );



  // Clock gating enables for state registers
logic x0_clk_en, x1_clk_en, x2_clk_en, x3_clk_en, x4_clk_en;
  logic control_regs_clk_en;

  logic load_init_en;
  logic domain_sep_en;
  logic process_state0_en;
  logic process_state1_en;
  logic process_state2_en;
  logic final_pre_xor_en;
  logic final_post_xor_en;
  logic perm_en;

  always_comb begin
    load_init_en      = (ascon_current_state == INITIALIZATION && init_xor == 0 && start_permutation == 0);
    domain_sep_en     = (ascon_current_state == DOMAIN_SEPARATION);
    process_state0_en = (ascon_current_state == PROCESS_DATA && processing_stage == STATE_0);
    process_state1_en = (ascon_current_state == PROCESS_DATA && processing_stage == STATE_1);
    process_state2_en = (ascon_current_state == PROCESS_DATA && processing_stage == STATE_2);
    final_pre_xor_en  = (ascon_current_state == FINALIZATION && finalization_xor_key == 0 && start_permutation == 0 && finalization_permutation == 0);
    final_post_xor_en = (ascon_current_state == FINALIZATION && finalization_permutation == 1);
    perm_en = start_permutation;

// x0 clock enable
  x0_clk_en = asc_en && (
    load_init_en ||
    process_state0_en ||
    process_state1_en ||
    process_state2_en ||
    perm_en
  );
  
  // x1 clock enable
  x1_clk_en = asc_en && (
    load_init_en ||
    final_pre_xor_en ||
    perm_en
  );
  
  // x2 clock enable
  x2_clk_en = asc_en && (
    load_init_en ||
    final_pre_xor_en ||
    perm_en
  );
  
  // x3 clock enable
  x3_clk_en = asc_en && (
    load_init_en ||
    (ascon_current_state == INITIALIZATION && init_xor) ||
    final_post_xor_en ||
    perm_en
  );
  
  // x4 clock enable
  x4_clk_en = asc_en && (
    load_init_en ||
    (ascon_current_state == INITIALIZATION && init_xor) ||
    domain_sep_en ||
    final_post_xor_en ||
    perm_en
  );
  
  // Control registers clock enable
    control_regs_clk_en = asc_en || rst;
  end

   
 always_ff @(posedge clk) begin
  if(asc_en) begin
    if(decryption_states == 1)   authentication_done <= 1;
  end else  authentication_done <=0;
end

  // Main state machine for ASCON operation
  always_ff @(posedge clk) begin
    if (rst) begin
      ascon_current_state <= IDLE;
      enc_dec_current_state = HALT;
    end else if (control_regs_clk_en) begin
      ascon_current_state <= ascon_next_state;
      enc_dec_current_state = enc_dec_current_next_state;
    end
  end

  always_comb begin
      ascon_next_state = ascon_current_state;
      enc_dec_current_next_state = enc_dec_current_state;

      case (ascon_current_state)
        IDLE: begin
          if (enc_start) begin
            ascon_next_state = INITIALIZATION;
            enc_dec_current_next_state = ENCRYPTION;
          end else if (dec_start) begin
            ascon_next_state = INITIALIZATION;
            enc_dec_current_next_state = DECRYPTION;
          end
        end

        INITIALIZATION: begin
          if (init_done)
            ascon_next_state = DOMAIN_SEPARATION;
        end

        DOMAIN_SEPARATION: begin
          if (domain_sep_done)
            ascon_next_state = PROCESS_DATA;
        end

        PROCESS_DATA: begin
          if (process_done)
            ascon_next_state = FINALIZATION;
        end

        FINALIZATION: begin
        if (encryption_done || authentication_done) begin
                  ascon_next_state = IDLE;
                  enc_dec_current_next_state = HALT;
        end
        end

        default: ascon_next_state = IDLE;
      endcase
  end

  // Encryption FSM with clock gating
  always_ff @(posedge clk) begin
    if (rst) begin
      init_done           <= 1'b0;
      enc_tag_value       <= 'b0;
      domain_sep_done     <= 1'b0;
      process_done        <= 1'b0;
      store_buffer_ready  <= 1'b0;
      final_done          <= 1'b0;

      enc_dec_message    <= 32'b0;
      x0              <= 64'h0;
      x1              <= 64'h0;
      x2              <= 64'h0;
      x3              <= 64'h0;
      x4              <= 64'h0;
      decryptionFaild <= 1'b0;

    decryption_states <= 0;

      start_permutation <= 1'b0;
      round_cnt <= 4'b0;
      init_xor <= 1'b0;
      init_key_xor <= 1'b0;
      domain_separation_xor <= 1'b0;
      finalization_xor_key <= 1'b0;
      finalization_permutation <= 1'b0;
      processing_stage <= STATE_0;
      end else if(asc_en == 1) begin
      init_done <= 1'b0;
      domain_sep_done <= 1'b0;
      final_done <= 1'b0;
      store_buffer_ready <= 'b0;
      encryption_done <= 'b0;
     
          
      case (ascon_current_state)
        INITIALIZATION: begin
          processing_stage <= STATE_0;
          if (load_init_en) begin
             if (x0_clk_en) x0 <= 64'h80400c0600000000;
             if (x1_clk_en) x1 <= key[127:64];
             if (x2_clk_en) x2 <= key[63:0];
             if (x3_clk_en) x3 <= nonce[127:64];
             if (x4_clk_en) x4 <= nonce[63:0];
            start_permutation   <= 1;
            round_cnt <= 0;
          end

          if (start_permutation) begin
             if (x0_clk_en) x0 <= x0_next;
             if (x1_clk_en) x1 <= x1_next;
             if (x2_clk_en) x2 <= x2_next;
             if (x3_clk_en) x3 <= x3_next;
             if (x4_clk_en) x4 <= x4_next;
            round_cnt <= round_cnt + 1;
            if (round_cnt == 11) begin
              start_permutation   <= 0;
              init_xor <= 1;
            end
                    end
          
          if (init_xor == 1'b1) begin
             if (x3_clk_en) x3 <= x3 ^ key[127:64];
             if (x4_clk_en) x4 <= x4 ^ key[63:0];
            init_key_xor <= 1'b1;
          end

          if (init_key_xor == 1'b1) init_done <= 1'b1;  // Initialization done
        end

        DOMAIN_SEPARATION: begin
          init_xor <= 1'b0;
          init_key_xor <= 1'b0;
          if (domain_sep_en && domain_separation_xor == 0) begin
             if (x4_clk_en) x4 <= x4 ^ 64'h1;  // Apply domain separation constant
            domain_separation_xor <= 1;
          end

          if (domain_separation_xor == 1) domain_sep_done <= 1'b1;  // Domain separation done
        end

        PROCESS_DATA: begin
          case (enc_dec_current_state)
            ENCRYPTION: begin
              case (processing_stage)
                STATE_IDLE: begin
                  // No operation here
                end
                STATE_0: begin
                   if (x0_clk_en) x0 <= x0 ^ {inPlaintext, 32'h00000000};  // XOR plaintext with state
                  processing_stage <= STATE_1;
                end
                STATE_1: begin
                  enc_dec_message <= x0[63:32];
                   if (x0_clk_en) x0 <= x0 ^ 64'h0000000080000000;  // Apply padding
                  processing_stage <= STATE_DONE;
                end
                STATE_DONE: begin
                  process_done <= 1'b1;  // Data processing done for decryption
                  processing_stage <= STATE_IDLE;
                end
                default: begin
                  processing_stage <= STATE_0;
                end
              endcase
            end
            DECRYPTION: begin
              case (processing_stage)
                STATE_IDLE: begin
                  process_done <= 1'b0;  // Data processing done for decryption
                end
                STATE_0: begin
                   if (x0_clk_en) x0 <= x0 ^ {inCiphertext[159:128], 32'h00000000};  // XOR ciphertext with state
                  processing_stage <= STATE_1;
                end
                STATE_1: begin
                  enc_dec_message <= x0[63:32];
                   if (x0_clk_en) x0 <= {inCiphertext[159:128], x0[31:0]};
                  processing_stage <= STATE_2;
                end
                STATE_2: begin
                   if (x0_clk_en) x0 <= x0 ^ 64'h0000000080000000;  // Apply padding
                  processing_stage <= STATE_DONE;
                end
                STATE_DONE: begin
                  process_done <= 1'b1;  // Data processing done for decryption
                  processing_stage <= STATE_IDLE;
                end
                default: begin
                  processing_stage <= STATE_0;
                end
              endcase
            end
            default:;
          endcase
        end

        FINALIZATION: begin
          process_done <= 1'b0;

          if (final_pre_xor_en) begin
             if (x1_clk_en) x1 <= x1 ^ key[127:64];
             if (x2_clk_en) x2 <= x2 ^ key[63:0];
            start_permutation   <= 1;
            round_cnt <= 0;
          end

          if (start_permutation) begin
             if (x0_clk_en) x0 <= x0_next;
             if (x1_clk_en) x1 <= x1_next;
             if (x2_clk_en) x2 <= x2_next;
             if (x3_clk_en) x3 <= x3_next;
             if (x4_clk_en) x4 <= x4_next;
            round_cnt <= round_cnt + 1;
            if (round_cnt == 11) begin
              start_permutation <= 0;
              finalization_permutation <= 1;
            end
          end

          if (finalization_permutation == 1) begin
             if (x3_clk_en) x3 <= x3 ^ key[127:64];
             if (x4_clk_en) x4 <= x4 ^ key[63:0];
            finalization_permutation <= 0;
            finalization_xor_key <= 1;
          end

          if (finalization_xor_key == 1) begin
            final_done <= 1'b1;
          end

          if(final_done) begin
            if (enc_dec_current_state == ENCRYPTION) begin
                enc_tag_value <= {x3, x4};
                encryption_done <= 1'b1;
                store_buffer_ready    <= 1'b1;
            end else if (enc_dec_current_state == DECRYPTION) begin
                if(decryption_states == 0) decryption_states <= 1;
            else begin
              decryptionFaild <= !({x3, x4} == {inCiphertext[63:0], inCiphertext[127:64]});
              enc_dec_message <= 0;
              decryption_states <= 0;
            end
            end
          end
        end

        default: begin
          
          process_done <= 1'b0;
          encryption_done <= 1'b0;
          start_permutation <= 1'b0;
          round_cnt <= 4'b0;
          init_xor <= 1'b0;
          init_key_xor <= 1'b0;
          domain_separation_xor <= 1'b0;
          finalization_xor_key <= 1'b0;
          finalization_permutation <= 1'b0;
          processing_stage <= STATE_0;
      
        end
      endcase
    end
  end

  assign decrypting = (enc_dec_current_state == DECRYPTION && processing_stage == (STATE_0 || STATE_1 || STATE_2)) ? 1 : 0;
  assign encrypting = enc_dec_current_state == ENCRYPTION ? 1 : 0;
  assign round_constant = 8'hf0 - (8'h0f * round_cnt);

endmodule
