-- EMACS settings: -*-  tab-width: 2; indent-tabs-mode: t -*-
-- vim: tabstop=2:shiftwidth=2:noexpandtab
-- kate: tab-width 2; replace-tabs off; indent-width 2;
-- =============================================================================
-- Authors:         Gustavo Martin
--
-- Entity:          io_ShiftRegister_PISO_TestHarness
--
-- Description:
-- -------------------------------------
-- Test harness for the PISO shift register controller.
-- This connects the DUT (io_ShiftRegister_PISO_Controller) to the
-- verification model (SN74AC165_Model) and the test controller.
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


entity io_ShiftRegister_PISO_TestHarness is
end entity;


architecture TestHarness of io_ShiftRegister_PISO_TestHarness is
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
	--   0 = 5 MHz shift clock, ACTIVE_LOW_CLK_INHIBIT=FALSE
	--   1 = 30 MHz shift clock, ACTIVE_LOW_CLK_INHIBIT=FALSE
	--   2 = 5 MHz shift clock, ACTIVE_LOW_CLK_INHIBIT=TRUE
	--   3 = 5 MHz shift clock, ADD_INPUT_SYNCHRONIZERS=TRUE
	signal ShiftFreqSel : natural range 0 to 3 := 0;

	-- DUT interface signals (directly accessible by test controller)
	signal Start        : std_logic;
	signal Busy         : std_logic;
	signal Valid        : std_logic;
	signal DataReceived : std_logic_vector(BITS - 1 downto 0);

	-- Shift register bus signals
	signal ShiftLoad_n   : std_logic;
	signal SerialClock   : std_logic;
	signal ClockInhibit  : std_logic;
	signal SerialIn      : std_logic;
	signal SerialDataIn  : std_logic;
	signal SerialDataIn_n : std_logic;

	-- Raw ClockInhibit from selected DUT (before model inversion)
	signal ClockInhibit_Raw : std_logic;

	-- Per-DUT signals (one set per configuration)
	signal Start_Slow, Start_Fast, Start_ActiveLow        : std_logic;
	signal Busy_Slow, Busy_Fast, Busy_ActiveLow           : std_logic;
	signal Valid_Slow, Valid_Fast, Valid_ActiveLow        : std_logic;
	signal DataReceived_Slow, DataReceived_Fast           : std_logic_vector(BITS - 1 downto 0);
	signal DataReceived_ActiveLow                         : std_logic_vector(BITS - 1 downto 0);
	signal ShiftLoad_n_Slow, ShiftLoad_n_Fast             : std_logic;
	signal ShiftLoad_n_ActiveLow                          : std_logic;
	signal SerialClock_Slow, SerialClock_Fast             : std_logic;
	signal SerialClock_ActiveLow                          : std_logic;
	signal ClockInhibit_Slow, ClockInhibit_Fast           : std_logic;
	signal ClockInhibit_ActiveLow                         : std_logic;
	signal ClockInhibit_Sync                              : std_logic;
	signal SerialIn_Slow, SerialIn_Fast, SerialIn_ActiveLow : std_logic;
	signal SerialIn_Sync                                  : std_logic;

	-- Per-DUT signals for DUT 3 (ADD_INPUT_SYNCHRONIZERS=TRUE)
	signal Start_Sync        : std_logic;
	signal Busy_Sync         : std_logic;
	signal Valid_Sync        : std_logic;
	signal DataReceived_Sync : std_logic_vector(BITS - 1 downto 0);
	signal ShiftLoad_n_Sync  : std_logic;
	signal SerialClock_Sync  : std_logic;

	-- Model control signals
	signal ModelParallelIn : std_logic_vector(7 downto 0);

	-- Component declarations
	component io_ShiftRegister_PISO_TestController is
		port (
			Clock           : in  std_logic;
			Reset           : in  std_logic;
			ShiftFreqSel    : out natural range 0 to 3;
			Start           : out std_logic;
			Busy            : in  std_logic;
			Valid           : in  std_logic;
			DataReceived    : in  std_logic_vector(7 downto 0);
			ClockInhibit    : in  std_logic;
			ModelParallelIn : out std_logic_vector(7 downto 0)
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
			BITS                    => BITS,
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
			SerialDataIn => SerialDataIn
		);

	-- DUT 1: Fast (30 MHz) shift clock
	DUT_Fast : entity PoC.io_ShiftRegister_PISO_Controller
		generic map (
			BITS                    => BITS,
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
			SerialDataIn => SerialDataIn
		);

	-- DUT 2: Slow (5 MHz) shift clock with ACTIVE_LOW_CLK_INHIBIT = TRUE
	DUT_ActiveLow : entity PoC.io_ShiftRegister_PISO_Controller
		generic map (
			BITS                    => BITS,
			ACTIVE_LOW_LOAD         => TRUE,
			ACTIVE_LOW_CLK_INHIBIT  => TRUE,  -- Inverted ClockInhibit polarity
			ACTIVE_LOW_DATA         => FALSE,
			ACTIVE_LOW_SERIAL_IN    => FALSE,
			CLOCK_FREQ              => CLOCK_FREQ,
			SHIFT_FREQ              => SHIFT_FREQ_SLOW,
			ADD_INPUT_SYNCHRONIZERS => FALSE
		)
		port map (
			Clock        => Clock,
			Reset        => Reset,
			Start        => Start_ActiveLow,
			Busy         => Busy_ActiveLow,
			Valid        => Valid_ActiveLow,
			DataReceived => DataReceived_ActiveLow,
			ShiftLoad_n  => ShiftLoad_n_ActiveLow,
			SerialClock  => SerialClock_ActiveLow,
			ClockInhibit => ClockInhibit_ActiveLow,
			SerialIn     => SerialIn_ActiveLow,
			SerialDataIn => SerialDataIn
		);

	-- DUT 3: Slow (5 MHz) shift clock with ADD_INPUT_SYNCHRONIZERS = TRUE
	DUT_Sync : entity PoC.io_ShiftRegister_PISO_Controller
		generic map (
			BITS                    => BITS,
			ACTIVE_LOW_LOAD         => TRUE,
			ACTIVE_LOW_CLK_INHIBIT  => FALSE,
			ACTIVE_LOW_DATA         => FALSE,
			ACTIVE_LOW_SERIAL_IN    => FALSE,
			CLOCK_FREQ              => CLOCK_FREQ,
			SHIFT_FREQ              => SHIFT_FREQ_SLOW,
			ADD_INPUT_SYNCHRONIZERS => TRUE  -- Input synchronizers enabled
		)
		port map (
			Clock        => Clock,
			Reset        => Reset,
			Start        => Start_Sync,
			Busy         => Busy_Sync,
			Valid        => Valid_Sync,
			DataReceived => DataReceived_Sync,
			ShiftLoad_n  => ShiftLoad_n_Sync,
			SerialClock  => SerialClock_Sync,
			ClockInhibit => ClockInhibit_Sync,
			SerialIn     => SerialIn_Sync,
			SerialDataIn => SerialDataIn
		);

	-- =========================================================================
	-- Multiplexers: Select active DUT based on ShiftFreqSel
	-- =========================================================================

	-- Route Start to selected DUT
	Start_Slow      <= Start when ShiftFreqSel = 0 else '0';
	Start_Fast      <= Start when ShiftFreqSel = 1 else '0';
	Start_ActiveLow <= Start when ShiftFreqSel = 2 else '0';
	Start_Sync      <= Start when ShiftFreqSel = 3 else '0';

	-- Mux outputs from selected DUT
	Busy         <= Busy_Slow         when ShiftFreqSel = 0 else
	                Busy_Fast         when ShiftFreqSel = 1 else
	                Busy_ActiveLow    when ShiftFreqSel = 2 else
	                Busy_Sync;
	Valid        <= Valid_Slow        when ShiftFreqSel = 0 else
	                Valid_Fast        when ShiftFreqSel = 1 else
	                Valid_ActiveLow   when ShiftFreqSel = 2 else
	                Valid_Sync;
	DataReceived <= DataReceived_Slow when ShiftFreqSel = 0 else
	                DataReceived_Fast when ShiftFreqSel = 1 else
	                DataReceived_ActiveLow when ShiftFreqSel = 2 else
	                DataReceived_Sync;

	-- Raw ClockInhibit from DUT (for test verification, not inverted)
	ClockInhibit_Raw <= ClockInhibit_Slow when ShiftFreqSel = 0 else
	                    ClockInhibit_Fast when ShiftFreqSel = 1 else
	                    ClockInhibit_ActiveLow when ShiftFreqSel = 2 else
	                    ClockInhibit_Sync;

	-- Mux shift register bus signals to Model
	ShiftLoad_n  <= ShiftLoad_n_Slow  when ShiftFreqSel = 0 else
	                ShiftLoad_n_Fast  when ShiftFreqSel = 1 else
	                ShiftLoad_n_ActiveLow when ShiftFreqSel = 2 else
	                ShiftLoad_n_Sync;
	SerialClock  <= SerialClock_Slow  when ShiftFreqSel = 0 else
	                SerialClock_Fast  when ShiftFreqSel = 1 else
	                SerialClock_ActiveLow when ShiftFreqSel = 2 else
	                SerialClock_Sync;
	-- Note: For DUT 2 (ACTIVE_LOW_CLK_INHIBIT=TRUE), we invert the signal
	-- to match the standard SN74AC165 model behavior where CLK_INH='0' enables clocking
	ClockInhibit <= ClockInhibit_Slow when ShiftFreqSel = 0 else
	                ClockInhibit_Fast when ShiftFreqSel = 1 else
	                not ClockInhibit_ActiveLow when ShiftFreqSel = 2 else  -- Invert for model compatibility
	                ClockInhibit_Sync;
	SerialIn     <= SerialIn_Slow     when ShiftFreqSel = 0 else
	                SerialIn_Fast     when ShiftFreqSel = 1 else
	                SerialIn_ActiveLow when ShiftFreqSel = 2 else
	                SerialIn_Sync;

	-- =========================================================================
	-- Verification Model: SN74AC165 Shift Register
	-- =========================================================================
	Model : component SN74AC165_Model
		generic map (
			TPD_SH_LD_TO_QH => 12 ns,
			TPD_CLK_TO_QH   => 11 ns
		)
		port map (
			ParallelIn => ModelParallelIn,
			UseVector  => TRUE,
			SH_LD_n    => ShiftLoad_n,
			CLK        => SerialClock,
			CLK_INH    => ClockInhibit,
			SER        => SerialIn,
			QH         => SerialDataIn,
			QH_n       => SerialDataIn_n
		);

	-- =========================================================================
	-- Test Controller
	-- =========================================================================
	TestCtrl : component io_ShiftRegister_PISO_TestController
		port map (
			Clock           => Clock,
			Reset           => Reset,
			ShiftFreqSel    => ShiftFreqSel,
			Start           => Start,
			Busy            => Busy,
			Valid           => Valid,
			DataReceived    => DataReceived,
			ClockInhibit    => ClockInhibit_Raw,  -- Use raw (non-inverted) signal for test
			ModelParallelIn => ModelParallelIn
		);

end architecture;
