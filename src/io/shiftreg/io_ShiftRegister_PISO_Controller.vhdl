-- EMACS settings: -*-  tab-width: 2; indent-tabs-mode: t -*-
-- vim: tabstop=2:shiftwidth=2:noexpandtab
-- kate: tab-width 2; replace-tabs off; indent-width 2;
-- =============================================================================
-- Authors:         Gustavo Martin
--
-- Entity:          io_ShiftRegister_PISO_Controller
--
-- Description:
-- -------------------------------------
-- This module provides a controller for Parallel-In Serial-Out (PISO) shift
-- registers like the SN74AC165-Q1 (8-bit parallel load shift register).
--
-- The controller generates the appropriate timing signals to:
--   1. Assert the parallel load signal (SH_LD_n) to load parallel data
--   2. Generate clock pulses to shift data out serially
--   3. Sample the serial data output (QH) on each clock edge
--
-- The SN74AC165-Q1 has the following interface:
--   - SH/LD_n (Shift/Load): When LOW, parallel data A-H is loaded into the
--     shift register. When HIGH, shift operation occurs on rising CLK edge.
--   - CLK (Clock): Positive-edge triggered clock for shifting
--   - CLK_INH (Clock Inhibit): When HIGH, clocking is disabled
--   - SER (Serial Input): Serial data input for cascading multiple devices
--   - A-H (Parallel Inputs): 8-bit parallel data input
--   - QH (Serial Output): Serial data output (directly from flip-flop H)
--   - QH_n (Complementary Output): Inverted serial data output
--
-- Operation:
--   The controller starts a transaction when Start is asserted. It first loads
--   the parallel data by asserting SH_LD_n LOW, then shifts out the data bit
--   by bit on successive clock pulses. The received serial data is collected
--   in an internal shift register and presented on DataReceived when Valid
--   is asserted.
--
-- Generic Parameters:
--   BITS              - Number of bits to shift (typically 8 for one device)
--   ACTIVE_LOW_SHIFTN - Whether SH/LD signal is active low (default TRUE)
--   ACTIVE_LOW_CLKINH - Whether CLK_INH signal is active low (default FALSE)
--   ACTIVE_LOW_DATA   - Whether QH data is active low (default FALSE)
--   CLOCK_FREQ        - System clock frequency
--   SHIFT_FREQ        - Shift register clock frequency (max 90 MHz for AC165)
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
use     IEEE.STD_LOGIC_1164.all;
use     IEEE.NUMERIC_STD.all;

use     work.utils.all;
use     work.physical.all;


entity io_ShiftRegister_PISO_Controller is
	generic (
		BITS                    : positive := 8;       -- Number of bits to shift
		ACTIVE_LOW_LOAD         : boolean  := TRUE;    -- SH/LD_n is active low
		ACTIVE_LOW_CLK_INHIBIT  : boolean  := FALSE;   -- CLK_INH is active low
		ACTIVE_LOW_DATA         : boolean  := FALSE;   -- QH data is active low
		ACTIVE_LOW_SERIAL_IN    : boolean  := FALSE;   -- SER input is active low
		CLOCK_FREQ              : FREQ     := 100 MHz; -- System clock frequency
		SHIFT_FREQ              : FREQ     := 1 MHz;   -- Shift clock frequency
		ADD_INPUT_SYNCHRONIZERS : boolean  := TRUE     -- Add synchronizers for inputs
	);
	port (
		-- System interface
		Clock           : in  std_logic;                              -- System clock
		Reset           : in  std_logic;                              -- Synchronous reset

		-- Control interface
		Start           : in  std_logic;                              -- Start transaction
		Busy            : out std_logic;                              -- Controller is busy
		Valid           : out std_logic;                              -- DataReceived is valid
		DataReceived    : out std_logic_vector(BITS - 1 downto 0);    -- Received parallel data

		-- Shift register interface (directly to chip pins)
		ShiftLoad_n     : out std_logic;                              -- SH/LD_n pin
		SerialClock     : out std_logic;                              -- CLK pin
		ClockInhibit    : out std_logic;                              -- CLK_INH pin
		SerialIn        : out std_logic;                              -- SER pin (for cascading)
		SerialDataIn    : in  std_logic                               -- QH pin input
	);
