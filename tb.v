// Include the design file we're gonna test
`include "async_fifo.v"

module async_fifo_tb;

  // --- Parameters ---
  parameter DATA_WIDTH = 8;
  parameter DEPTH = 8; // make sure this matches the design if not default

  // --- Wires and Regs ---
  wire [DATA_WIDTH-1:0] dataout;
  wire full;
  wire empty;
  reg [DATA_WIDTH-1:0] datain;
  reg w_en, wrclk, wrst;
  reg r_en, rclk, rrst;


  // --- Instantiation ---
  // connecting up the DUT (Device Under Test)
  // using named ports is way better, less confusing
  async_fifo #(
    .DATA_WIDTH(DATA_WIDTH),
    .DEPTH(DEPTH)
  ) dut (
    .w_clk      (wrclk),
    .w_rst_n    (wrst),  // my design uses active low reset
    .w_en       (w_en),
    .data_in    (datain),

    .r_clk      (rclk),
    .r_rst_n    (rrst), // active low here too
    .r_en       (r_en),
    .data_out   (dataout),

    .full       (full),
    .empty      (empty)
  );

  // --- Clock Generation ---
  // a couple of wacky async clocks
  always #5 wrclk = ~wrclk;  // write clock, 10ns period
  always #8 rclk = ~rclk;  // read clock, 16ns period
  
  // --- Main Test Sequence ---
  initial begin
    $display("Test Started...");
    // setup initial values
    wrclk = 1'b0;
    rclk = 1'b0;
    datain <= 0;
    w_en <= 0;
    r_en <= 0;
    
    // Assert resets (active low, so set to 0)
    wrst = 1'b0;
    rrst = 1'b0;
    #100; // hold reset for a bit
    
    // De-assert resets
    wrst = 1'b1;
    rrst = 1'b1;
    $display("Resets de-asserted. Starting operations.");

    // ---- PHASE 1: Write until the FIFO is full ----
    $display("Phase 1: Writing until full...");
    while(!full) begin
      @(posedge wrclk);
      w_en <= 1'b1;
      datain <= $random;
    end
    @(posedge wrclk);
    w_en <= 1'b0; // stop writing
    $display("FIFO is full.");

    #200; // wait a bit

    // ---- PHASE 2: Read until the FIFO is empty ----
    $display("Phase 2: Reading until empty...");
    while(!empty) begin
        @(posedge rclk);
        r_en <= 1'b1;
    end
    @(posedge rclk);
    r_en <= 1'b0; // stop reading
    $display("FIFO is empty.");

    #200;

    // ---- PHASE 3: Concurrent write and read ----
    $display("Phase 3: Concurrent R/W for 200 write clocks...");
    fork
        // write process
        begin: write_proc
            for (integer i=0; i<200; i=i+1) begin
                @(posedge wrclk);
                w_en <= !full; // only write if not full
                datain <= $urandom_range(1, 200);
            end
            w_en <= 0;
        end
        // read process
        begin: read_proc
            for (integer j=0; j<200; j=j+1) begin
                @(posedge rclk);
                r_en <= !empty; // only read if not empty
                #3; // add some random delay
            end
            r_en <= 0;
        end
    join
    
    $display("Concurrent test finished.");

    #500;
    $display("Test Finished Successfully!");
    $finish;
  end
 
  // --- Waveform Dumping ---
  initial begin
    $dumpfile("fifo_waves.vcd");
    $dumpvars(0, async_fifo_tb);
  end

endmodule
