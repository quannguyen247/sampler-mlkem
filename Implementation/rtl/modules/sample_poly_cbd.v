`timescale 1ns / 1ps
`include "mlkem_sampler_defs.vh"

module sample_poly_cbd (
    input wire clk,
    input wire rst_n,

    // Sampling parameter
    input wire [1:0] eta,

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

    localparam [3:0] ST_IDLE = 4'b0001;
    localparam [3:0] ST_LOAD = 4'b0010;
    localparam [3:0] ST_EMIT = 4'b0100;
    localparam [3:0] ST_DONE = 4'b1000;

    reg [3:0] curr_state, next_state;
    reg [1:0] eta_r;
    reg [23:0] byte_group_r;
    reg [1:0] byte_count;
    reg [1:0] group_coeff_idx;
    reg [8:0] coeff_count;

    reg [5:0] cbd_bits;
    reg [2:0] count_a, count_b;
    reg [`MLKEM_COEFF_WIDTH-1:0] coeff_data;

    wire group_last;
    wire coeff_accept;

    always @(*) begin
        next_state = curr_state;

        case (curr_state)
            ST_IDLE: if (start) next_state = ST_LOAD;
            ST_LOAD: begin
                if (byte_valid) begin
                    if ((eta_r == 2'd2) || (byte_count == 2'd2))
                        next_state = ST_EMIT;
                end
            end
            ST_EMIT: begin
                if (coeff_ready) begin
                    if (coeff_count == (`MLKEM_COEFF_COUNT - 1))
                        next_state = ST_DONE;
                    else if (group_last)
                        next_state = ST_LOAD;
                end
            end
            ST_DONE: next_state = ST_IDLE;
            default: next_state = ST_IDLE;
        endcase
    end

    always @(*) begin
        cbd_bits = 6'd0;

        if (eta_r == 2'd3) begin
            case (group_coeff_idx)
                2'd0: cbd_bits = byte_group_r[5:0];
                2'd1: cbd_bits = byte_group_r[11:6];
                2'd2: cbd_bits = byte_group_r[17:12];
                default: cbd_bits = byte_group_r[23:18];
            endcase
        end else begin
            case (group_coeff_idx)
                2'd0: cbd_bits[3:0] = byte_group_r[3:0];
                default: cbd_bits[3:0] = byte_group_r[7:4];
            endcase
        end

        count_a = {2'd0, cbd_bits[0]} +
                  {2'd0, cbd_bits[1]} +
                  ((eta_r == 2'd3) ? {2'd0, cbd_bits[2]} : 3'd0);
        count_b = {2'd0, cbd_bits[(eta_r == 2'd3) ? 3 : 2]} +
                  {2'd0, cbd_bits[(eta_r == 2'd3) ? 4 : 3]} +
                  ((eta_r == 2'd3) ? {2'd0, cbd_bits[5]} : 3'd0);

        if (count_a >= count_b)
            coeff_data = count_a - count_b;
        else
            coeff_data = `MLKEM_Q - (count_b - count_a);
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            curr_state <= ST_IDLE;
            eta_r <= 2'd2;
            byte_group_r <= 24'd0;
            byte_count <= 2'd0;
            group_coeff_idx <= 2'd0;
            coeff_count <= 9'd0;
        end else begin
            curr_state <= next_state;

            case (curr_state)
                ST_IDLE: begin
                    if (start) begin
                        eta_r <= (eta == 2'd3) ? 2'd3 : 2'd2;
                        byte_group_r <= 24'd0;
                        byte_count <= 2'd0;
                        group_coeff_idx <= 2'd0;
                        coeff_count <= 9'd0;
                    end
                end
                ST_LOAD: begin
                    if (byte_valid) begin
                        if (eta_r == 2'd3) begin
                            case (byte_count)
                                2'd0: begin
                                    byte_group_r[7:0] <= byte_in;
                                    byte_count <= 2'd1;
                                end
                                2'd1: begin
                                    byte_group_r[15:8] <= byte_in;
                                    byte_count <= 2'd2;
                                end
                                default: begin
                                    byte_group_r[23:16] <= byte_in;
                                    byte_count <= 2'd0;
                                    group_coeff_idx <= 2'd0;
                                end
                            endcase
                        end else begin
                            byte_group_r[7:0] <= byte_in;
                            byte_count <= 2'd0;
                            group_coeff_idx <= 2'd0;
                        end
                    end
                end
                ST_EMIT: begin
                    if (coeff_accept) begin
                        coeff_count <= coeff_count + 1'b1;
                        if (group_last)
                            group_coeff_idx <= 2'd0;
                        else
                            group_coeff_idx <= group_coeff_idx + 1'b1;
                    end
                end
            endcase
        end
    end

    assign group_last = (eta_r == 2'd3) ?
                        (group_coeff_idx == 2'd3) :
                        (group_coeff_idx == 2'd1);
    assign byte_ready = (curr_state == ST_LOAD);
    assign coeff_valid = (curr_state == ST_EMIT);
    assign coeff_out = coeff_data;
    assign coeff_last = coeff_valid &&
                        (coeff_count == (`MLKEM_COEFF_COUNT - 1));
    assign coeff_accept = coeff_valid && coeff_ready;
    assign busy = (curr_state != ST_IDLE);
    assign done = (curr_state == ST_DONE);

endmodule
