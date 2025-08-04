module tfsync #(parameter WIDTH=3)(
      input [WIDTH:0] din,
      input clk,
      input rst,
      output reg [WIDTH:0] dout
);
reg[WIDTH:0] dmeta;

always @(posedge clk or negedge rst)
begin
    if(!rst)
    begin
        dmeta<=0;
        dout<=0;
    end

    else
    begin
        dmeta<=din;
        dout<=dmeta;
    end
end
    
endmodule

/*
module b2g_convert #(
    parameter PTR_WIDTH=3
) (
    input [PTR_WIDTH-1:0] binary_ptr,

    output reg [PTR_WIDTH-1:0] gray_ptr
    
);

always@(*)
begin
    gray_ptr<=binary_ptr^(binary_ptr>>1);
end
    
endmodule

module g2b_convert #(
    parameter PTR_WIDTH=3
) (
    input [PTR_WIDTH-1:0] gray_input,
    output reg [PTR_WIDTH-1:0] binary_output
);
integer i;

always@(*)begin
    binary_output[PTR_WIDTH-1]<=gray_input[PTR_WIDTH-1];
    for (i =1;i<PTR_WIDTH ;i=i+1 ) begin
        binary_output[i]<=binary_output[i-1]^(gray_input[i]);
        
    end
end

    
endmodule
*/

module wptr_handler #(
    parameter WIDTH=3
) (
    input wclk,wrst,w_en,
    input [WIDTH:0] g_rptr_sync,
    output reg [WIDTH:0] b_wptr,
    output reg [WIDTH:0] g_wptr,
    output reg full
);
 
wire [WIDTH:0] b_wptr_nxt;
wire [WIDTH:0] g_wptr_nxt;
wire w_full;
assign b_wptr_nxt=b_wptr+(w_en&!full);
assign g_wptr_nxt=b_wptr_nxt^(b_wptr_nxt>>1);

always@(posedge wclk or negedge wrst)begin
    if(!wrst)begin
        b_wptr<=0;
        g_wptr<=0;
    end

    else begin
        b_wptr<=b_wptr_nxt;
        g_wptr<=g_wptr_nxt;
    end
end
assign w_full=(g_wptr_nxt==({~(g_rptr_sync[WIDTH:WIDTH-1]),g_rptr_sync[WIDTH-2:0]}));
always @(posedge wclk or negedge wrst) begin
    if(!wrst) full<=0;
    else full<=w_full;
      
end

    
endmodule


module rptr_handler #(
    parameter WIDTH=3
) (
    input rclk,rrst,r_en,
    input [WIDTH:0] g_wptr_sync,
    output reg [WIDTH:0] b_rptr,
    output reg [WIDTH:0] g_rptr,
    output reg  empty
);
wire [WIDTH:0] b_rptr_nxt,g_rptr_nxt;
wire r_emp;

assign b_rptr_nxt=b_rptr+(r_en & !empty);
assign g_rptr_nxt=b_rptr_nxt^(b_rptr_nxt>>1);
assign r_emp=(g_wptr_sync==g_rptr_nxt);

always @(posedge rclk or negedge rrst) begin
     if(!rrst)begin
        b_rptr<=0;
        g_rptr=0;
     end

     else begin
        b_rptr<=b_rptr_nxt;
        g_rptr<=g_rptr_nxt;
     end
end
always @(posedge rclk or negedge rrst) begin
    if(!rrst)begin
            empty<=1;
    end

    else empty<=r_emp;
    
end
endmodule

module fifo #(
    parameter DEPTH=8,DATA_WIDTH=8,PTR_WIDTH=3
) (
    input w_clk,w_en,rclk,r_en,
    input [PTR_WIDTH:0] b_wptr,b_rptr,
    input [DATA_WIDTH-1:0] data_in,
    input full,empty,
    output reg [DATA_WIDTH-1:0] data_out
);

reg[DATA_WIDTH-1:0] FIFO [0:DEPTH-1];

always @(posedge w_clk) begin
    if(w_en & !full)begin
        FIFO[b_wptr[PTR_WIDTH-1:0]]<=data_in;
    end
    
end

always @(posedge rclk) begin

    if (r_en & !empty) begin

        data_out<=FIFO[b_rptr[PTR_WIDTH-1:0]];
        
    end
    
end
endmodule



module asynchronous_fifo #(parameter DEPTH=8, DATA_WIDTH=8,PTR_WIDTH=3) (
  input wclk, wrst_n,
  input rclk, rrst_n,
  input w_en, r_en,
  input [DATA_WIDTH-1:0] data_in,
  output [DATA_WIDTH-1:0] data_out,
  output full, empty
);
  
  
 
  wire [PTR_WIDTH:0] g_wptr_sync, g_rptr_sync;
  wire [PTR_WIDTH:0] b_wptr, b_rptr;
  wire [PTR_WIDTH:0] g_wptr, g_rptr;
  

  tfsync #(PTR_WIDTH) sync_wptr (g_wptr,wclk,wrst_n, g_wptr_sync); //write pointer to read clock domain
  tfsync #(PTR_WIDTH) sync_rptr (g_rptr,rclk,rrst_n, g_rptr_sync); //read pointer to write clock domain 
  
  wptr_handler #(PTR_WIDTH) wptr_h(wclk, wrst_n, w_en,g_rptr_sync,b_wptr,g_wptr,full);
  rptr_handler #(PTR_WIDTH) rptr_h(rclk, rrst_n, r_en,g_wptr_sync,b_rptr,g_rptr,empty);
  fifo #(DEPTH,DATA_WIDTH,PTR_WIDTH)fifom(wclk, w_en, rclk, r_en,b_wptr, b_rptr, data_in,full,empty,data_out);

endmodule

