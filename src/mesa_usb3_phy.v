/* ****************************************************************************
-- Source file: mesa_usb3_phy.v                
-- Date:        October 2017     
-- Author:      khubbard
-- Description: Interface the Byte ASCII stream from FTDI FT600 to Mesa-Bus   
-- Language:    Verilog-2001 
-- Simulation:  Mentor-Modelsim 
-- Synthesis:   Lattice, XST, etc
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
-- 0.1   10.01.17  khubbard Creation
-- ***************************************************************************/
`default_nettype none // Strictly enforce all nets to be declared

module mesa_usb3_phy
(
  input  wire         clk,
  input  wire         reset,
  input  wire         mesa_wi_char_en,
  input  wire [7:0]   mesa_wi_char_d,
  input  wire         mesa_wi_sim_en,
  input  wire [7:0]   mesa_wi_sim_d,
  output wire [7:0]   tx_wo_byte,
  output wire         tx_wo_rdy,
//output wire [7:0]   dbg_sump,
  output wire [4:0]   dbg_nib,

  input  wire         ro_pop_ck_en,
  output wire         ro_pop_rdy,
  input  wire         ro_pop_en,
  output wire         ro_usb_rdy,
  output wire [7:0]   ro_usb_d,

  output wire         lb_wr,
  output reg          bang_reset,
  output wire         lb_rd,
  output wire [31:0]  lb_wr_d,
  output wire [31:0]  lb_addr,
  input  wire         lb_rd_rdy,
  input  wire [31:0]  lb_rd_d 
);// module mesa_usb3_phy

  wire          mesa_wi_nib_en;
  wire [3:0]    mesa_wi_nib_d;   
  wire          mesa_wi_nib_en_muxd;
  wire [3:0]    mesa_wi_nib_d_muxd;   
  wire [7:0]    rx_loc_d;
  wire          rx_loc_rdy;
  wire          rx_loc_start;
  wire          rx_loc_stop;
  wire [7:0]    tx_lb_byte_d;
  wire          tx_lb_byte_rdy;
  wire          tx_lb_done;
  wire [7:0]    mesa_ro_byte_d;
  wire          mesa_ro_byte_en;
  wire          mesa_ro_busy;
  wire          mesa_ro_done;
  wire [7:0]    ro_char_d;
  wire          ro_char_en;
  reg           sim_ping_pong;
  reg  [3:0]    mesa_wi_sim_nib;
  reg  [3:0]    f_cnt;
  reg           reset_loc;


// ----------------------------------------------------------------------------
// Take in a binary byte every other clock and create a stream of nibbles 
// ----------------------------------------------------------------------------
always @ ( posedge clk ) begin : proc_sim
  if ( mesa_wi_sim_en == 0 ) begin 
    sim_ping_pong <= 0;
  end else begin 
    sim_ping_pong <= ~ sim_ping_pong;
    if ( sim_ping_pong == 0 ) begin 
      mesa_wi_sim_nib <= mesa_wi_sim_d[7:4];
    end else begin 
      mesa_wi_sim_nib <= mesa_wi_sim_d[3:0];
    end 
  end 
end // proc_sim


// ----------------------------------------------------------------------------
// Hold all decoders in reset until we get a string of Fs
// ----------------------------------------------------------------------------
always @ ( posedge clk or posedge reset ) begin : proc_reset
 if ( reset == 1 ) begin
   reset_loc <= 1;
   f_cnt     <= 4'd0;
 end else begin
   if ( mesa_wi_nib_en == 1 ) begin
     if ( reset_loc == 1 ) begin
       if ( mesa_wi_nib_d == 4'hF ) begin
         f_cnt <= f_cnt + 1;
         if ( f_cnt == 4'd7 ) begin
           reset_loc <= 0;
         end
       end else begin
         f_cnt <= 4'd0;
       end
     end 
   end
 end
end


//-----------------------------------------------------------------------------
// 2017.12.12 Added SW reset via Bang
//-----------------------------------------------------------------------------
always @ ( posedge clk ) begin : proc_bang_reset
  if ( mesa_wi_char_en == 1 && mesa_wi_char_d[7:0] == 8'h21 ) begin
    bang_reset <= 1;
  end else begin
    bang_reset <= 0;
  end
end


//-----------------------------------------------------------------------------
// Convert Wi ASCII to Binary Nibbles. Decoder figures out nibble/byte phase
//-----------------------------------------------------------------------------
mesa_ascii2nibble u_mesa_ascii2nibble
(
  .clk              ( clk                 ),
  .rx_char_en       ( mesa_wi_char_en     ),
  .rx_char_d        ( mesa_wi_char_d[7:0] ),
  .rx_nib_en        ( mesa_wi_nib_en      ),
  .rx_nib_d         ( mesa_wi_nib_d[3:0]  )
);// module mesa_ascii2nibble
  assign mesa_wi_nib_en_muxd     = mesa_wi_nib_en | mesa_wi_sim_en;
  assign mesa_wi_nib_d_muxd[3:0] = ( mesa_wi_sim_en == 0 ) ? 
                                     mesa_wi_nib_d[3:0] : mesa_wi_sim_nib[3:0];

  assign dbg_nib = { mesa_wi_nib_en, mesa_wi_nib_d[3:0] };


//-----------------------------------------------------------------------------
// Decode Slot Addresses : Take in the Wi path as nibbles and generate the Wo
// paths for both internal and external devices.
//-----------------------------------------------------------------------------
mesa_decode u_mesa_decode
(
  .clk              ( clk                     ),
  .reset            ( reset_loc               ),
  .rx_in_flush      ( 1'b0                    ),
  .rx_in_d          ( mesa_wi_nib_d_muxd[3:0] ),
  .rx_in_rdy        ( mesa_wi_nib_en_muxd     ),
  .rx_out_d         ( tx_wo_byte[7:0]         ),
  .rx_out_rdy       ( tx_wo_rdy               ),
  .rx_loc_d         ( rx_loc_d[7:0]           ),
  .rx_loc_rdy       ( rx_loc_rdy              ),
  .rx_loc_start     ( rx_loc_start            ),
  .rx_loc_stop      ( rx_loc_stop             )
);


//-----------------------------------------------------------------------------
// Convert Subslots 0x0 and 0xE to 32bit local bus for user logic and prom
//-----------------------------------------------------------------------------
mesa2lb u_mesa2lb
(
  .clk              ( clk                     ),
  .reset            ( reset_loc               ),
  .mode_usb3        ( 1'b1                    ),
  .rx_byte_d        ( rx_loc_d[7:0]           ),
  .rx_byte_rdy      ( rx_loc_rdy              ),
  .rx_byte_start    ( rx_loc_start            ),
  .rx_byte_stop     ( rx_loc_stop             ),
  .tx_byte_d        ( tx_lb_byte_d[7:0]       ),
  .tx_byte_rdy      ( tx_lb_byte_rdy          ),
  .tx_done          ( tx_lb_done              ),
  .tx_busy          ( 1'b0                    ),
  .lb_wr            ( lb_wr                   ),
  .lb_rd            ( lb_rd                   ),
  .lb_wr_d          ( lb_wr_d[31:0]           ),
  .lb_addr          ( lb_addr[31:0]           ),
  .lb_rd_d          ( lb_rd_d[31:0]           ),
  .lb_rd_rdy        ( lb_rd_rdy               ),
  .prom_wr          (                         ),
  .prom_rd          (                         ),
  .prom_wr_d        (                         ),
  .prom_addr        (                         ),
  .prom_rd_d        ( 32'd0                   ),
  .prom_rd_rdy      ( 1'b0                    )
);


//-----------------------------------------------------------------------------
// Convert Ro Binary Bytes to ASCII 
// tx_lb_byte_d   ----< >--< >--< >--< >----------< >--< >--< >--< >----
// tx_lb_byte_rdy ____/ \__/ \__/ \__/ \__________/ \__/ \__/ \__/ \____
// tx_lb_done     _______________________________________________/ \____
//-----------------------------------------------------------------------------
mesa_byte2ascii u0_mesa_byte2ascii
(
  .clk              ( clk                 ),
  .reset            ( reset               ),
  .no_handshake     ( 1'b1                ),
  .tx_byte_en       ( tx_lb_byte_rdy      ),
  .tx_byte_d        ( tx_lb_byte_d[7:0]   ),
  .tx_byte_busy     (                     ),
  .tx_byte_done     ( 1'b0                ),
  .tx_char_en       ( ro_char_en          ),
  .tx_char_d        ( ro_char_d[7:0]      ),
  .tx_char_busy     ( 1'b0                ),
  .tx_char_idle     ( 1'b1                ) 
);// module mesa_byte2ascii


//-----------------------------------------------------------------------------
// Convert the intermittent ro byte stream into a constant stream for USB3
//-----------------------------------------------------------------------------
mesa_ro_buffer u0_mesa_ro_buffer
(
  .clk              ( clk                 ),
  .reset            ( reset               ),
  .push_done        ( tx_lb_done          ),
  .pop_ck_en        ( ro_pop_ck_en        ),
  .pop_rdy          ( ro_pop_rdy          ),
  .pop_en           ( ro_pop_en           ),
  .din_en           ( ro_char_en          ),
  .din_d            ( ro_char_d[7:0]      ),
  .dout_rdy         ( ro_usb_rdy          ),
  .dout_d           ( ro_usb_d[7:0]       )
);

//assign dbg_sump[0] = tx_lb_byte_rdy;
//assign dbg_sump[1] = ro_char_en;
//assign dbg_sump[2] = ro_usb_rdy;
//assign dbg_sump[3] = ro_pop_rdy;
//assign dbg_sump[4] = ro_pop_en;
//assign dbg_sump[5] = rx_loc_start;
//assign dbg_sump[6] = rx_loc_rdy;
//assign dbg_sump[7] = rx_loc_stop;


endmodule // mesa_usb3_phy.v
