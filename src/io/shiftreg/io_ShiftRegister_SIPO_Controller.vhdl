-- EMACS settings: -*-  tab-width: 2; indent-tabs-mode: t -*-
-- vim: tabstop=2:shiftwidth=2:noexpandtab
-- kate: tab-width 2; replace-tabs off; indent-width 2;
-- =============================================================================
-- Authors:         Gustavo Martin
--
-- Entity:          io_ShiftRegister_SIPO_Controller
--
-- Description:
-- -------------------------------------
-- Controller for Serial-In Parallel-Out (SIPO) shift registers like the
-- SN74AC596 or similar devices.
--
-- This controller handles the timing and sequencing for writing data to
-- external SIPO shift register ICs. It generates:
--   - Serial data output (SER)
--   - Shift clock (SRCK) - shifts data into register on rising edge
--   - Latch/Storage clock (RCK) - transfers shift register to output on rising edge
--   - Clear signal (SCLR_n) - clears shift register when low
--
-- Operation sequence:
--   1. Assert Start with DataToSend valid
--   2. Controller shifts out MSB first via SER with SRCK pulses
--   3. After all bits shifted, pulse RCK to latch data to outputs
--   4. Assert Valid and Done when complete
--
-- For daisy-chained configurations, set BITS to total bit count (e.g., 24 for 3 IC).
-- Data is shifted MSB first, so the last chip in the chain receives its data first.
--
-- Generics:
--   BITS                    - Number of bits to shift out (8 for single, 24 for 3-chip chain)
--   ACTIVE_LOW_CLEAR        - TRUE if SCLR_n is active low (typical)
--   ACTIVE_LOW_SERIAL_OUT   - TRUE if SER output should be active low
--   ACTIVE_LOW_LATCH        - TRUE if RCK is active low
--   ACTIVE_LOW_SHIFT_CLK    - TRUE if SRCK is active low
--   CLOCK_FREQ              - System clock frequency
--   SHIFT_FREQ              - Desired shift clock frequency
--   ADD_OUTPUT_REGISTERS    - Add output registers for cleaner timing
--
-- License:
-- =============================================================================
-- Copyright 2025-2025 The PoC-Library Authors
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--    http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
-- =============================================================================

library IEEE;
use     IEEE.std_logic_1164.all;
use     IEEE.numeric_std.all;

library PoC;
use     PoC.utils.all;
use     PoC.physical.all;


entity io_ShiftRegister_SIPO_Controller is
	generic (
		BITS                    : positive := 8;
		ACTIVE_LOW_CLEAR        : boolean  := TRUE;
		ACTIVE_LOW_SERIAL_OUT   : boolean  := FALSE;
		ACTIVE_LOW_LATCH        : boolean  := FALSE;
		ACTIVE_LOW_SHIFT_CLK    : boolean  := FALSE;
		CLOCK_FREQ              : FREQ     := 100 MHz;
		SHIFT_FREQ              : FREQ     := 5 MHz;
		ADD_OUTPUT_REGISTERS    : boolean  := FALSE
	);
	port (
		-- System signals
		Clock       : in  std_logic;
		Reset       : in  std_logic;

		-- User interface
		Start       : in  std_logic;
		Busy        : out std_logic;
		Done        : out std_logic;
		DataToSend  : in  std_logic_vector(BITS - 1 downto 0);

		-- Shift register interface (directly active/directly active, active low controlled via generics)
		SerialOut   : out std_logic;  -- SER: Serial data output to shift register
		ShiftClock  : out std_logic;  -- SRCK: Shift register clock
		LatchClock  : out std_logic;  -- RCK: Storage/latch register clock
		Clear_n     : out std_logic   -- SCLR_n: Shift register clear (directly active low compatible)
	);
end entity;


