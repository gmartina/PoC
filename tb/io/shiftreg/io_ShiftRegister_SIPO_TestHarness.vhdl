-- EMACS settings: -*-  tab-width: 2; indent-tabs-mode: t -*-
-- vim: tabstop=2:shiftwidth=2:noexpandtab
-- kate: tab-width 2; replace-tabs off; indent-width 2;
-- =============================================================================
-- Authors:         Gustavo Martin
--
-- Entity:          io_ShiftRegister_SIPO_TestHarness
--
-- Description:
-- -------------------------------------
-- Test harness for the SIPO shift register controller.
-- This connects the DUT (io_ShiftRegister_SIPO_Controller) to the
-- verification model (SN74AC596_Model) and the test controller.
--
-- Supports multiple shift clock frequencies via DUT selection:
--   - ShiftFreqSel = 0: 5 MHz shift clock (default)
--   - ShiftFreqSel = 1: 30 MHz shift clock (fast)
--
-- The test controller drives ShiftFreqSel to select the desired configuration.
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

library osvvm;
context osvvm.OsvvmContext;

library PoC;
use     PoC.physical.all;


entity io_ShiftRegister_SIPO_TestHarness is
end entity;


architecture TestHarness of io_ShiftRegister_SIPO_TestHarness is
	-- Clock and timing constants
	constant TPERIOD_CLOCK : time := 10 ns;   -- 100 MHz system clock
	constant CLOCK_FREQ    : FREQ := 100 MHz;

	-- Supported shift frequencies
	constant SHIFT_FREQ_SLOW : FREQ := 5 MHz;
	constant SHIFT_FREQ_FAST : FREQ := 30 MHz;

	-- Test configuration
	constant BITS : positive := 8;

	-- Clock and reset signals
	signal Clock : std_logic := '1';
	signal Reset : std_logic := '1';

	-- DUT selection (driven by test controller):
	--   0 = 5 MHz shift clock, ACTIVE_LOW_CLEAR=TRUE
	--   1 = 30 MHz shift clock, ACTIVE_LOW_CLEAR=TRUE
	--   2 = 5 MHz shift clock, ACTIVE_LOW_CLEAR=FALSE
	--   3 = 5 MHz shift clock, ADD_OUTPUT_REGISTERS=TRUE
	signal ShiftFreqSel : natural range 0 to 3 := 0;

	-- DUT interface signals
	signal Start      : std_logic;
	signal Busy       : std_logic;
	signal Done       : std_logic;
	signal DataToSend : std_logic_vector(BITS - 1 downto 0);

	-- Shift register bus signals (active, muxed from selected DUT)
	signal SerialOut   : std_logic;
	signal ShiftClock  : std_logic;
	signal LatchClock  : std_logic;
	signal Clear_n     : std_logic;

	-- Per-DUT signals (one set per configuration)
	signal Start_Slow, Start_Fast, Start_ActiveHigh      : std_logic;
	signal Busy_Slow, Busy_Fast, Busy_ActiveHigh         : std_logic;
	signal Done_Slow, Done_Fast, Done_ActiveHigh         : std_logic;
	signal SerialOut_Slow, SerialOut_Fast                : std_logic;
	signal SerialOut_ActiveHigh                          : std_logic;
	signal ShiftClock_Slow, ShiftClock_Fast              : std_logic;
	signal ShiftClock_ActiveHigh                         : std_logic;
	signal LatchClock_Slow, LatchClock_Fast              : std_logic;
	signal LatchClock_ActiveHigh                         : std_logic;
	signal Clear_n_Slow, Clear_n_Fast, Clear_n_ActiveHigh : std_logic;
	signal Clear_n_Raw : std_logic;  -- Raw DUT output for test verification

	-- Per-DUT signals for DUT 3 (ADD_OUTPUT_REGISTERS=TRUE)
	signal Start_OutReg      : std_logic;
	signal Busy_OutReg       : std_logic;
	signal Done_OutReg       : std_logic;
	signal SerialOut_OutReg  : std_logic;
	signal ShiftClock_OutReg : std_logic;
	signal LatchClock_OutReg : std_logic;
	signal Clear_n_OutReg    : std_logic;

	-- Model output signals
	signal ModelParallelOut : std_logic_vector(7 downto 0);

	-- Component declarations
	component io_ShiftRegister_SIPO_TestController is
		port (
			Clock            : in  std_logic;
			Reset            : in  std_logic;
			ShiftFreqSel     : out natural range 0 to 3;
			Start            : out std_logic;
			Busy             : in  std_logic;
			Done             : in  std_logic;
			DataToSend       : out std_logic_vector(7 downto 0);
			Clear_n          : in  std_logic;
			ModelParallelOut : in  std_logic_vector(7 downto 0)
		);
	end component;

	component SN74AC596_Model is
		generic (
			TPD_SRCK_TO_QH_PRIME : time := 11 ns;
			TPD_RCK_TO_OUTPUTS   : time := 12 ns;
			TPD_SCLR_TO_QH_PRIME : time := 10 ns;
			TSU_SER              : time := 10 ns;
			TH_SER               : time := 0 ns;
			TPW_SRCK_HIGH        : time := 6 ns;
			TPW_SRCK_LOW         : time := 6 ns;
			TPW_RCK_HIGH         : time := 6 ns;
			TPW_RCK_LOW          : time := 6 ns;
			TPW_SCLR_LOW         : time := 10 ns
		);
		port (
			SER         : in  std_logic := '0';
			SRCK        : in  std_logic := '0';
			RCK         : in  std_logic := '0';
			SCLR_n      : in  std_logic := '1';
			QA          : out std_logic;
			QB          : out std_logic;
			QC          : out std_logic;
			QD          : out std_logic;
			QE          : out std_logic;
			QF          : out std_logic;
			QG          : out std_logic;
			QH          : out std_logic;
			ParallelOut : out std_logic_vector(7 downto 0);
			QH_Prime    : out std_logic
		);
	end component;

