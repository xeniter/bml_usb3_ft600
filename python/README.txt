README.txt    : This file
ft600_test.py : Example Python

ft600_test.py is an example program for talking to the example FPGA design.
It first performs a data integrity check by loading 256 random dwords into 
the FPGA and reading them back in a loop 128 times.
Second, it times back to back write bursts and read bursts and reports the
performance for both in both MBytes/sec and Mbps.
To compare these numbers with theoretical maximums, multiply results by 4.
For example, if the program reports 2 MBytes/Sec, then the chip is actually
achieving 8 MBytes/Sec ( with max possible of 200 MBytes/Sec ).
The BML dual-PMOD design is 4x slower than the chip itself as:
  1) Only 8 of 16 data pins are used.
  2) ASCII is used to send binary payloads.

The Software Stack:
   User Application : Where you make 32bit Write and Read requests of Hardware.
   lb_link          : "Local Bus" : This accepts Write and Read requests of 
                       infinite size and breaks them down into HW limits and 
                       constructs Mesa Bus payloads out of them.
   mesa_bus         : Sends or Receives payloads of up to 255 bytes to 
                      specified Slot,Subslot with a Command.
   usb_ft600_link   : Sends or Receives ASCII payloads to FT600 device driver.
   
Hardware Stack :
   Hardware does the reverse, a Mesa Bus decoder parses Local Bus packets and 
   converts them to 32bit bus cycles.   

In a linear order, it looks like this:
 UserCode<->lb_link<->mesa_bus<->usb_ft600_link<->D3XX_DevDriver<->WindowsUSB..
  ->FT600_Chip<->FPGA_PMOD<->MesaBusDecoder<->LocalBusDecoder<->LocalBus
   
2017.12.18 Kevin M. Hubbard @ Black Mesa Labs