architecture rtl of io_ShiftRegister_SIPO_Controller is
	-- Calculate timing parameters
	-- Full period of shift clock in system clock cycles
	constant SHIFT_PERIOD_CYCLES : positive := TimingToCycles(to_time(SHIFT_FREQ), CLOCK_FREQ);
	-- Half period of shift clock in system clock cycles
	constant HALF_PERIOD_CYCLES  : positive := maximum(SHIFT_PERIOD_CYCLES / 2, 1);
	constant TIMER_BITS          : positive := log2ceilnz(HALF_PERIOD_CYCLES + 1);
	constant BIT_COUNTER_BITS    : positive := log2ceilnz(BITS + 1);

	-- State machine states
	type T_STATE is (
		ST_IDLE,              -- Waiting for Start
		ST_LOAD,              -- Load shift register with data
		ST_SHIFT_SETUP,       -- Setup serial data, wait for timing
		ST_SHIFT_CLOCK_HIGH,  -- SRCK high period
		ST_SHIFT_CLOCK_LOW,   -- SRCK low period, prepare next bit
		ST_LATCH_SETUP,       -- Setup before latch clock
		ST_LATCH_CLOCK_HIGH,  -- RCK high period - latch data to outputs
		ST_LATCH_CLOCK_LOW,   -- RCK low period
		ST_COMPLETE           -- Signal completion
	);

	-- State machine signals
	signal State      : T_STATE := ST_IDLE;
	signal NextState  : T_STATE;

	-- Timing counter
	signal Timer      : unsigned(TIMER_BITS - 1 downto 0) := (others => '0');
	signal TimerDone  : std_logic;

	-- Bit counter (counts down from BITS-1 to 0)
	signal BitCounter : unsigned(BIT_COUNTER_BITS - 1 downto 0) := (others => '0');

	-- Shift register for data to send
	signal ShiftReg   : std_logic_vector(BITS - 1 downto 0) := (others => '0');

	-- Internal output signals (directly active, active low handled at output)
	signal SerialOut_i   : std_logic := '0';
	signal ShiftClock_i  : std_logic := '0';
	signal LatchClock_i  : std_logic := '0';
	signal Clear_n_i     : std_logic := '1';
	signal Busy_i        : std_logic := '0';
	signal Done_i        : std_logic := '0';

