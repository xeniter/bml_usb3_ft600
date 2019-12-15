/* ****************************************************************************
-- Source file: lb_read_cache.v
-- Date:        October 29, 2017
-- Author:      khubbard
-- Description: A SRAM cache for storing read cycles for reading later.
-- Language:    Verilog-2001
-- Simulation:  Mentor-Modelsim
-- Synthesis:   Xilint-XST,Xilinx-Vivado,Lattice-Synplify
-- License:     This project is licensed with the CERN Open Hardware Licence
--              v1.2.  You may redistribute and modify this project under the
--              terms of the CERN OHL v.1.2. (http://ohwr.org/cernohl).
--              This project is distributed WITHOUT ANY EXPRESS OR IMPLIED
--              WARRANTY, INCLUDING OF MERCHANTABILITY, SATISFACTORY QUALITY
--              AND FITNESS FOR A PARTICULAR PURPOSE. Please see the CERN OHL
--              v.1.2 for applicable Conditions.
--
-- Revision History:
-- Ver#  When      Who      What
-- ----  --------  -------- --------------------------------------------------
-- 0.1   10.29.17  khubbard Creation
-- ***************************************************************************/
`default_nettype none // Strictly enforce all nets to be declared


module lb_read_cache   
(
  input  wire         reset,
  input  wire         clk_lb,
  input  wire         lb_cs,
  input  wire         lb_wr,
  input  wire         lb_rd,
  input  wire [31:0]  lb_addr,
  input  wire [31:0]  lb_wr_d,
  output reg  [31:0]  lb_rd_d,
  output reg          lb_rd_rdy
);


  reg  [31:0]   ram_array[1024-1:0];
  reg  [10-1:0] a_addr;
  reg           a_we;
  reg  [31:0]   a_di;
  reg  [10-1:0] b_addr;
  reg  [31:0]   b_do;
  reg  [1:0]    b_en_sr;


//-----------------------------------------------------------------------------
// Connect inferred SRAM to local bus
//-----------------------------------------------------------------------------
always @ ( posedge clk_lb ) begin : proc_test_lb
  if ( lb_cs == 1 && lb_wr == 1 ) begin
    a_we   <= 1;
    a_di   <= lb_wr_d[31:0];
    a_addr <= lb_addr[12:2];// Note Byte to DWORD conversion
  end else begin
    a_we   <= 0;
    a_di   <= 32'd0;
    a_addr <= 10'd0;
  end

  lb_rd_rdy <= 0;
  lb_rd_d   <= 32'd0;
  b_en_sr[1:0] <= { b_en_sr[0], 1'b0 };
  if ( lb_cs == 1 && lb_rd == 1 ) begin
    b_en_sr[0] <= 1;
    b_addr     <= lb_addr[12:2];// Note Byte to DWORD conversion
  end else begin
    if ( b_en_sr[1] == 1 ) begin
      lb_rd_rdy <= 1;
      lb_rd_d   <= b_do[31:0];
    end
  end
end  // proc_cnt


//-----------------------------------------------------------------------------
// Infer Dual Port RAM
//-----------------------------------------------------------------------------
always @( posedge clk_lb )
begin
  if ( a_we ) begin
    ram_array[a_addr] <= a_di[31:0];
  end
end // always


//-----------------------------------------------------------------------------
// Read Port of RAM
//-----------------------------------------------------------------------------
always @( posedge clk_lb )
begin
  if ( b_en_sr[0] == 1 ) begin
    b_do <= ram_array[b_addr];
  end
end // always


endmodule // lb_read_cache
