/* ****************************************************************************
-- (C) Copyright 2017 Kevin M. Hubbard - All rights reserved.
-- Source file: mesa_ro_buffer.v
-- Date:        October 2017
-- Author:      khubbard
-- Description: Byte buffer for Mesa Bus for storing intermittent stream of 
--              ro bytes until the read is complete, then provides constant
--              stream of ro bytes as required by USB3 interface FIFO.
--              Basically a store then dump non-circular FIFO
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
-- Ver#  When      Who      What
-- ----  --------  -------- --------------------------------------------------
-- 0.1   10.21.17  khubbard Creation
-- ***************************************************************************/
`default_nettype none // Strictly enforce all nets to be declared


module mesa_ro_buffer #
(
   parameter depth_len      =  512,
   parameter depth_bits     =  9
)
(
  input  wire         reset,
  input  wire         clk,
  input  wire         pop_ck_en,
  input  wire         push_done,
  input  wire         pop_en,
  output reg          pop_rdy,  
  input  wire         din_en,
  input  wire [7:0]   din_d,
  output reg          dout_rdy,
  output reg  [7:0]   dout_d
);


  reg  [7:0]              ram_array[depth_len-1:0];
  reg  [depth_bits-1:0]   a_addr;
  reg                     a_we;
  reg  [7:0]              a_di;
  reg  [depth_bits-1:0]   b_addr;
  reg  [7:0]              b_do;
  reg                     b_en;
  reg  [3:0]              b_en_sr;
  reg  [depth_bits-1:0]   stop_addr;
  reg                     pop_jk;
  reg  [3:0]              done_sr;
  wire [15:0]             zeros;
  wire [15:0]             ones;
  reg                     pop_en_p1;

  assign zeros = 16'd0;
  assign ones  = 16'hFFFF;


//-----------------------------------------------------------------------------
// Push process
//-----------------------------------------------------------------------------
always @ ( posedge clk or posedge reset ) begin : proc_din 
  if ( reset == 1 ) begin 
    a_we      <= 0;
    a_addr    <= zeros[depth_bits-1:0];
    stop_addr <= zeros[depth_bits-1:0];
    a_di      <= 8'd0;
    done_sr   <= 4'd0;
  end else begin 
    a_di    <= din_d[7:0];
    done_sr <= { done_sr[2:0], push_done };// Must delay as preceeds last pushes
    a_we   <= 0;
    if ( din_en == 1 ) begin 
      a_we      <= 1;
      a_addr    <= a_addr + 1;
    end 
    if ( a_we == 1 ) begin 
      stop_addr <= a_addr;
    end
    if ( done_sr[3] == 1 ) begin
      a_addr <= zeros[depth_bits-1:0];
    end 
  end 
end // proc_din


//-----------------------------------------------------------------------------
// Pop process
//-----------------------------------------------------------------------------
always @ ( posedge clk or posedge reset ) begin : proc_dout
  if ( reset == 1 ) begin 
    b_en      <= 0;
    b_en_sr   <= 4'd0;
    b_addr    <= zeros[depth_bits-1:0];
    pop_jk    <= 0;
    pop_rdy   <= 0;
    pop_en_p1 <= 0;
    dout_rdy  <= 0;
    dout_d    <= 8'd0;
  end else begin 
   if ( pop_ck_en == 1 ) begin
     b_en_sr   <= { b_en_sr[2:0], b_en };
//   dout_rdy  <= b_en_sr[1] & b_en_sr[0];
     dout_rdy  <= b_en_sr[1];
     dout_d    <= b_do[7:0];
     pop_en_p1 <= pop_en;
   end
   if ( b_en_sr[0] == 0 ) begin
     dout_rdy <= 0;
   end

    if ( done_sr[3] == 1 ) begin
      pop_rdy <= 1;// FIFO has data ready to be popped
    end
    if ( pop_ck_en == 1 ) begin
      if ( pop_en == 1 && pop_en_p1 == 0 && pop_jk == 0 ) begin
        b_en    <= 1;
        b_addr  <= zeros[depth_bits-1:0];
        pop_jk  <= 1;
        pop_rdy <= 0;
      end
      if ( pop_jk == 1 ) begin 
        b_addr <= b_addr + 1;
        if ( b_addr == stop_addr ) begin
          b_en   <= 0;
          pop_jk <= 0;
        end
      end 
    end 
  end
end


//-----------------------------------------------------------------------------
// Infer Dual Port RAM
//-----------------------------------------------------------------------------
always @( posedge clk )
begin
  if ( a_we ) begin
    ram_array[a_addr] <= a_di[7:0];
  end
end // always


//-----------------------------------------------------------------------------
// Read Port of RAM
//-----------------------------------------------------------------------------
always @( posedge clk )
begin
  if ( pop_ck_en == 1 ) begin
    if ( b_en == 1 ) begin
      b_do <= ram_array[b_addr];
    end
  end
end // always


endmodule // mesa_ro_buffer