begin
	-- ==========================================================================
	-- Timer: Counts system clock cycles for shift clock timing
	-- ==========================================================================
	TimerDone <= '1' when Timer = 0 else '0';

	-- ==========================================================================
	-- Main State Machine (Single clocked process)
	-- ==========================================================================
	process(Clock)
	begin
		if rising_edge(Clock) then
			if Reset = '1' then
				State        <= ST_IDLE;
				Timer        <= (others => '0');
				BitCounter   <= (others => '0');
				ShiftReg     <= (others => '0');
				SerialOut_i  <= '0';
				ShiftClock_i <= '0';
				LatchClock_i <= '0';
				Clear_n_i    <= '1';
				Busy_i       <= '0';
				Done_i       <= '0';
			else
				-- Default: clear done signal
				Done_i <= '0';

				case State is
					when ST_IDLE =>
						Busy_i       <= '0';
						ShiftClock_i <= '0';
						LatchClock_i <= '0';
						Clear_n_i    <= '1';
						SerialOut_i  <= '0';

						if Start = '1' then
							State  <= ST_LOAD;
							Busy_i <= '1';
						end if;

					when ST_LOAD =>
						-- Load the shift register with data to send
						ShiftReg   <= DataToSend;
						BitCounter <= to_unsigned(BITS - 1, BIT_COUNTER_BITS);
						Timer      <= to_unsigned(HALF_PERIOD_CYCLES - 1, TIMER_BITS);
						State      <= ST_SHIFT_SETUP;

					when ST_SHIFT_SETUP =>
						-- Setup serial data (MSB first)
						SerialOut_i  <= ShiftReg(BITS - 1);
						ShiftClock_i <= '0';

						if Timer = 0 then
							Timer <= to_unsigned(HALF_PERIOD_CYCLES - 1, TIMER_BITS);
							State <= ST_SHIFT_CLOCK_HIGH;
						else
							Timer <= Timer - 1;
						end if;

					when ST_SHIFT_CLOCK_HIGH =>
						-- SRCK high - data is shifted into register on this rising edge
						ShiftClock_i <= '1';

						if Timer = 0 then
							Timer <= to_unsigned(HALF_PERIOD_CYCLES - 1, TIMER_BITS);
							State <= ST_SHIFT_CLOCK_LOW;
						else
							Timer <= Timer - 1;
						end if;

					when ST_SHIFT_CLOCK_LOW =>
						-- SRCK low - prepare for next bit
						ShiftClock_i <= '0';

						if Timer = 0 then
							if BitCounter = 0 then
								-- All bits shifted, proceed to latch
								Timer <= to_unsigned(HALF_PERIOD_CYCLES - 1, TIMER_BITS);
								State <= ST_LATCH_SETUP;
							else
								-- More bits to shift
								BitCounter <= BitCounter - 1;
								ShiftReg   <= ShiftReg(BITS - 2 downto 0) & '0';  -- Shift left
								Timer      <= to_unsigned(HALF_PERIOD_CYCLES - 1, TIMER_BITS);
								State      <= ST_SHIFT_SETUP;
							end if;
						else
							Timer <= Timer - 1;
						end if;

					when ST_LATCH_SETUP =>
						-- Setup time before latch clock
						LatchClock_i <= '0';

						if Timer = 0 then
							Timer <= to_unsigned(HALF_PERIOD_CYCLES - 1, TIMER_BITS);
							State <= ST_LATCH_CLOCK_HIGH;
						else
							Timer <= Timer - 1;
						end if;

					when ST_LATCH_CLOCK_HIGH =>
						-- RCK high - data is latched to output registers
						LatchClock_i <= '1';

						if Timer = 0 then
							Timer <= to_unsigned(HALF_PERIOD_CYCLES - 1, TIMER_BITS);
							State <= ST_LATCH_CLOCK_LOW;
						else
							Timer <= Timer - 1;
						end if;

					when ST_LATCH_CLOCK_LOW =>
						-- RCK low
						LatchClock_i <= '0';

						if Timer = 0 then
							State <= ST_COMPLETE;
						else
							Timer <= Timer - 1;
						end if;

					when ST_COMPLETE =>
						-- Signal completion
						Done_i       <= '1';
						Busy_i       <= '0';
						ShiftClock_i <= '0';
						LatchClock_i <= '0';
						State        <= ST_IDLE;

				end case;
			end if;
		end if;
	end process;

	-- ==========================================================================
	-- Output assignments with polarity control
	-- ==========================================================================

	-- Apply active-low polarity if configured
	gen_serial_out : if ADD_OUTPUT_REGISTERS generate
		process(Clock)
		begin
			if rising_edge(Clock) then
				if ACTIVE_LOW_SERIAL_OUT then
					SerialOut <= not SerialOut_i;
				else
					SerialOut <= SerialOut_i;
				end if;
			end if;
		end process;
	else generate
		SerialOut <= not SerialOut_i when ACTIVE_LOW_SERIAL_OUT else SerialOut_i;
	end generate;

	gen_shift_clock : if ADD_OUTPUT_REGISTERS generate
		process(Clock)
		begin
			if rising_edge(Clock) then
				if ACTIVE_LOW_SHIFT_CLK then
					ShiftClock <= not ShiftClock_i;
				else
					ShiftClock <= ShiftClock_i;
				end if;
			end if;
		end process;
	else generate
		ShiftClock <= not ShiftClock_i when ACTIVE_LOW_SHIFT_CLK else ShiftClock_i;
	end generate;

	gen_latch_clock : if ADD_OUTPUT_REGISTERS generate
		process(Clock)
		begin
			if rising_edge(Clock) then
				if ACTIVE_LOW_LATCH then
					LatchClock <= not LatchClock_i;
				else
					LatchClock <= LatchClock_i;
				end if;
			end if;
		end process;
	else generate
		LatchClock <= not LatchClock_i when ACTIVE_LOW_LATCH else LatchClock_i;
	end generate;

	gen_clear : if ADD_OUTPUT_REGISTERS generate
		process(Clock)
		begin
			if rising_edge(Clock) then
				if ACTIVE_LOW_CLEAR then
					Clear_n <= Clear_n_i;  -- Already active low internally
				else
					Clear_n <= not Clear_n_i;
				end if;
			end if;
		end process;
	else generate
		Clear_n <= Clear_n_i when ACTIVE_LOW_CLEAR else not Clear_n_i;
	end generate;

	-- Status outputs
	Busy <= Busy_i;
	Done <= Done_i;

end architecture;