end entity io_ShiftRegister_PISO_Controller;


architecture rtl of io_ShiftRegister_PISO_Controller is
	-- State machine states
	type T_STATE is (
		ST_IDLE,            -- Idle, waiting for Start
		ST_LOAD,            -- Assert parallel load
		ST_LOAD_WAIT,       -- Wait for load timing
		ST_SAMPLE_FIRST,    -- Sample first bit (QH valid after load)
		ST_SHIFT_CLOCK_HIGH,-- Clock high phase
		ST_SHIFT_CLOCK_LOW, -- Clock low phase
		ST_SAMPLE_BIT,      -- Sample data bit
		ST_COMPLETE         -- Transaction complete
	);

	-- Calculate timing parameters
	-- Clock divider for shift frequency (half period for 50% duty cycle)
	constant SHIFT_PERIOD_CYCLES : positive := TimingToCycles(to_time(SHIFT_FREQ), CLOCK_FREQ);
	constant HALF_PERIOD_CYCLES  : positive := maximum(SHIFT_PERIOD_CYCLES / 2, 1);
	constant TIMER_BITS          : positive := log2ceilnz(HALF_PERIOD_CYCLES + 1);
	constant BIT_COUNTER_BITS    : positive := log2ceilnz(BITS + 1);

	-- State register
	signal State      : T_STATE := ST_IDLE;

	-- Timer for clock generation
	signal Timer      : unsigned(TIMER_BITS - 1 downto 0) := (others => '0');
	signal TimerDone  : std_logic;

	-- Bit counter (counts down from BITS-1 to 0)
	signal BitCounter : unsigned(BIT_COUNTER_BITS - 1 downto 0) := (others => '0');

	-- Shift register for received data
	signal ShiftReg   : std_logic_vector(BITS - 1 downto 0) := (others => '0');

	-- Internal signals for outputs
	signal ShiftLoad_n_s   : std_logic := '1';
	signal SerialClock_s   : std_logic := '0';
	signal ClockInhibit_s  : std_logic := '1';
	signal SerialIn_s      : std_logic := '0';
	signal Valid_s         : std_logic := '0';
	signal Busy_s          : std_logic := '0';

	-- Synchronized serial data input
	signal SerialDataIn_sync : std_logic;

