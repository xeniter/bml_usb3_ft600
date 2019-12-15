/* ****************************************************************************
-- Source file: ft600_fsm.v              
-- Date:        October 26, 2017
-- Author:      khubbard
-- Description: Verilog RTL for interfacing to FTDI FT600 USB3 FIFO        
-- Language:    Verilog-2001 and VHDL-1993
-- Simulation:  Mentor-Modelsim 
-- Synthesis:   Xilinst-XST 
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
-- ----  --------  -------- ---------------------------------------------------
-- 0.1   10.26.17  khubbard Creation
-- ***************************************************************************/
`default_nettype none // Strictly enforce all nets to be declared
                                                                                
module ft600_fsm
(
  input  wire         clk_ft,            // 66 or 100 MHz
  input  wire         reset,             // 
  input  wire         ft600_rxf_l,       // FT Wi path has data ready
  input  wire         ft600_txe_l,       // FT Ro path can accept data
  input  wire [15:0]  ft600_d_in,        // Bidi datapath
  output wire [15:0]  ft600_d_out,       // Bidi datapath
  output wire [15:0]  ft600_d_oe_l,      // Bidi datapath
  input  wire [1:0]   ft600_be_in,       // Bidi byte enable
  output wire [1:0]   ft600_be_out,      // Bidi byte enable
  output wire [1:0]   ft600_be_oe_l,     // Bidi byte enable
  output wire         ft600_oe_l,        // Give okay for FT to drive datapath
  output wire         ft600_rd_l,        // FT Wi path read request
  output wire         ft600_wr_l,        // FT Ro path write enable
  output reg          dbg_ft_rd,         // Debug signal
  output reg          dbg_ft_wr,         // Debug signal
  output wire [7:0]   dbg_byte,
  output wire         dbg_sample,
  output reg          mesa_wi_char_en,   // Strobe for Wi ASCII Character
  output reg  [7:0]   mesa_wi_char_d,    // 8bit Wi ASCII Character
  input  wire         mesa_ro_pop_rdy,   // ro buffer has data to send
  output reg          mesa_ro_pop_en,    // ACK for ro buffer to send data
  output wire         mesa_ro_pop_ck_en, // Clock enable for stalling ro buffer
  input  wire [7:0]   mesa_ro_char_d,    // 8bit ASCII character from ro buffer
  input  wire         mesa_ro_char_rdy   // Ready strobe for 8bit ASCII char
);// module ft600_fsm


  reg  [15:0]   ft600_d_in_p1;
  reg           mesa_ro_pop_ck_en_l;
  reg           ft_oe_l_fal; 
  reg           ft_dir_oe_l_fal;
  reg           ft_oe_l;
  reg           ft_rd_l_fal; 
  reg           ft_rd_l;
  reg           ft_wr_l_fal; 
  reg           ft_wr_l;
  reg  [15:0]   ft_d_out_fal;
  reg  [15:0]   ft_d_out;
  reg  [1:0]    ft_be_out_fal;
  reg  [1:0]    ft_be_out;
  reg           ft_dir_fal;
  reg           ft_dir_oe_l;
  reg  [7:0]    ft_rxf_l_sr;
  wire          d_in_sample;


  assign ft600_oe_l    = ft_oe_l_fal;
  assign ft600_rd_l    = ft_rd_l_fal;
  assign ft600_wr_l    = ft_wr_l_fal;
  assign ft600_be_out  = ft_be_out_fal[1:0];
  assign ft600_d_out   = ft_d_out_fal[15:0];
  assign ft600_d_oe_l  = {16{ft_dir_oe_l_fal}};
  assign ft600_be_oe_l = { 2{ft_dir_oe_l_fal}};

  assign dbg_byte = ft600_d_in_p1[7:0];
  assign dbg_sample = d_in_sample;


//-----------------------------------------------------------------------------
// FT600 Cycles
// READ CYCLE:
//   CLK         __/  \__/  \__/  \__/  \__/  \__/  \__/  \__/  \__/  \_
//   TXE_L
//   RXF_L             \__________________________________/
//   OE_L                   \___________________________________/
//   RD_L                         \_____________________________/
//   WR_L        
//   DATA[15:0]  -----------------< D0>< D1>< D2>< D3>< D4>-------------- 
//   BE[1:0]     _________________/                       \______________
//
// WRITE CYCLE:
//   CLK         __/  \__/  \__/  \__/  \__/  \__/  \__/  \__/  \__/  \__
//   TXE_L             \___________________________________/
//   WR_L                         \_____________________________/
//   DATA[15:0]  -----------------< D0>< D1>< D2>< D3>< D4>---------------
//   BE[1:0]     _________________/                       \______________
//
//
// Captured 32 xfer cycle for LB_Read
//   rxf  ___/          \___________/    \____
//   txe  _______________________________________________/           \___
//   oe   ____/          \___________/     \__
//   rd   ____/          \___________/     \__
//   wr   _________________________________________________/         \___
//            |<---28--->|           |<-4->|<-- ~1-3mS-->|
//-----------------------------------------------------------------------------
always @ ( posedge clk_ft ) begin : proc_fsm
 begin
  ft_oe_l          <= 1;// Tell FT600 to float pins default
  ft_rd_l          <= 1;// Dont pop 
  ft_d_out         <= 16'd0;
  ft_be_out        <= 2'b00;
  ft_wr_l          <= 1;
  ft_rxf_l_sr      <= { ft_rxf_l_sr[6:0], ft600_rxf_l };
  mesa_wi_char_en  <= 0;
  mesa_wi_char_d   <= 8'd0;
  dbg_ft_rd        <= ~ ft_rd_l;
  dbg_ft_wr        <= ~ ft_wr_l;
  ft600_d_in_p1    <= ft600_d_in[15:0];// Note ft600_phy 8bits are tossed

  // WARNING: This timing between rxf_l==0 and rd_l<=0 is critical. If circuit
  // waits longer, FT600 FIFO oscillates, de-asserting rxf_l after a few cks
  if ( ft600_rxf_l == 0 ) begin
    ft_rd_l <= 0;// Tell FT600 to pop data         
    ft_oe_l <= 0;// Tell FT600 to drive pins       
  end

  if ( d_in_sample == 1 ) begin 
    mesa_wi_char_en  <= 1;
    mesa_wi_char_d   <= ft600_d_in_p1[7:0];// Note ft600_phy 8bits are tossed
  end
 
  if ( mesa_ro_char_rdy == 1 && ft600_txe_l == 0 ) begin
    ft_dir_oe_l <= 0;// FPGA drives pins 
    ft_d_out    <= { 8'h7E, mesa_ro_char_d[7:0] };// "~" + ro Char
    ft_be_out   <= 2'b11;
    ft_wr_l     <= 0;
  end else begin
    ft_dir_oe_l <= 1;// Don't let FPGA drive pins 
  end 

  if ( ft600_txe_l == 1 ) begin
    ft_wr_l <= 1;
  end

  if ( reset == 1 ) begin
    ft_rxf_l_sr      <= 8'b11111111;
    mesa_wi_char_en  <= 0;
    mesa_wi_char_d   <= 8'd0;
    ft_dir_oe_l      <= 1;// Don't let FPGA drive pins 
  end 

 end 
end  // proc_fsm
  assign d_in_sample = ( ft_rxf_l_sr[0] == 0 && ft_rxf_l_sr[2] == 0 &&
                         ft_rd_l == 0 ) ? 1 : 0;


//-----------------------------------------------------------------------------
// Outputs to FT600 are on negative clock edge
//-----------------------------------------------------------------------------
always @ ( negedge clk_ft ) begin : proc_dout_fal
  ft_oe_l_fal     <= ft_oe_l;
  ft_rd_l_fal     <= ft_rd_l;
  ft_wr_l_fal     <= ft_wr_l;
  ft_dir_oe_l_fal <= ft_dir_oe_l;
  ft_d_out_fal    <= ft_d_out[15:0];
  ft_be_out_fal   <= ft_be_out[1:0];
end  // proc_dout_fal


//-----------------------------------------------------------------------------
// Interface the FT600 USB3 FIFO to the MesaBus PHY
//-----------------------------------------------------------------------------
always @ ( posedge clk_ft ) begin : proc_phy_fsm
  if ( ft600_txe_l == 0 && mesa_ro_pop_rdy == 1 ) begin
    mesa_ro_pop_en <= 1;// Pop the continuous byte stream from mesa_ro_buffer.v
  end else begin
    mesa_ro_pop_en <= 0;
  end 
  mesa_ro_pop_ck_en_l <= ft600_txe_l;
end  // proc_phy_fsm
  assign mesa_ro_pop_ck_en = ~ mesa_ro_pop_ck_en_l;


endmodule // ft600_fsm
