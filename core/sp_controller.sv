module sp_controller #(
    parameter type ascon_outputs_t = logic,
    parameter config_pkg::cva6_cfg_t CVA6Cfg = config_pkg::cva6_cfg_empty
) (
    input logic clk_i,  // Clock
    input logic rst_ni,  // Synchronous reset
    input logic is_scl,  // Synchronous reset
    input ascon_outputs_t ascon_outputs,
    input logic [31:0] instr_i,  // Instruction word
    input logic issue_ack_i,  // Acknowledge signal from issue stage
    input logic chunks_loaded,  // Acknowledge signal from issue stage
    output logic illegal_instr_o,  // Illegal instruction flag  || Remove if not used
    output logic fetch_stall_o,  // Stall the front end during lenc processing
    output logic [11:0] offset_q,
    output logic decryption_done,
    output logic [31:0] decrypted_value,
    output config_pkg::exception_t exception_o,  // Unified exception output as a struct
    output logic sp_scs_en,
    output logic encrpt_en,
    output logic [3:0] load_counter,
    output logic decrpt_en

);

  // ************************************************* LENC START ************************************************* //

  //LENC FSM States
  enum logic [2:0] {
    SCL_IDLE,
    SCL_WAIT_ASCON,
    SCL_LOAD_CHUNKS,
    SCL_DECRYPTION,
    SCL_UNSTALLING
  }
      scl_state_d, scl_state_q;

  // Temporary Registers
  // logic [4:0] rd_reg, rs1_reg;     // Destination and base address registers
  logic [31:0] decrypted_value_temp;  // Decrypted plaintext value
  logic [3:0] load_counter_d;         // Counter for tracking loaded instructions
  logic [11:0] scs_offset_q, scs_offset_d, scl_offset_q, scl_offset_d;
  logic decryption_done_temp;  // Signal to indicate decryption done
  logic scl_fetch_stall_o;  // Signal to indicate decryption done

  // Combinational Logic
  always_comb begin
    // Default assignments
    illegal_instr_o = 1'b0;
    scl_fetch_stall_o = 1'b0;
    load_counter_d = load_counter;
    decryption_done_temp = '0;
    scl_offset_d = scl_offset_q;
    scl_state_d = scl_state_q;
    decrpt_en = 0;
    decrypted_value_temp = 1'b0;

    unique case (scl_state_q)
      SCL_IDLE: begin
        if (is_scl) begin
          // Extract rd, rs1, and offset from the instruction
          // rd = instr_i[11:7]; || rsfoffset_q1 = instr_i[19:15];
          scl_offset_d = instr_i[31:20];  // Sign-extend offset
          scl_fetch_stall_o = 1'b1;  // Stall front end
          
          if (issue_ack_i) begin
            if (!ascon_outputs.asc_en) scl_state_d = SCL_LOAD_CHUNKS;
            else scl_state_d = SCL_WAIT_ASCON;
          decrypted_value_temp = 1'b0;
          end
        end
      end
      SCL_WAIT_ASCON: begin
        scl_fetch_stall_o = 1'b1;  // Stall front end
        if (!ascon_outputs.asc_en) begin 
           if (issue_ack_i) scl_state_d = SCL_LOAD_CHUNKS;
        end
      end
      SCL_LOAD_CHUNKS: begin
        scl_fetch_stall_o = 1'b1;  // Continue stalling
        if (issue_ack_i) begin
          if (load_counter < 5) begin

            // Increment load counter and offset
            load_counter_d = load_counter + 1;
            scl_offset_d   = scl_offset_d + 12'h8;  // Increment offset by 4 bytes

          end else begin
            // All 9 chunks are loaded
            if (chunks_loaded) begin
              decrpt_en = chunks_loaded;
            end
            if (ascon_outputs.decrypting) begin
              scl_state_d  = SCL_DECRYPTION;
              scl_offset_d = 0;
            end
          end
        end
      end
      SCL_DECRYPTION: begin
        load_counter_d = 4'd0;  // Reset load counter
        scl_fetch_stall_o = 1'b1;  // Continue stalling
        if (!ascon_outputs.decrypting) begin  // Assuming decryption_done_temp signal from encryption unit
          decrypted_value_temp = !ascon_outputs.decryptionFaild? ascon_outputs.enc_dec_message: '0;  // Store decrypted value
          scl_state_d = SCL_UNSTALLING;
          decryption_done_temp = 1'b1;
        end
      end
      SCL_UNSTALLING: begin
        decryption_done_temp = 1'b1;
        decrypted_value_temp = ascon_outputs.enc_dec_message;
        scl_fetch_stall_o = 1'b0;
        if (issue_ack_i && !ascon_outputs.decrypting) begin  // Assuming decryption_done_temp signal from encryption unit
            scl_state_d = SCL_IDLE; 
        end
      end

      default: begin
        scl_state_d = SCL_IDLE;
      end
    endcase
  end

  assign exception_o.decryption_failure_exception = ascon_outputs.decryptionFaild? 1'b1: 0;

  // Sequential Logic
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      scl_state_q <= SCL_IDLE;
      load_counter <= 4'd0;
      scl_offset_q <= 12'h0;
      scs_offset_q <= 12'h0;
    end else begin
      scl_state_q <= scl_state_d;
      load_counter <= load_counter_d;
      scl_offset_q <= scl_offset_d;
      scs_offset_q <= scs_offset_d;
    end
  end

  assign decrypted_value = decrypted_value_temp;
  assign decryption_done = decryption_done_temp;


  // Helper Function to Detect lenc Instruction
  function automatic logic is_scl_instr(input logic [31:0] instr);
    return (instr[6:0] == riscv::OpcodeLoadChunk && instr[14:12] == 3'b111); // Opcode and funct3 for lenc
  endfunction

  // ************************************************* LENC END ************************************************* //

  // ************************************************* SENC START ************************************************* //


  // Counter for delay in SCS_WAIT_ASCON state
  logic [2:0] store_delay;



  //SENC FSM States
  enum logic [2:0] {
    SCS_IDLE,
    SCS_WAIT_ASCON,
    SCS_FETCH_STALL,
    SCS_GENERATE_CHUNKS,
    SCS_STORE_PREP,
    SCS_UNSTALLING
  }
      scs_state_d, scs_state_q;

  // Temporary Registers
  // logic [4:0] rd_reg, rs1_reg;                      // Destination and base address registers
  logic scs_fetch_stall_o;

  // Store delay counter always block
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      store_delay <= 3'b0;
    end else begin
      // Reset counter when not in SCS_WAIT_ASCON state
      if (scs_state_q != SCS_WAIT_ASCON) begin
        store_delay <= 3'b0;
      end 
      // Increment counter while in SCS_WAIT_ASCON and asc_en is still high
      else if (scs_state_q == SCS_WAIT_ASCON && !ascon_outputs.asc_en) begin
        if (store_delay < 3'd4) begin
          store_delay <= store_delay + 1;
        end
      end
    end
  end

  // Combinational Logic
  always_comb begin
    // Default assignments
    scs_fetch_stall_o = 1'b0;
    scs_state_d = scs_state_q;
    encrpt_en = 1'b0;
    sp_scs_en = 1'b0;
    scs_offset_d = scs_offset_q;

    unique case (scs_state_q)
      SCS_IDLE: begin
        scs_offset_d = 0;
        if (is_scs_instr(instr_i)) begin 
            scs_offset_d = {instr_i[31:25], instr_i[11:7]};
            if (scl_state_d == SCL_IDLE) begin
              scs_fetch_stall_o = 1'b1;  
              if (!ascon_outputs.asc_en) scs_state_d = SCS_FETCH_STALL;
              else                           scs_state_d = SCS_WAIT_ASCON;
            end
            else scs_state_d = SCS_UNSTALLING;
        end
      end
      SCS_WAIT_ASCON: begin
        scs_fetch_stall_o = 1'b1;  // Continue stalling
        if (!ascon_outputs.asc_en && store_delay >= 4) begin
          scs_state_d = SCS_GENERATE_CHUNKS;
          encrpt_en   = 1'b1;
        end
      end
      SCS_FETCH_STALL: begin
        scs_fetch_stall_o = 1'b1;  // Continue stalling
        if (issue_ack_i) begin
          scs_state_d = SCS_GENERATE_CHUNKS;
          encrpt_en   = 1'b1;
        end
      end
      SCS_GENERATE_CHUNKS: begin
        scs_fetch_stall_o = 1'b1;  // Continue stalling
        encrpt_en = 1'b1 & !ascon_outputs.encrypting;
        if (ascon_outputs.encrypting) begin  // Assuming decryption_done_temp signal from encryption unit
          encrpt_en   = 1'b0;
          scs_state_d = SCS_STORE_PREP;
        end
      end
      SCS_STORE_PREP: begin
        scs_fetch_stall_o = 1'b1;  // Continue stalling
        sp_scs_en = 1'b1;
        scs_state_d  = SCS_UNSTALLING;
      end

      SCS_UNSTALLING: begin
        sp_scs_en = 1'b1;
        scs_fetch_stall_o = 1'b0;
        if (issue_ack_i) begin
          scs_state_d = SCS_IDLE;
        end
      end

      default: begin
        scs_state_d = SCS_IDLE;
      end
    endcase
  end

  // Sequential Logic
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      scs_state_q <= SCS_IDLE;
    end else begin
      scs_state_q <= scs_state_d;
    end
  end


  // Helper Function to Detect senc Instruction
  function automatic logic is_scs_instr(input logic [31:0] instr);
    return (instr[6:0] == riscv::OpcodeStoreChunk && instr[14:12] == 3'b111); // Opcode and funct3 for senc
  endfunction

  // ************************************************* SENC END ************************************************* //

  // ***********
  assign fetch_stall_o = scl_fetch_stall_o | scs_fetch_stall_o;
  assign offset_q = scl_offset_d | scs_offset_d;

  /* Secrue Registers Tracing*/

  logic secure_registers[32];

  riscv::instruction_t instr;
  assign instr = riscv::instruction_t'(instr_i);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      // Reset secure_registers to all zeros on reset
      secure_registers <= '{default: 0};
      exception_o.normal_store_secure_variable <= 0;
    end else begin
      // Default behavior: No changes to secure_registers
      secure_registers <= secure_registers;

      // Decode the instruction and update secure_registers accordingly
      case (instr[6:0])
        // Load Instructions (e.g., lb, lh, lw, ld, lenc)
        riscv::OpcodeLoad: begin
          if (is_scl) begin
            // LENC instruction: Mark destination register as secure
            secure_registers[instr[11:7]] <= 1;
          end else begin
            // Normal load instruction: Mark destination register as non-secure
            secure_registers[instr[11:7]] <= 0;
          end
        end

        // Store Instructions - Handle SENC instruction
        riscv::OpcodeStore: begin
          if (instr[14:12] != 3'b111 && secure_registers[instr[24:20]] == 1) begin
            // Normal Store instruction: Store secure data and reset register
            exception_o.normal_store_secure_variable <= 1;

          end else if (instr[14:12] == 3'b111 && secure_registers[instr[24:20]] == 0 && ~ascon_outputs.encrypting) begin
            // SENC instruction: Store secure data and reset register
            secure_registers[instr[24:20]] <= 1;
          end
        end

        // Immediate Instructions (e.g., li, addi, etc.)
        riscv::OpcodeOpImm: begin
          // Check if the source register is secure
          if (secure_registers[instr[19:15]]) begin
            // Propagate secure status to the destination register
            secure_registers[instr[11:7]] <= 1;
          end else begin
            // Destination register is non-secure
            secure_registers[instr[11:7]] <= 0;
          end
        end

        // Arithmetic/Logical Instructions (e.g., add, sub, div, rem, etc.)
        riscv::OpcodeOp: begin
          // Check if either source register is secure
          if (secure_registers[instr[19:15]] || secure_registers[instr[24:20]]) begin
            // Propagate secure status to the destination register
            secure_registers[instr[11:7]] <= 1;
          end else begin
            // Destination register is non-secure
            secure_registers[instr[11:7]] <= 0;
          end
        end

        // Default Case: Unsupported or invalid instructions
        default: begin
          // No changes to secure_registers
        end
      endcase
    end
  end


  


endmodule

