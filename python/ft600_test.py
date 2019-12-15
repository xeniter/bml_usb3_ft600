#!python3
###############################################################################
# Source file : ft600_test.py               
# Language    : Python 3.3 
# Author      : Kevin Hubbard    
# Description : Test script for FT600 interface 
# License     : GPLv3
#      This program is free software: you can redistribute it and/or modify
#      it under the terms of the GNU General Public License as published by
#      the Free Software Foundation, either version 3 of the License, or
#      (at your option) any later version.
#
#      This program is distributed in the hope that it will be useful,
#      but WITHOUT ANY WARRANTY; without even the implied warranty of
#      MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#      GNU General Public License for more details.
#
#      You should have received a copy of the GNU General Public License
#      along with this program.  If not, see <http://www.gnu.org/licenses/>.
#                                                               
# PySerial for Python3 from:
#   https://pypi.python.org/pypi/pyserial/
# Note: The directory this script in should also have these files (Windows)
#  o FTD3XX.dll
#  o FTD3XX.lib
#  o defines.py
# These should be available after downloading and installing from FTDIchip.com
#  o FTD3XXDriver_WHQLCertified_v1.2.0.6_Installer.exe
#  o D3XXPython_Release1.0.zip
# -----------------------------------------------------------------------------
# History :
# 2017.12.01 : khubbard : Created
###############################################################################
import sys;
import select;
import socket;
import time;
import os;
import random;
from time import sleep;

def main():
  args = sys.argv + [None]*3;
  vers = "2017.12.01";
  auth = "khubbard";
  random.seed();

  # This allow changing freq between 66 MHz and 100 MHz
  if ( True  ):
    usb_link = usb_ft600_link();
    lf = "";
    cfg = usb_link.get_cfg();
    desired_freq = 0;# 1=66 MHz, 0=100 MHz
    if ( cfg.FIFOClock != desired_freq ):
      print("Changing FT600 Frequency");
      cfg.FIFOClock = desired_freq;
      rts = usb_link.set_cfg( cfg );
      usb_link.close();
      sleep(0.5);# Chip will reset, so must wait
      usb_link = usb_ft600_link();
  else:
    print("Hey");
    usb_link = usb_ft232_link( port_name = "COM4", baudrate = 921600 );
    lf = "\n";

  mb  = mesa_bus( phy_link = usb_link, lf = lf );
  bd  = lb_link( mesa_bus = mb, slot = 0x00, subslot = 0x0 );

  # USB 2.0 FT600 @ 100 MHz 256 DWORDs = 1K Bytes
  # Writes = 9 Bursts of ~212 ASCII / ~106 Bytes
  # WR With Hub - Each Burst is 2uS wide with 1ms spacing = 125 KBytes/Sec
  # WR With no Hub - Each Burst is 2.56uS wide with 500us spacing
  # WR With no Hub - 1024 Bytes / .004 S = 250 KBytes/Sec = 8 Mbits Raw 
  # RD = 9 bursts of ~212 ASCII / ~106 Bytes in
  # RD With no Hub - 1024 Bytes / .0085 S = 120 KBytes/Sec = 4 Mbits Raw 
  #
  # USB 2.0 FT232 at 921,600
  # Read of 1Kbytes  = 272ms = 1024 / 0.272 = 3KBytes/Sec  = 
  # Write of 1Kbytes =  25ms = 1024 / 0.025 = 40KBytes/Sec = 640 kbaud raw
  # Writes occur as bursts of 29 DWORDs. Each DWORD is 86 uS apart 
  # Each group of 29 DWORDs is 280uS apart.
  # 4 Bytes / .000086 = 744Kbaud

  num_dwords = 256;

  print("Starting Test");
# rts = bd.rd( 0x0000000c, 1 )[0];
# print("%08x" % ( rts ) );
# return;

  data_list = [];
  for k in range (0, num_dwords ):
    data_list += [ random.randint(0, 0xFFFFFFFF ) ];

  k = 0;
  for i in range (0, 128 ):
    bd.wr( 0x00010000, data_list );
    rts = bd.rd( 0x00010000, num_dwords );
    if ( rts != data_list ):
      for (i,each) in enumerate( rts ):
        expect = data_list[i];
        if ( expect != each ):
          print("%d Failure %08x != %08x" % ( i, each, expect ) );
    else:
      k +=1;
      if ( k > 10 ):
