/* ****************************************************************************
-- (C) Copyright 2017 Kevin M. Hubbard @ Black Mess Labs - All rights reserved.
-- Source file: top.v                
-- Date:        December 2017
-- Author:      khubbard
-- Description: Spartan3 Test Design that uses Mesa Backdoor and SUMP      
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
--           P2-Facing Pins                        P1-Facing Pins
--      ----------------------------        ----------------------------
--     | 1    3    5    7    GND 3V |      | 1    3    5    7    GND 3V |
--     | 0    2    4    6    GND 3V |      | 0    2    4    6    GND 3V |
--  ___|____________________________|______|____________________________|__
-- |                        BML USB 3.0 FT600 Board                        |
--  -----------------------------------------------------------------------
--       pmod_*_*<0> = ft600_d[1]            pmod_*_*<0> = ft600_clk  
--       pmod_*_*<1> = ft600_d[0]            pmod_*_*<1> = ft600_be[0]
--       pmod_*_*<2> = ft600_d[3]            pmod_*_*<2> = ft600_be[1] 
--       pmod_*_*<3> = ft600_d[2]            pmod_*_*<3> = ft600_txe_l
--       pmod_*_*<4> = ft600_d[5]            pmod_*_*<4> = ft600_rxf_l
--       pmod_*_*<5> = ft600_d[4]            pmod_*_*<5> = ft600_wr_l
--       pmod_*_*<6> = ft600_d[7]            pmod_*_*<6> = ft600_rd_l
--       pmod_*_*<7> = ft600_d[6]            pmod_*_*<7> = ft600_oe_l
--
-- Revision History:
-- Ver#  When      Who      What
-- ----  --------  -------- ---------------------------------------------------
-- 0.1   12.18.17  khubbard Creation
-- ***************************************************************************/
`default_nettype none // Strictly enforce all nets to be declared
                                                                                
module top
(
  input  wire         rst_l,
  input  wire         clk_lb,      // 40 MHz Main Input Clock
  output wire         ok_led,

  output wire         bd_txd,      // FT232 UART connection to a FTDI cable
  input  wire         bd_rxd,      // Apply soft-pullup to this pin.

  input  wire         ft600_clk,  // dual-PMOD to FT600
  inout  wire [7:0]   ft600_d,
  inout  wire [1:0]   ft600_be,
  input  wire         ft600_txe_l,
  input  wire         ft600_rxf_l,
  output wire         ft600_oe_l,
  output wire         ft600_rd_l,
  output wire         ft600_wr_l
);// module top


  wire          clk_lb_tree;
  wire          rst_l_loc;
  wire          reset_loc;
  reg           reset_ft600;
  wire          bd_rxd_loc;
  wire          bd_txd_loc;
  reg           ok_led_loc;

  wire          ft_lb_cs_u0;
  wire          uart_lb_cs_u1;

  wire [31:0]   u0_lb_rd_d;
  wire          u0_lb_rd_rdy;
  wire [31:0]   u1_lb_rd_d;
  wire          u1_lb_rd_rdy;

  reg  [25:0]   led_cnt;
  reg  [25:0]   led_cnt_p1;
  reg  [31:0]   ft_lb_00_reg;
  reg  [31:0]   ft_lb_04_reg;
  reg  [31:0]   ft_lb_08_reg;
  reg  [31:0]   ft_lb_0c_reg;
  reg  [31:0]   uart_lb_00_reg;
  reg  [31:0]   uart_lb_04_reg;
  reg  [31:0]   uart_lb_08_reg;
  reg  [31:0]   uart_lb_0c_reg;
 
  wire          ft_lb_wr;
  wire          ft_lb_rd;
  wire [31:0]   ft_lb_addr;
  wire [31:0]   ft_lb_wr_d;
  reg  [31:0]   ft_lb_rd_d;
  reg           ft_lb_rd_rdy;
  wire [15:0]   ft600_d_in;
  wire [15:0]   ft600_d_out;
  wire [15:0]   ft600_d_oe_l;
  wire [15:0]   ft600_be_in;
  wire [15:0]   ft600_be_out;
  wire [15:0]   ft600_be_oe_l;

  wire          uart_lb_wr;
  wire          uart_lb_rd;
  wire [31:0]   uart_lb_addr;
  wire [31:0]   uart_lb_wr_d;
  reg  [31:0]   uart_lb_rd_d;
  reg           uart_lb_rd_rdy;
  reg  [9:0]    uart_timeout_cnt;
  reg  [9:0]    ft_timeout_cnt;

  wire          clk_ft_tree;
  wire          clk_ft_tree_loc;


  assign ok_led = ok_led_loc;
  assign reset_loc = ~rst_l_loc;

// For some reason UCF's IOB = TRUE didn't apply for all, so handle here
// For IO timing, make sure at the ft600 signals are flopped in the IOB
// synthesis attribute IOB of ft600_rd_l    is "TRUE"
// synthesis attribute IOB of ft600_wr_l    is "TRUE"
// synthesis attribute IOB of ft600_oe_l    is "TRUE"
// synthesis attribute IOB of ft600_d[7:0]  is "TRUE"
// synthesis attribute IOB of ft600_be[1:0] is "TRUE"
// synthesis attribute IOB of ft600_rxf_l   is "TRUE"
// synthesis attribute IOB of ft600_txe_l   is "TRUE"

  BUFG u2_clk_tree   (.I( clk_lb          ),.O( clk_lb_tree      ));
  BUFG u3_clk_tree   (.I( clk_ft_tree_loc ),.O( clk_ft_tree      ));

//-----------------------------------------------------------------------------
// Use a DLL to remove clock insertion delay 
// Note: clock comes on 500ms prior to USB traffic
//-----------------------------------------------------------------------------
CLKDLL u_pll
(
  .RST                             ( reset_loc                      ),
  .CLKIN                           ( ft600_clk                      ),
  .CLKFB                           ( clk_ft_tree                    ),
  .CLK0                            ( clk_ft_tree_loc                ),
  .CLK90                           (                                ),
  .CLK180                          (                                ),
  .CLK270                          (                                ),
  .CLK2X                           (                                ),
  .CLKDV                           (                                ),
  .LOCKED                          (                                )
);


//-----------------------------------------------------------------------------
// Flash an LED when the FT600 provides a clock.
// WARNING: The FT600 has the ability to keep the clock on ALWAYS, but enabling
// this feature disables the USB 2.0 backwards compatibility of the chip such
// that it will only work with a USB 3.0 host. Very annoying.
// WARNING: Was having a powerup issue with 1st ft600 read being off by a byte.
//  Adding reset_ft600 here cleared up this issue. Suspect the problem was
//  in ft600_fsm/rxf_l_sr[7:0] initalizing to 0s
//-----------------------------------------------------------------------------
always @ ( posedge clk_ft_tree or posedge reset_loc ) begin : proc_led 
 if ( reset_loc == 1 ) begin
   led_cnt      <= 26'd0;
   led_cnt_p1   <= 26'd0;
   ok_led_loc   <= 0;
   reset_ft600  <= 1;
 end else begin
   reset_ft600  <= 0;
   ok_led_loc   <= 0;
   led_cnt_p1   <= led_cnt[25:0];
   led_cnt      <= led_cnt + 1;
   if ( led_cnt[19] == 1 ) begin
     ok_led_loc <= 1;
   end
 end // clk+reset
end // proc_led


// ----------------------------------------------------------------------------
// LocalBus Test Interface for FT600 interface
// ----------------------------------------------------------------------------
always @ ( posedge clk_ft_tree or posedge reset_loc ) begin : proc_ft_lb 
 if ( reset_loc == 1 ) begin
   ft_lb_00_reg   <= 32'd0;
   ft_lb_04_reg   <= 32'd0;
   ft_lb_08_reg   <= 32'd0;
   ft_lb_0c_reg   <= 32'h12345678;
   ft_lb_rd_rdy   <= 0;
   ft_lb_rd_d     <= 32'd0;
   ft_timeout_cnt <= 10'd1023;
 end else begin
   ft_lb_rd_d     <= 32'd0;
   ft_lb_rd_rdy   <= 0;

   if ( ft_lb_rd == 1 ) begin
     ft_timeout_cnt <= 10'd0;
   end else if ( ft_lb_rd_rdy == 1 ) begin
     ft_timeout_cnt <= 10'd1023;
   end else begin
     if ( ft_timeout_cnt != 10'd1023 ) begin
       ft_timeout_cnt <= ft_timeout_cnt + 1;
       if ( ft_timeout_cnt == 10'd1022 ) begin
         ft_lb_rd_rdy <= 1;
         ft_lb_rd_d   <= 32'hDEADBEEF;
       end
     end
   end 

   if ( ft_lb_addr[19:8] == 12'd0 ) begin
     if ( ft_lb_wr == 1 && ft_lb_addr[7:0] == 8'h00 ) begin
       ft_lb_00_reg <= ft_lb_wr_d[31:0];
     end
     if ( ft_lb_wr == 1 && ft_lb_addr[7:0] == 8'h04 ) begin
       ft_lb_04_reg <= ft_lb_wr_d[31:0];
     end
     if ( ft_lb_wr == 1 && ft_lb_addr[7:0] == 8'h08 ) begin
       ft_lb_08_reg <= ft_lb_wr_d[31:0];
     end
//   if ( ft_lb_wr == 1 && ft_lb_addr[7:0] == 8'h0c ) begin
//     ft_lb_0c_reg <= ft_lb_wr_d[31:0];
//   end

     if ( ft_lb_rd == 1 && ft_lb_addr[7:0] == 8'h00 ) begin
       ft_lb_rd_rdy <= 1;
       ft_lb_rd_d   <= ft_lb_00_reg[31:0];
     end
     if ( ft_lb_rd == 1 && ft_lb_addr[7:0] == 8'h04 ) begin
       ft_lb_rd_rdy <= 1;
       ft_lb_rd_d   <= ft_lb_04_reg[31:0];
     end
     if ( ft_lb_rd == 1 && ft_lb_addr[7:0] == 8'h08 ) begin
       ft_lb_rd_rdy <= 1;
       ft_lb_rd_d   <= ft_lb_08_reg[31:0];
     end
     if ( ft_lb_rd == 1 && ft_lb_addr[7:0] == 8'h0c ) begin
       ft_lb_rd_rdy <= 1;
       ft_lb_rd_d   <= ft_lb_0c_reg[31:0];
     end
   end

   if ( u0_lb_rd_rdy == 1 ) begin
     ft_lb_rd_rdy <= 1;
     ft_lb_rd_d   <= u0_lb_rd_d[31:0];
   end

 end // clk+reset
end // proc_ft_lb   


// ----------------------------------------------------------------------------
// LocalBus Test Interface for FT232 UART interface
// ----------------------------------------------------------------------------
always @ ( posedge clk_lb_tree or posedge reset_loc ) begin : proc_uart_lb 
 if ( reset_loc == 1 ) begin
   uart_lb_00_reg   <= 32'd0;
   uart_lb_04_reg   <= 32'd0;
   uart_lb_08_reg   <= 32'd0;
   uart_lb_0c_reg   <= 32'h12345678;
   uart_lb_rd_rdy   <= 0;
   uart_lb_rd_d     <= 32'd0;
   uart_timeout_cnt <= 10'd1023;
 end else begin
   uart_lb_rd_d   <= 32'd0;
   uart_lb_rd_rdy <= 0;

   if ( uart_lb_rd == 1 ) begin
     uart_timeout_cnt <= 10'd0;
   end else if ( uart_lb_rd_rdy == 1 ) begin
     uart_timeout_cnt <= 10'd1023;
   end else begin
     if ( uart_timeout_cnt != 10'd1023 ) begin
       uart_timeout_cnt <= uart_timeout_cnt + 1;
       if ( uart_timeout_cnt == 10'd1022 ) begin
         uart_lb_rd_rdy <= 1;
         uart_lb_rd_d   <= 32'hDEADBEEF;
       end
     end
   end 

   if ( uart_lb_addr[19:8] == 12'd0 ) begin
     if ( uart_lb_wr == 1 && uart_lb_addr[7:0] == 8'h00 ) begin
       uart_lb_00_reg <= uart_lb_wr_d[31:0];
     end
     if ( uart_lb_wr == 1 && uart_lb_addr[7:0] == 8'h04 ) begin
       uart_lb_04_reg <= uart_lb_wr_d[31:0];
     end
     if ( uart_lb_wr == 1 && uart_lb_addr[7:0] == 8'h08 ) begin
       uart_lb_08_reg <= uart_lb_wr_d[31:0];
     end
//   if ( uart_lb_wr == 1 && uart_lb_addr[7:0] == 8'h0c ) begin
//     uart_lb_0c_reg <= uart_lb_wr_d[31:0];
//   end

     if ( uart_lb_rd == 1 && uart_lb_addr[7:0] == 8'h00 ) begin
       uart_lb_rd_rdy <= 1;
       uart_lb_rd_d   <= uart_lb_00_reg[31:0];
     end
     if ( uart_lb_rd == 1 && uart_lb_addr[7:0] == 8'h04 ) begin
       uart_lb_rd_rdy <= 1;
       uart_lb_rd_d   <= uart_lb_04_reg[31:0];
     end
     if ( uart_lb_rd == 1 && uart_lb_addr[7:0] == 8'h08 ) begin
       uart_lb_rd_rdy <= 1;
       uart_lb_rd_d   <= uart_lb_08_reg[31:0];
     end
     if ( uart_lb_rd == 1 && uart_lb_addr[7:0] == 8'h0c ) begin
       uart_lb_rd_rdy <= 1;
       uart_lb_rd_d   <= uart_lb_0c_reg[31:0];
     end
   end

   if ( u1_lb_rd_rdy == 1 ) begin
     uart_lb_rd_rdy <= 1;
     uart_lb_rd_d   <= u1_lb_rd_d[31:0];
   end

 end // clk+reset
end // proc_uart_lb   


//-----------------------------------------------------------------------------
// A 4KByte RAM for buffering up mutiple LB writes and reads.       
//-----------------------------------------------------------------------------
lb_read_cache u0_lb_read_cache
(
  .reset                           ( reset_loc                  ),
  .clk_lb                          ( clk_ft_tree                ),
  .lb_cs                           ( ft_lb_cs_u0                ),
  .lb_wr                           ( ft_lb_wr                   ),
  .lb_rd                           ( ft_lb_rd                   ),
  .lb_addr                         ( ft_lb_addr[31:0]           ),
  .lb_wr_d                         ( ft_lb_wr_d[31:0]           ),
  .lb_rd_d                         ( u0_lb_rd_d[31:0]           ),
  .lb_rd_rdy                       ( u0_lb_rd_rdy               )
);
  assign ft_lb_cs_u0 = ( ft_lb_addr[19:16] == 4'h1 ) ? 1 : 0;


//-----------------------------------------------------------------------------
// A 4KByte RAM for buffering up mutiple LB writes and reads.       
//-----------------------------------------------------------------------------
lb_read_cache u1_lb_read_cache
(
  .reset                           ( reset_loc                  ),
  .clk_lb                          ( clk_lb_tree                ),
  .lb_cs                           ( uart_lb_cs_u1              ),
  .lb_wr                           ( uart_lb_wr                 ),
  .lb_rd                           ( uart_lb_rd                 ),
  .lb_addr                         ( uart_lb_addr[31:0]         ),
  .lb_wr_d                         ( uart_lb_wr_d[31:0]         ),
  .lb_rd_d                         ( u1_lb_rd_d[31:0]           ),
  .lb_rd_rdy                       ( u1_lb_rd_rdy               )
);
  assign uart_lb_cs_u1 = ( uart_lb_addr[19:16] == 4'h1 ) ? 1 : 0;

//-----------------------------------------------------------------------------
// CMOS IO Buffers. Data and Byte Enables are bidirectional so instantiate
//-----------------------------------------------------------------------------
genvar j;
generate
for ( j=0; j<=7; j=j+1 ) begin: gen_j
  IOBUF    u0_inout ( .IO( ft600_d[j]      ), .T( ft600_d_oe_l[j]  ),
                      .I ( ft600_d_out[j]  ), .O( ft600_d_in[j]    ));
end
endgenerate

genvar k;
generate
for ( k=0; k<=1; k=k+1 ) begin: gen_k
  IOBUF    u0_inout ( .IO( ft600_be[k]     ), .T( ft600_be_oe_l[k] ),
                      .I ( ft600_be_out[k] ), .O( ft600_be_in[k]   ));
end
endgenerate


//-----------------------------------------------------------------------------
// USB3 MesaBus to Local Bus. Interface to FT600 and create 32b Local Bus
//-----------------------------------------------------------------------------
ft600_xface u_ft600_xface
(
  .clk_ft            ( clk_ft_tree         ),
  .reset             ( reset_ft600         ),
  .dbg_ft_rd         (                     ),
  .dbg_ft_wr         (                     ),
  .ft600_txe_l       ( ft600_txe_l         ),
  .ft600_rxf_l       ( ft600_rxf_l         ),
  .ft600_d_in        ( ft600_d_in[15:0]    ),
  .ft600_d_out       ( ft600_d_out[15:0]   ),
  .ft600_d_oe_l      ( ft600_d_oe_l[15:0]  ),
  .ft600_be_in       ( ft600_be_in[1:0]    ),
  .ft600_be_out      ( ft600_be_out[1:0]   ),
  .ft600_be_oe_l     ( ft600_be_oe_l[1:0]  ),
  .ft600_oe_l        ( ft600_oe_l          ),
  .ft600_rd_l        ( ft600_rd_l          ),
  .ft600_wr_l        ( ft600_wr_l          ),

  .lb_wr             ( ft_lb_wr            ),
  .lb_rd             ( ft_lb_rd            ),
  .lb_addr           ( ft_lb_addr[31:0]    ),
  .lb_wr_d           ( ft_lb_wr_d[31:0]    ),
  .lb_rd_d           ( ft_lb_rd_d[31:0]    ),
  .lb_rd_rdy         ( ft_lb_rd_rdy        ),
  .dbg_sample        (                     ),
  .dbg_byte          (                     ),
  .dbg_nib           (                     )
);// module ft600_xface


//-----------------------------------------------------------------------------
// UART MesaBus to Local Bus. Interface to FT232 and create 32b Local Bus
//-----------------------------------------------------------------------------
ft232_xface u_ft232_xface
(
  .reset             ( reset_loc          ),
  .clk_lb            ( clk_lb_tree        ),
  .ftdi_wi           ( bd_rxd_loc         ),
  .ftdi_ro           ( bd_txd_loc         ),
  .ftdi_wo           (                    ),
  .ftdi_ri           (                    ),
  .lb_wr             ( uart_lb_wr         ),
  .lb_rd             ( uart_lb_rd         ),
  .lb_addr           ( uart_lb_addr[31:0] ),
  .lb_wr_d           ( uart_lb_wr_d[31:0] ),
  .lb_rd_d           ( uart_lb_rd_d[31:0] ),
  .lb_rd_rdy         ( uart_lb_rd_rdy     ),
  .prom_wr           (                    ),
  .prom_rd           (                    ),
  .prom_addr         (                    ),
  .prom_wr_d         (                    ),
  .prom_rd_d         ( 32'd0              ),
  .prom_rd_rdy       ( 1'b0               )
);// module ft232_xface


endmodule // top.v