begin
	-- Input synchronizer for SerialDataIn
	genSync : if ADD_INPUT_SYNCHRONIZERS generate
		i_sync_Bits : entity work.sync_Bits
			generic map (
				BITS => 1
			)
			port map (
				Clock     => Clock,
				Input(0)  => SerialDataIn,
				Output(0) => SerialDataIn_sync
			);
	end generate;

	g_NoSync : if not ADD_INPUT_SYNCHRONIZERS generate
		SerialDataIn_sync <= SerialDataIn;
	end generate;

	-- Timer done signal
	TimerDone <= '1' when Timer = 0 else '0';

	-- Main state machine process (single process style for clarity)
	process(Clock)
		variable DataBit : std_logic;
	begin
		if rising_edge(Clock) then
			if Reset = '1' then
				State          <= ST_IDLE;
				Timer          <= (others => '0');
				BitCounter     <= (others => '0');
				ShiftReg       <= (others => '0');
				ShiftLoad_n_s  <= '1';
				SerialClock_s  <= '0';
				ClockInhibit_s <= '1';
				Valid_s        <= '0';
				Busy_s         <= '0';
			else
				-- Default: clear single-cycle signals
				Valid_s <= '0';

				-- Timer countdown
				if Timer > 0 then
					Timer <= Timer - 1;
				end if;

				case State is
					when ST_IDLE =>
						ShiftLoad_n_s  <= '1';
						SerialClock_s  <= '0';
						ClockInhibit_s <= '1';
						Busy_s         <= '0';

						if Start = '1' then
							State      <= ST_LOAD;
							Busy_s     <= '1';
							BitCounter <= to_unsigned(BITS - 1, BitCounter'length);
						end if;

					when ST_LOAD =>
						-- Assert parallel load (directly, then wait)
						ShiftLoad_n_s  <= '0';
						ClockInhibit_s <= '1';
						SerialClock_s  <= '0';
						Busy_s         <= '1';
						Timer          <= to_unsigned(HALF_PERIOD_CYCLES - 1, Timer'length);
						State          <= ST_LOAD_WAIT;

					when ST_LOAD_WAIT =>
						-- Keep load asserted while waiting
						ShiftLoad_n_s  <= '0';
						ClockInhibit_s <= '1';
						SerialClock_s  <= '0';
						Busy_s         <= '1';

						if TimerDone = '1' then
							-- Release load, data is now loaded
							ShiftLoad_n_s <= '1';
							Timer         <= to_unsigned(HALF_PERIOD_CYCLES - 1, Timer'length);
							State         <= ST_SAMPLE_FIRST;
						end if;

					when ST_SAMPLE_FIRST =>
						-- Wait for QH to stabilize after load release, then sample
						ShiftLoad_n_s  <= '1';
						ClockInhibit_s <= '0';
						SerialClock_s  <= '0';
						Busy_s         <= '1';

						if TimerDone = '1' then
							-- Sample first bit (MSB)
							if ACTIVE_LOW_DATA then
								DataBit := not SerialDataIn_sync;
							else
								DataBit := SerialDataIn_sync;
							end if;
							ShiftReg <= ShiftReg(BITS - 2 downto 0) & DataBit;

							if BitCounter = 0 then
								-- Only 1 bit to read, we're done
								State <= ST_COMPLETE;
							else
								BitCounter <= BitCounter - 1;
								Timer      <= to_unsigned(HALF_PERIOD_CYCLES - 1, Timer'length);
								State      <= ST_SHIFT_CLOCK_HIGH;
							end if;
						end if;

					when ST_SHIFT_CLOCK_HIGH =>
						-- Clock high phase - this shifts the register in the chip
						ShiftLoad_n_s  <= '1';
						SerialClock_s  <= '1';
						ClockInhibit_s <= '0';
						Busy_s         <= '1';

						if TimerDone = '1' then
							Timer <= to_unsigned(HALF_PERIOD_CYCLES - 1, Timer'length);
							State <= ST_SHIFT_CLOCK_LOW;
						end if;

					when ST_SHIFT_CLOCK_LOW =>
						-- Clock low phase - wait for data to stabilize
						ShiftLoad_n_s  <= '1';
						SerialClock_s  <= '0';
						ClockInhibit_s <= '0';
						Busy_s         <= '1';

						if TimerDone = '1' then
							State <= ST_SAMPLE_BIT;
						end if;

					when ST_SAMPLE_BIT =>
						-- Sample the data bit
						ShiftLoad_n_s  <= '1';
						SerialClock_s  <= '0';
						ClockInhibit_s <= '0';
						Busy_s         <= '1';

						-- Sample bit
						if ACTIVE_LOW_DATA then
							DataBit := not SerialDataIn_sync;
						else
							DataBit := SerialDataIn_sync;
						end if;
						ShiftReg <= ShiftReg(BITS - 2 downto 0) & DataBit;

						if BitCounter = 0 then
							-- All bits shifted
							State <= ST_COMPLETE;
						else
							BitCounter <= BitCounter - 1;
							Timer      <= to_unsigned(HALF_PERIOD_CYCLES - 1, Timer'length);
							State      <= ST_SHIFT_CLOCK_HIGH;
						end if;

					when ST_COMPLETE =>
						Valid_s        <= '1';
						Busy_s         <= '0';
						ClockInhibit_s <= '1';
						SerialClock_s  <= '0';
						State          <= ST_IDLE;

				end case;
			end if;
		end if;
	end process;

	-- Serial input is directly driven low for non-cascaded operation
	SerialIn_s <= '0';

	-- Apply output polarities
	ShiftLoad_n   <= ShiftLoad_n_s   when ACTIVE_LOW_LOAD            else not ShiftLoad_n_s;
	ClockInhibit  <= ClockInhibit_s  when not ACTIVE_LOW_CLK_INHIBIT else not ClockInhibit_s;
	SerialIn      <= SerialIn_s      when not ACTIVE_LOW_SERIAL_IN   else not SerialIn_s;
	SerialClock   <= SerialClock_s;

	-- Output assignments
	Busy         <= Busy_s;
	Valid        <= Valid_s;
	DataReceived <= ShiftReg;

end architecture rtl;