#       print("." , end='', flush=True); #     print ".",
        k = 0;

  print("Measuring Performance");
  start_time = time.time();
  iterations = 128;
  for i in range (0, iterations ):
    bd.wr( 0x00010000, data_list );
  stop_time = time.time();
  wr_rate = ( iterations * num_dwords * 4.0 ) / ( stop_time - start_time );
  wr_rate = wr_rate / 1000000.0;# Conv Byte to MBytes
  print("Writes at %.03f MB/sec ( or %.03f Mbps )" % ( wr_rate, wr_rate*8 ) );

  start_time = time.time();
  for i in range (0, iterations ):
    rts = bd.rd( 0x00010000, num_dwords );
  stop_time = time.time();
  rd_rate = ( iterations * num_dwords * 4.0 ) / ( stop_time - start_time );
  rd_rate = rd_rate / 1000000.0;# Conv Byte to MBytes
  print("Reads at %.03f MB/sec ( or %.03f Mbps )" % ( rd_rate, rd_rate*8 ) );
    
  return;


###############################################################################
# Protocol interface for MesaBus over a FTDI USB3 connection.
class lb_link:
  def __init__ ( self, mesa_bus, slot, subslot ):
    self.mesa_bus = mesa_bus;
    self.slot      = slot;
    self.subslot   = subslot;
    self.dbg_flag  = False;

  def wr_repeat(self, addr, data_list ):
    self.wr( addr, data_list, repeat = True );

  def wr(self, addr, data_list, repeat = False ):
    # LocalBus WR cycle is a Addr+Data payload
    # Mesabus has maximum payload of 255 bytes, or 63 DWORDs.
    # 1 DWORD is LB Addr, leaving 62 DWORDs available for data bursts
    # if data is more than 62 dwords, parse it down into multiple bursts
    each_addr = addr;
    if ( repeat == False ):
      mb_cmd = 0x0;# Burst Write
    else:
      mb_cmd = 0x2;# Write Repeat ( Multiple data to same address - FIFO like )

    # Warning: Payloads greater than 29 can result with corruptions on FT600, 
    # Example 0x11111111 becomes 0x1111111F. 
    #    1 DWORD of MesaBus Header
    #    1 DWORD of LB Addr
    #   30 DWORD of LB Data
    #  ------
    #   32 DWORDs = 128 Binary Bytes = 256 ASCII Nibbles = 512 FT600 Bytes
    max_payload_len = 29;
    while ( len( data_list ) > 0 ):
      if ( len( data_list ) > max_payload_len ):
        data_payload = data_list[0:max_payload_len];
        data_list    = data_list[max_payload_len:];
      else:
        data_payload = data_list[0:];
        data_list    = [];
      payload = ( "%08x" % each_addr );
      for each_data in data_payload:
        payload += ( "%08x" % each_data );
        if ( repeat == False ):
          each_addr +=4;# maintain address for splitting into 62 DWORD bursts
#     print("MB.wr :" + payload );
      self.mesa_bus.wr( self.slot, self.subslot, mb_cmd, payload );
    return;

  def wr_packet(self, addr_data_list ):
    # FT600 has a 1024 byte limit. My 8bit interface halves that to 512 bytes
    # and send ASCII instead of binary, so 256
    max_packet_len = 30;
    while ( len( addr_data_list ) > 0 ):
      if ( len( addr_data_list ) > max_packet_len ):
        data_payload   = addr_data_list[0:max_packet_len];
        addr_data_list = addr_data_list[max_packet_len:];
      else:
        data_payload   = addr_data_list[0:];
        addr_data_list = [];
      payload = "";
      for each_data in data_payload:
        payload += ( "%08x" % each_data );
      mb_cmd = 0x4;# Write Packet
#     print("MB.wr :" + payload );
      self.mesa_bus.wr( self.slot, self.subslot, mb_cmd, payload );
    return;

  def rd_repeat(self, addr, num_dwords ):
    rts = self.rd( addr, num_dwords+1, repeat = True );
    return rts;

  def rd(self, addr, num_dwords, repeat = False ):
    max_payload = 31;
    if ( num_dwords <= max_payload ):
      rts = self.rd_raw( addr, num_dwords );
    else:
      # MesaBus has 63 DWORD payload limit, so split up into multiple reads
      dwords_remaining = num_dwords;
      rts = [];
      while( dwords_remaining > 0 ):
        if ( dwords_remaining <= max_payload ):
          rts += self.rd_raw( addr, dwords_remaining );
          dwords_remaining = 0;
        else:
          rts += self.rd_raw( addr, max_payload );
          dwords_remaining -= max_payload;
          addr += max_payload*4;# Note Byte Addressing
    return rts;

  def rd_raw(self, addr, num_dwords, repeat = False ):
    dwords_remaining = num_dwords;
    each_addr = addr;
    if ( repeat == False ):
      mb_cmd = 0x1;# Normal Read
    else:
      mb_cmd = 0x3;# Read  Repeat ( Multiple data to same address )

    # LocalBus RD cycle is a Addr+Len 8byte payload to 0x00,0x0,0x1
    payload = ( "%08x" % each_addr ) + ( "%08x" % num_dwords );
