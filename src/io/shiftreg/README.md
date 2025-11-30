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

---

## io_ShiftRegister_SIPO_Controller

A controller for Serial-In Parallel-Out (SIPO) shift registers like the 
**SN74AC596** (8-Bit Shift Register with Output Register).

### Features

- Configurable number of bits (for cascading multiple devices)
- Configurable clock frequency
- Configurable signal polarities (active low/high for latch and clear)
- Optional output synchronizers for metastability protection
- Simple start/busy/done interface
- Separate shift and storage registers in target device

### Supported Devices

- TI SN74AC596 (8-bit shift register with output register)
- TI SN74HC596 (8-bit shift register with output register)
- TI SN74HC595 (8-bit shift register with output register)
- Other compatible SIPO shift registers

### Pin Mapping for SN74AC596

| Controller Port | SN74AC596 Pin | Description |
|-----------------|---------------|-------------|
| Serial_DataOut  | SER (14)      | Serial data input |
| Serial_Clock    | SRCK (11)     | Shift register clock |
| Serial_Latch    | RCK (12)      | Storage register clock (latch) |
| Serial_Clear_n  | SCLR (10)     | Shift register clear (active low) |

### Usage Example

```vhdl
library PoC;
use     PoC.physical.all;

-- Instantiate the controller
ctrl : entity PoC.io_ShiftRegister_SIPO_Controller
    generic map (
        BITS        => 8,
        CLOCK_FREQ  => 100 MHz,
        SHIFT_FREQ  => 1 MHz
    )
    port map (
        Clock          => Clock,
        Reset          => Reset,
        Start          => WriteRequest,
        Busy           => ControllerBusy,
        Done           => WriteComplete,
        DataOut        => ParallelData,
        Serial_DataOut => SIPO_SER,
        Serial_Clock   => SIPO_SRCK,
        Serial_Latch   => SIPO_RCK,
        Serial_Clear_n => SIPO_SCLR_n
    );
```

### Timing

The controller operates as follows:
1. On `Start` assertion, it optionally clears the shift register (if configured)
2. It shifts out data MSB first, generating clock pulses for each bit
3. Data is set up on the falling edge of the shift clock
4. The target device samples data on the rising edge of the shift clock
5. After all bits are shifted, it pulses the latch signal to transfer data to outputs
6. `Done` is asserted for one clock cycle when the operation completes

### Daisy Chain Configuration

Both PISO and SIPO controllers support daisy chaining multiple shift register ICs:

```vhdl
-- Example: 24-bit SIPO chain (3 x SN74AC596)
ctrl : entity PoC.io_ShiftRegister_SIPO_Controller
    generic map (
        BITS        => 24,  -- 3 chips x 8 bits
        CLOCK_FREQ  => 100 MHz,
        SHIFT_FREQ  => 5 MHz
    )
    port map (
        -- ... ports connected to daisy-chained ICs
    );
```

---

### License

See the main PoC license file.