begin
	-- Clock generation using OSVVM
	Osvvm.ClockResetPkg.CreateClock(
		Clk    => Clock,
		Period => TPERIOD_CLOCK
	);

	-- Reset generation using OSVVM
	Osvvm.ClockResetPkg.CreateReset(
		Reset       => Reset,
		ResetActive => '1',
		Clk         => Clock,
		Period      => 5 * TPERIOD_CLOCK,
		tpd         => 0 ns
	);

	-- =========================================================================
	-- DUT instances with different configurations
	-- =========================================================================

	-- DUT 0: Slow (5 MHz) shift clock, ACTIVE_LOW_CLEAR=TRUE
	DUT_Slow : entity PoC.io_ShiftRegister_SIPO_Controller
		generic map (
			BITS                    => BITS,
			ACTIVE_LOW_CLEAR        => TRUE,
			ACTIVE_LOW_SERIAL_OUT   => FALSE,
			ACTIVE_LOW_LATCH        => FALSE,
			ACTIVE_LOW_SHIFT_CLK    => FALSE,
			CLOCK_FREQ              => CLOCK_FREQ,
			SHIFT_FREQ              => SHIFT_FREQ_SLOW,
			ADD_OUTPUT_REGISTERS    => FALSE
		)
		port map (
			Clock       => Clock,
			Reset       => Reset,
			Start       => Start_Slow,
			Busy        => Busy_Slow,
			Done        => Done_Slow,
			DataToSend  => DataToSend,
			SerialOut   => SerialOut_Slow,
			ShiftClock  => ShiftClock_Slow,
			LatchClock  => LatchClock_Slow,
			Clear_n     => Clear_n_Slow
		);

	-- DUT 1: Fast (30 MHz) shift clock, ACTIVE_LOW_CLEAR=TRUE
	DUT_Fast : entity PoC.io_ShiftRegister_SIPO_Controller
		generic map (
			BITS                    => BITS,
			ACTIVE_LOW_CLEAR        => TRUE,
			ACTIVE_LOW_SERIAL_OUT   => FALSE,
			ACTIVE_LOW_LATCH        => FALSE,
			ACTIVE_LOW_SHIFT_CLK    => FALSE,
			CLOCK_FREQ              => CLOCK_FREQ,
			SHIFT_FREQ              => SHIFT_FREQ_FAST,
			ADD_OUTPUT_REGISTERS    => FALSE
		)
		port map (
			Clock       => Clock,
			Reset       => Reset,
			Start       => Start_Fast,
			Busy        => Busy_Fast,
			Done        => Done_Fast,
			DataToSend  => DataToSend,
			SerialOut   => SerialOut_Fast,
			ShiftClock  => ShiftClock_Fast,
			LatchClock  => LatchClock_Fast,
			Clear_n     => Clear_n_Fast
		);

	-- DUT 2: Slow (5 MHz) shift clock, ACTIVE_LOW_CLEAR=FALSE (active-high clear)
	DUT_ActiveHigh : entity PoC.io_ShiftRegister_SIPO_Controller
		generic map (
			BITS                    => BITS,
			ACTIVE_LOW_CLEAR        => FALSE,  -- Active-high clear signal
			ACTIVE_LOW_SERIAL_OUT   => FALSE,
			ACTIVE_LOW_LATCH        => FALSE,
			ACTIVE_LOW_SHIFT_CLK    => FALSE,
			CLOCK_FREQ              => CLOCK_FREQ,
			SHIFT_FREQ              => SHIFT_FREQ_SLOW,
			ADD_OUTPUT_REGISTERS    => FALSE
		)
		port map (
			Clock       => Clock,
			Reset       => Reset,
			Start       => Start_ActiveHigh,
			Busy        => Busy_ActiveHigh,
			Done        => Done_ActiveHigh,
			DataToSend  => DataToSend,
			SerialOut   => SerialOut_ActiveHigh,
			ShiftClock  => ShiftClock_ActiveHigh,
			LatchClock  => LatchClock_ActiveHigh,
			Clear_n     => Clear_n_ActiveHigh
		);

	-- DUT 3: Slow (5 MHz) shift clock, ADD_OUTPUT_REGISTERS=TRUE
	DUT_OutReg : entity PoC.io_ShiftRegister_SIPO_Controller
		generic map (
			BITS                    => BITS,
			ACTIVE_LOW_CLEAR        => TRUE,
			ACTIVE_LOW_SERIAL_OUT   => FALSE,
			ACTIVE_LOW_LATCH        => FALSE,
			ACTIVE_LOW_SHIFT_CLK    => FALSE,
			CLOCK_FREQ              => CLOCK_FREQ,
			SHIFT_FREQ              => SHIFT_FREQ_SLOW,
			ADD_OUTPUT_REGISTERS    => TRUE  -- Output registers enabled
		)
		port map (
			Clock       => Clock,
			Reset       => Reset,
			Start       => Start_OutReg,
			Busy        => Busy_OutReg,
			Done        => Done_OutReg,
			DataToSend  => DataToSend,
			SerialOut   => SerialOut_OutReg,
			ShiftClock  => ShiftClock_OutReg,
			LatchClock  => LatchClock_OutReg,
			Clear_n     => Clear_n_OutReg
		);

	-- =========================================================================
	-- Multiplexers: Select active DUT based on ShiftFreqSel
	-- =========================================================================

	-- Route Start to selected DUT
	Start_Slow       <= Start when ShiftFreqSel = 0 else '0';
	Start_Fast       <= Start when ShiftFreqSel = 1 else '0';
	Start_ActiveHigh <= Start when ShiftFreqSel = 2 else '0';
	Start_OutReg     <= Start when ShiftFreqSel = 3 else '0';

	-- Mux outputs from selected DUT
	Busy <= Busy_Slow when ShiftFreqSel = 0 else
	        Busy_Fast when ShiftFreqSel = 1 else
	        Busy_ActiveHigh when ShiftFreqSel = 2 else
	        Busy_OutReg;
	Done <= Done_Slow when ShiftFreqSel = 0 else
	        Done_Fast when ShiftFreqSel = 1 else
	        Done_ActiveHigh when ShiftFreqSel = 2 else
	        Done_OutReg;

	-- Mux shift register bus signals to Model
	SerialOut  <= SerialOut_Slow  when ShiftFreqSel = 0 else
	              SerialOut_Fast  when ShiftFreqSel = 1 else
	              SerialOut_ActiveHigh when ShiftFreqSel = 2 else
	              SerialOut_OutReg;
	ShiftClock <= ShiftClock_Slow when ShiftFreqSel = 0 else
	              ShiftClock_Fast when ShiftFreqSel = 1 else
	              ShiftClock_ActiveHigh when ShiftFreqSel = 2 else
	              ShiftClock_OutReg;
	LatchClock <= LatchClock_Slow when ShiftFreqSel = 0 else
	              LatchClock_Fast when ShiftFreqSel = 1 else
	              LatchClock_ActiveHigh when ShiftFreqSel = 2 else
	              LatchClock_OutReg;
	-- Note: For DUT 2 (ACTIVE_LOW_CLEAR=FALSE), we invert the signal
	-- to match the standard SN74AC596 model behavior where SCLR_n='0' clears
	Clear_n    <= Clear_n_Slow    when ShiftFreqSel = 0 else
	              Clear_n_Fast    when ShiftFreqSel = 1 else
	              not Clear_n_ActiveHigh when ShiftFreqSel = 2 else  -- Invert for model compatibility
	              Clear_n_OutReg;
	-- Raw DUT output for test verification (no inversion)
	Clear_n_Raw <= Clear_n_Slow     when ShiftFreqSel = 0 else
	               Clear_n_Fast     when ShiftFreqSel = 1 else
	               Clear_n_ActiveHigh when ShiftFreqSel = 2 else
	               Clear_n_OutReg;

	-- =========================================================================
	-- Verification Model: SN74AC596 Shift Register
	-- =========================================================================
	Model : component SN74AC596_Model
		generic map (
			TPD_SRCK_TO_QH_PRIME => 11 ns,
			TPD_RCK_TO_OUTPUTS   => 12 ns
		)
		port map (
			SER         => SerialOut,
			SRCK        => ShiftClock,
			RCK         => LatchClock,
			SCLR_n      => Clear_n,
			ParallelOut => ModelParallelOut,
			QH_Prime    => open  -- Not used for single chip test
		);

	-- =========================================================================
	-- Test Controller
	-- =========================================================================
	TestCtrl : component io_ShiftRegister_SIPO_TestController
		port map (
			Clock            => Clock,
			Reset            => Reset,
			ShiftFreqSel     => ShiftFreqSel,
			Start            => Start,
			Busy             => Busy,
			Done             => Done,
			DataToSend       => DataToSend,
			Clear_n          => Clear_n_Raw,  -- Use raw DUT output for verification
			ModelParallelOut => ModelParallelOut
		);

end architecture;