#   print("MB.wr :" + payload );
    self.mesa_bus.wr( self.slot, self.subslot, mb_cmd, payload );
    rts_str = self.mesa_bus.rd( num_dwords = num_dwords );
#   print("MB.rd :" + rts_str );

    rts = [];
    if ( len( rts_str ) >= 8 ):
      while ( len( rts_str ) >= 8 ):
        rts_dword = rts_str[0:8];
        rts_str   = rts_str[8:];
#       print("MB.rd :" + rts_dword );
        try:
          rts += [ int( rts_dword, 16 ) ];
        except:
          addr_str = "%08x" % each_addr;
          print("ERROR: Invalid LocalBus Read >" +
                 addr_str + "< >" + rts_mesa + "< >" + rts_dword + "<");
          if ( self.dbg_flag == "debug" ):
            sys.exit();
          rts += [ 0xdeadbeef ];
    else:
      print("ERROR: Invalid LocalBus Read >" + rts_str + "<");
      rts += [ 0xdeadbeef ];
    return rts;


###############################################################################
# Routines for Reading and Writing Payloads over MesaBus
# A payload is a series of bytes in hexadecimal string format. A typical use
# for MesaBus is to transport a higher level protocol like Local Bus for 32bit
# writes and reads. MesaBus is lower level and transports payloads to a
# specific device on a serial chained bus based on the Slot Number.
# More info at : https://blackmesalabs.wordpress.com/2016/03/04/mesa-bus/
#  0x0 : Write Cycle    : Payload of <ADDR><DATA>...
#  0x1 : Read  Cycle    : Payload of <ADDR><Length> 
#  0x2 : Write Repeat   : Write burst data to single address : <ADDR><DATA>...
#  0x3 : Read  Repeat   : Read burst data from single address : <ADDR><Length> 
#  0x4 : Write Multiple : Payload of <ADDR><DATA><ADDR><DATA><ADDR><DATA>..

class mesa_bus:
  def __init__ ( self, phy_link, lf ):
    self.phy_link = phy_link;
# Note: type() doesn't work right in Python2, so tossed
#    if ( type( phy_link ) == usb_ft232_link ):
#      self.lf = "\n";
#    else:
#      self.lf = "";
    self.lf = lf;
    self.phy_link.wr( self.lf );
    self.phy_link.wr("FFFFFFFF" + self.lf );# HW releases from Reset after 8 0xFs

  def wr( self, slot, subslot, cmd, payload ):
#   preamble  = "F0";
    preamble  = "FFF0";
    slot      = "%02x" % slot;
    subslot   = "%01x" % subslot;
    cmd       = "%01x" % cmd;
    num_bytes = "%02x" % int( len( payload ) / 2 );
    mesa_str  = preamble + slot + subslot + cmd + num_bytes + payload + self.lf;
    self.phy_link.wr( mesa_str );
    return;

  def rd( self, num_dwords ):
    #   "F0FE0004"+"12345678"
    #   "04" is num payload bytes and "12345678" is the read payload
    rts = self.phy_link.rd( bytes_to_read = (1+num_dwords)*4 );
    if ( len( rts ) > 8 ):
      rts = rts[8:];# Strip the "FOFE0004" header
    return rts;


###############################################################################
# Serial port class for sending and receiving ASCII strings to FT232RL UART
# Note - isn't ft232 specific, should work with any generic USB to UART chip
class usb_ft232_link:
  def __init__ ( self, port_name, baudrate ):
    try:
      import serial;
    except:
      raise RuntimeError("ERROR: PySerial from sourceforge.net is required");
      raise RuntimeError(
         "ERROR: Unable to import serial\n"+
         "PySerial from sourceforge.net is required for Serial Port access.");
    try:
      self.ser = serial.Serial( port=port_name, baudrate=baudrate,
                               bytesize=8, parity='N', stopbits=1,
                               timeout=1, xonxoff=0, rtscts=0,dsrdtr=0);
      self.port = port_name;
      self.baud = baudrate;
      self.ser.flushOutput();
      self.ser.flushInput();
      self.ack_state = True;
    except:
      raise RuntimeError("ERROR: Unable to open USB COM Port "+port_name)

  def rd( self, bytes_to_read ):
    rts = self.ser.readline();
    return rts;

  def wr( self, str ):
    self.ser.write( str.encode("utf-8") );
    return;

  def close(self):
    self.ser.close();
    return;


