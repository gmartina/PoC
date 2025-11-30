# Shift Register Controllers

This directory contains controllers for various shift register ICs.

## io_ShiftRegister_PISO_Controller

A controller for Parallel-In Serial-Out (PISO) shift registers like the 
**SN74AC165-Q1** (Automotive 8-Bit Parallel Input Shift Register).

### Features

- Configurable number of bits (for cascading multiple devices)
- Configurable clock frequency
- Configurable signal polarities
- Optional input synchronizers for metastability protection
- Simple start/busy/valid interface

### Supported Devices

- TI SN74AC165-Q1 (8-bit parallel load shift register)
- TI SN74HC165 (8-bit parallel load shift register)
- Other compatible PISO shift registers

### Pin Mapping for SN74AC165-Q1

| Controller Port | SN74AC165 Pin | Description |
|-----------------|---------------|-------------|
| ShiftLoad_n     | SH/LD (1)     | Shift/Load control (active low) |
| SerialClock     | CLK (2)       | Clock input |
| ClockInhibit    | CLK INH (15)  | Clock inhibit |
| SerialIn        | SER (10)      | Serial input (for cascading) |
| SerialDataIn    | QH (9)        | Serial output |

### Usage Example

```vhdl
library PoC;
use     PoC.physical.all;

-- Instantiate the controller
ctrl : entity PoC.io_ShiftRegister_PISO_Controller
    generic map (
        BITS        => 8,
        CLOCK_FREQ  => 100 MHz,
        SHIFT_FREQ  => 1 MHz
    )
    port map (
        Clock        => Clock,
        Reset        => Reset,
        Start        => ReadRequest,
        Busy         => ControllerBusy,
        Valid        => DataValid,
        DataReceived => ParallelData,
        ShiftLoad_n  => PISO_SH_LD_n,
        SerialClock  => PISO_CLK,
        ClockInhibit => PISO_CLK_INH,
        SerialIn     => PISO_SER,
        SerialDataIn => PISO_QH
    );
```

### Timing

The controller operates as follows:
1. On `Start` assertion, it first loads parallel data by asserting `ShiftLoad_n` low
2. After the load setup time, it releases the load signal
3. It samples the first bit (QH) immediately after load
4. For remaining bits, it generates clock pulses and samples data on each falling edge
5. After all bits are shifted, `Valid` is asserted for one clock cycle

### License

See the main PoC license file.
