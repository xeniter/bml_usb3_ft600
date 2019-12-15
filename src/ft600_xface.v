/* ****************************************************************************
-- Source file: ft600_xface.v              
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
                                                                                
module ft600_xface
(
  input  wire         reset,       
  input  wire         clk_ft,      // 66 or 100 MHz
  output wire         dbg_ft_rd,
  output wire         dbg_ft_wr,
  input  wire         ft600_txe_l,
  input  wire         ft600_rxf_l,
  input  wire [15:0]  ft600_d_in,
  output wire [15:0]  ft600_d_out,
  output wire [15:0]  ft600_d_oe_l,
  input  wire [1:0]   ft600_be_in,
  output wire [1:0]   ft600_be_out,
  output wire [1:0]   ft600_be_oe_l,
  output wire         ft600_oe_l,
  output wire         ft600_rd_l,
  output wire         ft600_wr_l,
  output wire         lb_wr,
  output wire         lb_rd,
  output wire [31:0]  lb_wr_d,
  output wire [31:0]  lb_addr,
  input  wire         lb_rd_rdy,
  input  wire [31:0]  lb_rd_d,
  output wire [7:0]   dbg_byte,
  output wire         dbg_sample,
  output wire [4:0]   dbg_nib
);// module ft600_xface


  wire          mesa_wi_char_en;   // Strobe for Wi ASCII Character
  wire [7:0]    mesa_wi_char_d;    // 8bit Wi ASCII Character
  wire          mesa_ro_pop_rdy;   // ro buffer has data to send
  wire          mesa_ro_pop_en;    // ACK for ro buffer to send data
  wire          mesa_ro_pop_ck_en; // Clock enable for stalling ro buffer
  wire [7:0]    mesa_ro_char_d;    // 8bit ASCII character from ro buffer
  wire          mesa_ro_char_rdy;  // Ready strobe for 8bit ASCII char
  wire          bang_reset      ;  // 


//-----------------------------------------------------------------------------
// State Machine for handshaking with external FT600 FIFO
//-----------------------------------------------------------------------------
ft600_fsm u_ft600_fsm
(
  .clk_ft            ( clk_ft              ),
  .reset             ( reset               ),
  .ft600_rxf_l       ( ft600_rxf_l         ),
  .ft600_txe_l       ( ft600_txe_l         ),
  .ft600_d_in        ( ft600_d_in[15:0]    ),
  .ft600_d_out       ( ft600_d_out[15:0]   ),
  .ft600_d_oe_l      ( ft600_d_oe_l[15:0]  ),
  .ft600_be_in       ( ft600_be_in[1:0]    ),
  .ft600_be_out      ( ft600_be_out[1:0]   ),
  .ft600_be_oe_l     ( ft600_be_oe_l[1:0]  ),
  .ft600_oe_l        ( ft600_oe_l          ),
  .ft600_rd_l        ( ft600_rd_l          ),
  .ft600_wr_l        ( ft600_wr_l          ),
  .mesa_wi_char_en   ( mesa_wi_char_en     ),
  .mesa_wi_char_d    ( mesa_wi_char_d[7:0] ),
  .mesa_ro_pop_rdy   ( mesa_ro_pop_rdy     ),
  .mesa_ro_pop_en    ( mesa_ro_pop_en      ),
  .mesa_ro_pop_ck_en ( mesa_ro_pop_ck_en   ),
  .mesa_ro_char_d    ( mesa_ro_char_d[7:0] ),
  .mesa_ro_char_rdy  ( mesa_ro_char_rdy    ),
  .dbg_byte          ( dbg_byte[7:0]       ),
  .dbg_sample        ( dbg_sample          ),
  .dbg_ft_rd         ( dbg_ft_rd           ),
  .dbg_ft_wr         ( dbg_ft_wr           ) 
);// module ft600_fsm


//-----------------------------------------------------------------------------
// USB3 MesaBus to Local Bus converter. This converts byte streams to localbus
//-----------------------------------------------------------------------------
mesa_usb3_phy u_mesa_usb3_phy
(
  .clk               ( clk_ft              ),
  .reset             ( reset | bang_reset  ),
  .mesa_wi_char_en   ( mesa_wi_char_en     ),
  .mesa_wi_char_d    ( mesa_wi_char_d[7:0] ),
  .mesa_wi_sim_en    ( 1'b0                ),
  .mesa_wi_sim_d     ( 8'd0                ),
  .dbg_nib           ( dbg_nib[4:0]        ),
  .bang_reset        ( bang_reset          ),
  .tx_wo_byte        (                     ),
  .tx_wo_rdy         (                     ),
  .ro_pop_ck_en      ( mesa_ro_pop_ck_en   ),
  .ro_pop_rdy        ( mesa_ro_pop_rdy     ),
  .ro_pop_en         ( mesa_ro_pop_en      ),
  .ro_usb_rdy        ( mesa_ro_char_rdy    ),
  .ro_usb_d          ( mesa_ro_char_d[7:0] ),
  .lb_wr             ( lb_wr               ),
  .lb_rd             ( lb_rd               ),
  .lb_addr           ( lb_addr[31:0]       ),
  .lb_wr_d           ( lb_wr_d[31:0]       ),
  .lb_rd_d           ( lb_rd_d[31:0]       ),
  .lb_rd_rdy         ( lb_rd_rdy           )
);// module mesa_ft600_phy


endmodule // ft600_xface
