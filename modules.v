//
// a basic 2-flop synchronizer to deal with cdc.
// it'll add 2 clk cycles of latency but stops metastability. hopefully.
//
module cdc_synchronizer #(
    parameter width = 4
) (
    input clk,
    input rst_n,
    input [width-1:0] async_in,
    output reg [width-1:0] sync_out
);

    reg [width-1:0] meta_flop;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            meta_flop <= 0;
            sync_out <= 0;
        end 
        else begin
            meta_flop<= async_in; //1st flop
            sync_out <=meta_flop; //2nd flop
        end
    end

endmodule

//
// Module: fifo_pointer_logic
// handles all the pointer stuff for either the write or read side.
// use the parameter to tell it which one it is.
//
module fifo_pointer_logic #(
    parameter ADDR_WIDTH = 3,
    parameter IS_WR_DOMAIN = 0 // 1 for write pointer (checks full), 0 for read pointer (checks empty)
) (
    input                       clk,
    input rst_n,
    input incr_en,        // w_en or r_en
    input [ADDR_WIDTH:0]        synced_remote_gptr,
    output reg [ADDR_WIDTH:0]    b_ptr,          //binary ptr
    output reg [ADDR_WIDTH:0]    g_ptr,          // gray ptr
    output reg                  status_flag     // Full or Empty
);

    wire [ADDR_WIDTH:0] b_ptr_next;
    wire [ADDR_WIDTH:0] g_ptr_next;
    wire                status_flag_comb;

    // increment pointer if we're enabled and not already full/empty
    assign b_ptr_next = b_ptr + (incr_en & !status_flag);
    // binary to gray conversion
    assign g_ptr_next = b_ptr_next ^ (b_ptr_next >> 1);

    // Pointer registers
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            b_ptr <= 0;
            g_ptr <= 0;
        end else begin
           b_ptr <= b_ptr_next;
           g_ptr <= g_ptr_next;
        end
    end

    // Full/Empty logic here
    generate
        if (IS_WR_DOMAIN) begin : full_check_logic
            // full check is weird, have to invert the top two bits of the synced ptr.
            // this is the standard way to do it.
            assign status_flag_comb = (g_ptr_next == {~synced_remote_gptr[ADDR_WIDTH:ADDR_WIDTH-1], synced_remote_gptr[ADDR_WIDTH-2:0]});
        end else begin : empty_check_logic
            // empty check is easy, just compare 'em
            assign status_flag_comb = (g_ptr_next == synced_remote_gptr);
        end
    endgenerate

    // status flag register
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // on reset, fifo is always empty, never full.
            status_flag <= (IS_WR_DOMAIN) ? 1'b0 : 1'b1;
        end 
        else begin
            status_flag <= status_flag_comb;
        end
    end

endmodule


//
// Module: fifo_ram
// Description: just the memory part of the fifo. simple dual port ram.
//
module fifo_ram #(
    parameter DATA_WIDTH = 8,
    parameter DEPTH = 8,
    parameter ADDR_WIDTH = 3
) (
    // Write Port
    input                       w_clk,
    input                       w_en,
    input      [ADDR_WIDTH-1:0] w_addr,
    input [DATA_WIDTH-1:0] data_in,
    input full,

    // Read Port
    input                       r_clk,
    input                       r_en,
    input      [ADDR_WIDTH-1:0] r_addr,
    output reg [DATA_WIDTH-1:0] data_out,
    input                       empty
);

    // the core memory array
    reg [DATA_WIDTH-1:0] mem_core [0:DEPTH-1];

    // Write Logic
    always @(posedge w_clk) begin
        if(w_en && !full)begin
            mem_core[w_addr] <= data_in;
        end
    end

    // Read Logic
    always @(posedge r_clk) begin
        if (r_en && !empty) 
        begin
            data_out <= mem_core[r_addr];
        end
    end

endmodule


//
// a-sync fifo top level module
// wires all the other blocks together
//
module async_fifo #(
    parameter DATA_WIDTH = 8,
    parameter DEPTH      = 8
) (
    // Write Domain
    input w_clk,
    input w_rst_n,
    input w_en,
    input [DATA_WIDTH-1:0] data_in,

    // Read Domain
    input                       r_clk,
    input r_rst_n,
    input                       r_en,
    output     [DATA_WIDTH-1:0] data_out,

    // Status Flags
    output full,
    output empty
);

    // Calculate pointer widths from depth. dont touch this.
    localparam ADDR_WIDTH=$clog2(DEPTH);
    localparam PTR_WIDTH  = ADDR_WIDTH + 1;

    // internal wires
    wire [PTR_WIDTH-1:0] w_b_ptr, w_g_ptr; 
    wire [PTR_WIDTH-1:0] r_b_ptr, r_g_ptr; 

    wire [PTR_WIDTH-1:0] w_g_ptr_to_rdom; // wptr synced to read clk
    wire [PTR_WIDTH-1:0] r_g_ptr_to_wdom; // rptr synced to write clk

    // --- connect stuff up ---

    // write pointer logic instance
    fifo_pointer_logic #(
        .ADDR_WIDTH      (ADDR_WIDTH),
        .IS_WR_DOMAIN (1)
    ) u_wr_ptr (
        .clk                (w_clk),
        .rst_n              (w_rst_n),
        .incr_en            (w_en),
        .synced_remote_gptr (r_g_ptr_to_wdom),
        .b_ptr (w_b_ptr),
        .g_ptr              (w_g_ptr),
        .status_flag (full)
    );

    // read pointer logic
    fifo_pointer_logic #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .IS_WR_DOMAIN (0)
    ) u_rd_ptr (
        .clk(r_clk),
        .rst_n(r_rst_n),
        .incr_en(r_en),
        .synced_remote_gptr (w_g_ptr_to_rdom),
        .b_ptr(r_b_ptr),
        .g_ptr(r_g_ptr),
        .status_flag(empty)
    );


    // Synchronize read ptr to write domain
    cdc_synchronizer #(
        .width (PTR_WIDTH)
    ) rptr_sync_unit (
        .clk(w_clk),
        .rst_n(w_rst_n),
        .async_in(r_g_ptr),
        .sync_out(r_g_ptr_to_wdom)
    );

    // Synchronize write ptr to read domain
    cdc_synchronizer #(
        .width (PTR_WIDTH)
    ) wptr_sync_unit (
        .clk (r_clk),
        .rst_n(r_rst_n),
        .async_in (w_g_ptr),
        .sync_out (w_g_ptr_to_rdom)
    );


    // the memory instance
    fifo_ram #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(DEPTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) fifo_mem_inst (
        .w_clk(w_clk),
        .w_en(w_en),
        .w_addr(w_b_ptr[ADDR_WIDTH-1:0]),
        .data_in(data_in),
        .full(full),

        .r_clk(r_clk),
        .r_en(r_en),
        .r_addr(r_b_ptr[ADDR_WIDTH-1:0]),
        .data_out(data_out),
        .empty(empty)
    );

endmodule
