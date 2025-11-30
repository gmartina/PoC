-- EMACS settings: -*-  tab-width: 2; indent-tabs-mode: t -*-
-- vim: tabstop=2:shiftwidth=2:noexpandtab
-- kate: tab-width 2; replace-tabs off; indent-width 2;
-- =============================================================================
-- Authors:         Gustavo Martin
--
-- Entity:          io_ShiftRegister_PISO_DaisyChain_TestHarness
--
-- Description:
-- -------------------------------------
-- Test harness for the PISO shift register controller in daisy chain mode.
-- This connects the DUT (io_ShiftRegister_PISO_Controller configured for 24 bits)
-- to three cascaded SN74AC165_Model instances and the test controller.
--
-- Daisy Chain Configuration:
--   [Chip 0] --> [Chip 1] --> [Chip 2] --> Controller
--   (LSB)                      (MSB)
--
--   - Chip 0: Bits 7:0   (first loaded, shifted out last)
--   - Chip 1: Bits 15:8  (middle chip)
--   - Chip 2: Bits 23:16 (last chip, QH connects to controller)
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


entity io_ShiftRegister_PISO_DaisyChain_TestHarness is
end entity;


architecture TestHarness of io_ShiftRegister_PISO_DaisyChain_TestHarness is
	-- Clock and timing constants
	constant TPERIOD_CLOCK : time := 10 ns;   -- 100 MHz system clock
	constant CLOCK_FREQ    : FREQ := 100 MHz;

	-- Supported shift frequencies
	constant SHIFT_FREQ_SLOW : FREQ := 5 MHz;
	constant SHIFT_FREQ_FAST : FREQ := 30 MHz;

	-- Daisy chain configuration
	constant NUM_CHIPS     : positive := 3;
	constant BITS_PER_CHIP : positive := 8;
	constant TOTAL_BITS    : positive := NUM_CHIPS * BITS_PER_CHIP;  -- 24 bits

	-- Clock and reset signals
	signal Clock : std_logic := '1';
	signal Reset : std_logic := '1';

	-- Frequency selection (driven by test controller)
	signal ShiftFreqSel : natural range 0 to 1 := 0;

	-- DUT interface signals
	signal Start        : std_logic;
	signal Busy         : std_logic;
	signal Valid        : std_logic;
	signal DataReceived : std_logic_vector(TOTAL_BITS - 1 downto 0);

	-- Shift register bus signals (active, muxed from selected DUT)
	signal ShiftLoad_n   : std_logic;
	signal SerialClock   : std_logic;
	signal ClockInhibit  : std_logic;
	signal SerialIn      : std_logic;

	-- Inter-chip serial connections
	signal SerialChain   : std_logic_vector(NUM_CHIPS downto 0);

	-- Per-DUT signals (one set per frequency)
	signal Start_Slow, Start_Fast               : std_logic;
	signal Busy_Slow, Busy_Fast                 : std_logic;
	signal Valid_Slow, Valid_Fast               : std_logic;
	signal DataReceived_Slow, DataReceived_Fast : std_logic_vector(TOTAL_BITS - 1 downto 0);
	signal ShiftLoad_n_Slow, ShiftLoad_n_Fast   : std_logic;
	signal SerialClock_Slow, SerialClock_Fast   : std_logic;
	signal ClockInhibit_Slow, ClockInhibit_Fast : std_logic;
	signal SerialIn_Slow, SerialIn_Fast         : std_logic;

	-- Model control signals (24 bits total, split across 3 chips)
	signal ModelParallelIn : std_logic_vector(TOTAL_BITS - 1 downto 0);

	-- Component declarations
	component io_ShiftRegister_PISO_DaisyChain_TestController is
		port (
			Clock           : in  std_logic;
			Reset           : in  std_logic;
			ShiftFreqSel    : out natural range 0 to 1;
			Start           : out std_logic;
			Busy            : in  std_logic;
			Valid           : in  std_logic;
			DataReceived    : in  std_logic_vector(23 downto 0);
			ModelParallelIn : out std_logic_vector(23 downto 0)
		);
	end component;

	component SN74AC165_Model is
		generic (
			TPD_SH_LD_TO_QH  : time := 12 ns;
			TPD_CLK_TO_QH    : time := 11 ns;
			TSU_DATA         : time := 10 ns;
			TH_DATA          : time := 0 ns;
			TSU_SER          : time := 10 ns;
			TH_SER           : time := 0 ns;
			TPW_CLK_HIGH     : time := 6 ns;
			TPW_CLK_LOW      : time := 6 ns;
			TPW_SH_LD_LOW    : time := 10 ns
		);
		port (
			A          : in  std_logic := '0';
			B          : in  std_logic := '0';
			C          : in  std_logic := '0';
			D          : in  std_logic := '0';
			E          : in  std_logic := '0';
			F          : in  std_logic := '0';
			G          : in  std_logic := '0';
			H          : in  std_logic := '0';
			ParallelIn : in  std_logic_vector(7 downto 0) := (others => '0');
			UseVector  : in  boolean := TRUE;
			SH_LD_n    : in  std_logic := '1';
			CLK        : in  std_logic := '0';
			CLK_INH    : in  std_logic := '0';
			SER        : in  std_logic := '0';
			QH         : out std_logic;
			QH_n       : out std_logic
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
	-- DUT instances with different shift frequencies
	-- =========================================================================

	-- DUT 0: Slow (5 MHz) shift clock
	DUT_Slow : entity PoC.io_ShiftRegister_PISO_Controller
		generic map (
			BITS                    => TOTAL_BITS,
			ACTIVE_LOW_LOAD         => TRUE,
			ACTIVE_LOW_CLK_INHIBIT  => FALSE,
			ACTIVE_LOW_DATA         => FALSE,
			ACTIVE_LOW_SERIAL_IN    => FALSE,
			CLOCK_FREQ              => CLOCK_FREQ,
			SHIFT_FREQ              => SHIFT_FREQ_SLOW,
			ADD_INPUT_SYNCHRONIZERS => FALSE
		)
		port map (
			Clock        => Clock,
			Reset        => Reset,
			Start        => Start_Slow,
			Busy         => Busy_Slow,
			Valid        => Valid_Slow,
			DataReceived => DataReceived_Slow,
			ShiftLoad_n  => ShiftLoad_n_Slow,
			SerialClock  => SerialClock_Slow,
			ClockInhibit => ClockInhibit_Slow,
			SerialIn     => SerialIn_Slow,
			SerialDataIn => SerialChain(NUM_CHIPS)
		);

	-- DUT 1: Fast (30 MHz) shift clock
	DUT_Fast : entity PoC.io_ShiftRegister_PISO_Controller
		generic map (
			BITS                    => TOTAL_BITS,
			ACTIVE_LOW_LOAD         => TRUE,
			ACTIVE_LOW_CLK_INHIBIT  => FALSE,
			ACTIVE_LOW_DATA         => FALSE,
			ACTIVE_LOW_SERIAL_IN    => FALSE,
			CLOCK_FREQ              => CLOCK_FREQ,
			SHIFT_FREQ              => SHIFT_FREQ_FAST,
			ADD_INPUT_SYNCHRONIZERS => FALSE
		)
		port map (
			Clock        => Clock,
			Reset        => Reset,
			Start        => Start_Fast,
			Busy         => Busy_Fast,
			Valid        => Valid_Fast,
			DataReceived => DataReceived_Fast,
			ShiftLoad_n  => ShiftLoad_n_Fast,
			SerialClock  => SerialClock_Fast,
			ClockInhibit => ClockInhibit_Fast,
			SerialIn     => SerialIn_Fast,
			SerialDataIn => SerialChain(NUM_CHIPS)
		);

	-- =========================================================================
	-- Multiplexers: Select active DUT based on ShiftFreqSel
	-- =========================================================================

	-- Route Start to selected DUT
	Start_Slow <= Start when ShiftFreqSel = 0 else '0';
	Start_Fast <= Start when ShiftFreqSel = 1 else '0';

	-- Mux outputs from selected DUT
	Busy         <= Busy_Slow         when ShiftFreqSel = 0 else Busy_Fast;
	Valid        <= Valid_Slow        when ShiftFreqSel = 0 else Valid_Fast;
	DataReceived <= DataReceived_Slow when ShiftFreqSel = 0 else DataReceived_Fast;

	-- Mux shift register bus signals to Model chain
	ShiftLoad_n  <= ShiftLoad_n_Slow  when ShiftFreqSel = 0 else ShiftLoad_n_Fast;
	SerialClock  <= SerialClock_Slow  when ShiftFreqSel = 0 else SerialClock_Fast;
	ClockInhibit <= ClockInhibit_Slow when ShiftFreqSel = 0 else ClockInhibit_Fast;
	SerialIn     <= SerialIn_Slow     when ShiftFreqSel = 0 else SerialIn_Fast;

	-- =========================================================================
	-- Verification Models: Daisy chain of SN74AC165 Shift Registers
	-- =========================================================================

	-- Serial input to first chip comes from controller
	SerialChain(0) <= SerialIn;

	-- Generate daisy chain of SN74AC165 models
	-- Chip 0 holds bits 7:0, Chip 1 holds bits 15:8, Chip 2 holds bits 23:16
	-- Data shifts from Chip 0 -> Chip 1 -> Chip 2 -> Controller
	gen_chain : for i in 0 to NUM_CHIPS - 1 generate
		Model_inst : component SN74AC165_Model
			generic map (
				TPD_SH_LD_TO_QH => 12 ns,
				TPD_CLK_TO_QH   => 11 ns
			)
			port map (
				ParallelIn => ModelParallelIn((i + 1) * BITS_PER_CHIP - 1 downto i * BITS_PER_CHIP),
				UseVector  => TRUE,
				SH_LD_n    => ShiftLoad_n,
				CLK        => SerialClock,
				CLK_INH    => ClockInhibit,
				SER        => SerialChain(i),
				QH         => SerialChain(i + 1),
				QH_n       => open
			);
	end generate;

	-- =========================================================================
	-- Test Controller
	-- =========================================================================
	TestCtrl : component io_ShiftRegister_PISO_DaisyChain_TestController
		port map (
			Clock           => Clock,
			Reset           => Reset,
			ShiftFreqSel    => ShiftFreqSel,
			Start           => Start,
			Busy            => Busy,
			Valid           => Valid,
			DataReceived    => DataReceived,
			ModelParallelIn => ModelParallelIn
		);

end architecture;
