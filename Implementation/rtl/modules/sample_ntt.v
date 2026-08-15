`timescale 1ns / 1ps
`include "mlkem_sampler_defs.vh"

module sample_ntt (
    input wire clk,
    input wire rst_n,

    // Input byte stream
    input wire byte_valid,
    input wire [7:0] byte_in,
    output wire byte_ready,

    // Output coefficient stream
    input wire coeff_ready,
    output wire coeff_valid,
    output wire [`MLKEM_COEFF_WIDTH-1:0] coeff_out,
    output wire coeff_last,

    // Global control
    input wire start,
    output wire busy,
    output wire done
);

    localparam [7:0] ST_IDLE  = 8'b00000001;
    localparam [7:0] ST_BYTE0 = 8'b00000010;
    localparam [7:0] ST_BYTE1 = 8'b00000100;
    localparam [7:0] ST_BYTE2 = 8'b00001000;
    localparam [7:0] ST_EVAL  = 8'b00010000;
    localparam [7:0] ST_OUT1  = 8'b00100000;
    localparam [7:0] ST_OUT2  = 8'b01000000;
    localparam [7:0] ST_DONE  = 8'b10000000;

    reg [7:0] curr_state, next_state;
    reg [7:0] byte0_r, byte1_r;
    reg [`MLKEM_COEFF_WIDTH-1:0] d1_r, d2_r;
    reg [8:0] coeff_count;

    wire d1_valid;
    wire d2_valid;
    wire coeff_accept;

    always @(*) begin
        next_state = curr_state;

        case (curr_state)
            ST_IDLE: if (start) next_state = ST_BYTE0;
            ST_BYTE0: if (byte_valid) next_state = ST_BYTE1;
            ST_BYTE1: if (byte_valid) next_state = ST_BYTE2;
            ST_BYTE2: if (byte_valid) next_state = ST_EVAL;
            ST_EVAL: begin
                if (d1_valid)
                    next_state = ST_OUT1;
                else if (d2_valid)
                    next_state = ST_OUT2;
                else
                    next_state = ST_BYTE0;
            end
            ST_OUT1: begin
                if (coeff_ready) begin
                    if (coeff_count == (`MLKEM_COEFF_COUNT - 1))
                        next_state = ST_DONE;
                    else if (d2_valid)
                        next_state = ST_OUT2;
                    else
                        next_state = ST_BYTE0;
                end
            end
            ST_OUT2: begin
                if (coeff_ready) begin
                    if (coeff_count == (`MLKEM_COEFF_COUNT - 1))
                        next_state = ST_DONE;
                    else
                        next_state = ST_BYTE0;
                end
            end
            ST_DONE: next_state = ST_IDLE;
            default: next_state = ST_IDLE;
        endcase
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            curr_state <= ST_IDLE;
            byte0_r <= 8'd0;
            byte1_r <= 8'd0;
            d1_r <= {`MLKEM_COEFF_WIDTH{1'b0}};
            d2_r <= {`MLKEM_COEFF_WIDTH{1'b0}};
            coeff_count <= 9'd0;
        end else begin
            curr_state <= next_state;

            case (curr_state)
                ST_IDLE: begin
                    if (start) begin
                        byte0_r <= 8'd0;
                        byte1_r <= 8'd0;
                        d1_r <= {`MLKEM_COEFF_WIDTH{1'b0}};
                        d2_r <= {`MLKEM_COEFF_WIDTH{1'b0}};
                        coeff_count <= 9'd0;
                    end
                end
                ST_BYTE0: begin
                    if (byte_valid)
                        byte0_r <= byte_in;
                end
                ST_BYTE1: begin
                    if (byte_valid)
                        byte1_r <= byte_in;
                end
                ST_BYTE2: begin
                    if (byte_valid) begin
                        d1_r <= {byte1_r[3:0], byte0_r};
                        d2_r <= {byte_in, byte1_r[7:4]};
                    end
                end
                ST_OUT1,
                ST_OUT2: begin
                    if (coeff_accept)
                        coeff_count <= coeff_count + 1'b1;
                end
            endcase
        end
    end

    assign d1_valid = (d1_r < `MLKEM_Q);
    assign d2_valid = (d2_r < `MLKEM_Q);
    assign byte_ready = (curr_state == ST_BYTE0) ||
                        (curr_state == ST_BYTE1) ||
                        (curr_state == ST_BYTE2);
    assign coeff_valid = (curr_state == ST_OUT1) ||
                         (curr_state == ST_OUT2);
    assign coeff_out = (curr_state == ST_OUT2) ? d2_r : d1_r;
    assign coeff_last = coeff_valid &&
                        (coeff_count == (`MLKEM_COEFF_COUNT - 1));
    assign coeff_accept = coeff_valid && coeff_ready;
    assign busy = (curr_state != ST_IDLE);
    assign done = (curr_state == ST_DONE);

endmodule
