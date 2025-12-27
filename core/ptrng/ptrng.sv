module ptrng_top
    (
        input  logic       clk,
        input  logic       rst_n,
        input  logic       enable,
        input  logic       update,
        output logic       valid,
        output logic [127:0] data
    );
    
    logic [1:0]        state;
    logic [7:0]        counter;
    
    localparam S_IDLE  = 2'd0;
    localparam S_WAIT1 = 2'd1;
    localparam S_WAIT2 = 2'd2;
    localparam S_READY = 2'd3;
    
    // Counter logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter <= '0;
        end else if (enable && (state == S_WAIT2)) begin
            counter <= counter + 1;
        end
    end
    
    assign data = {16{counter}};
    
    // FSM
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            valid <= 1'b0;
        end else if (enable) begin
            case (state)
                S_IDLE: begin
                    if (update) begin
                        state <= S_WAIT1;
                        valid <= 1'b0;
                    end
                end
                
                S_WAIT1: begin
                    state <= S_WAIT2;
                end
                
                S_WAIT2: begin
                    state <= S_READY;
                    valid <= 1'b1;
                end
                
                S_READY: begin
                    if (update) begin
                        state <= S_WAIT1;
                        valid <= 1'b0;
                    end
                end
            endcase
        end
    end
    
endmodule