###############################################################################
# class for sending and receiving ASCII strings to FTDI FT600 chip 
# Note: Look at ftd3xx.py for list of functions in Python
class usb_ft600_link:
  def __init__ ( self ):
    try:
      import ftd3xx
      import sys
      if sys.platform == 'win32':
        import ftd3xx._ftd3xx_win32 as _ft
      elif sys.platform == 'linux2':
        import ftd3xx._ftd3xx_linux as _ft
    except:
      raise RuntimeError("ERROR: FTD3XX from FTDIchip.com is required");
      raise RuntimeError(
         "ERROR: Unable to import serial\n"+
         "PySerial from sourceforge.net is required for Serial Port access.");
    try:
      # check connected devices
      numDevices = ftd3xx.createDeviceInfoList()
      if (numDevices == 0):
        print("ERROR: No FTD3XX device is detected.");
        return False;
      devList = ftd3xx.getDeviceInfoList()

      # Just open the first device (index 0)
      devIndex = 0;
      self.D3XX = ftd3xx.create(devIndex, _ft.FT_OPEN_BY_INDEX);
       
      if (self.D3XX is None):
        print("ERROR: Please check if another D3XX application is open!");
        return False;

      # Reset the FT600 to make sure starting fresh with nothing in FIFOs
      self.D3XX.resetDevicePort(); # Flush
      self.D3XX.close();
      self.D3XX = ftd3xx.create(devIndex, _ft.FT_OPEN_BY_INDEX);

      # check if USB3 or USB2
      devDesc = self.D3XX.getDeviceDescriptor();
      bUSB3 = devDesc.bcdUSB >= 0x300;

      # validate chip configuration
      cfg = self.D3XX.getChipConfiguration();

      # Timeout is in ms,0=Blocking. Defaults to 5,000
#     rts = self.D3XX.setPipeTimeout( pipeid = 0xFF, timeoutMS = 0 );
      rts = self.D3XX.setPipeTimeout( pipeid = 0xFF, timeoutMS = 1000 );

    # process loopback for all channels
    except:
      raise RuntimeError("ERROR: Unable to open USB Port " );
    return;

  def get_cfg( self ):
    cfg = self.D3XX.getChipConfiguration();
    return cfg;

  def set_cfg( self, cfg ):
    rts = self.D3XX.setChipConfiguration(cfg);
    return rts;

  def rd( self, bytes_to_read ):
    bytes_to_read = bytes_to_read * 4;# Only using 8 of 16bit of FT600, ASCII
    channel = 0;
    rx_pipe = 0x82 + channel;
    if sys.platform == 'linux2':
      rx_pipe -= 0x82;
    output = self.D3XX.readPipeEx( rx_pipe, bytes_to_read );
    xferd = output['bytesTransferred']
    if sys.version_info.major == 3:
      buff_read = output['bytes'].decode('latin1');
    else:
      buff_read = output['bytes'];

    while (xferd != bytes_to_read ):
      status = self.D3XX.getLastError()
      if (status != 0):
        print("ERROR READ %d (%s)" % (status,self.D3XX.getStrError(status)));
        if sys.platform == 'linux2':
          return self.D3XX.flushPipe(pipe);
        else:
          return self.D3XX.abortPipe(pipe);
      output = self.D3XX.readPipeEx( rx_pipe, bytes_to_read - xferd );
      status = self.D3XX.getLastError()
      xferd += output['bytesTransferred']
      if sys.version_info.major == 3:
        buff_read += output['bytes'].decode('latin1')
      else:
        buff_read += output['bytes']
    return buff_read[0::2];# Return every other ch as using 8 of 16 FT600 bits

  def wr( self, str ):
    str = "~".join( str );# only using 8bits of 16bit FT600, so pad with ~
    bytes_to_write = len( str );# str is now "~1~2~3 .. ~e~f" - Twice as long
    channel = 0;
    result = False;
    timeout = 5;
    tx_pipe = 0x02 + channel;
    if sys.platform == 'linux2':
      tx_pipe -= 0x02;
    if ( sys.version_info.major == 3 ):
      str = str.encode('latin1');
    xferd = 0
    while ( xferd != bytes_to_write ):
      # write data to specified pipe
      xferd += self.D3XX.writePipe(tx_pipe,str,bytes_to_write-xferd);
    return;

  def close(self):
    self.D3XX.resetDevicePort(); # Flush anything in chip
    self.D3XX.close();
    self.D3XX = 0;
    return;

###############################################################################
try:
  if __name__=='__main__': main()
except KeyboardInterrupt:
  print('Break!')
# EOF
