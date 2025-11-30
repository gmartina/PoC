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
	constant SHIFT_FREQ    : FREQ := 5 MHz;   -- 5 MHz shift clock

	-- Test configuration
	constant BITS : positive := 8;

	-- Clock and reset signals
	signal Clock_100 : std_logic := '1';
	signal Reset_100 : std_logic := '1';

	-- DUT interface signals
	signal Start        : std_logic;
	signal Busy         : std_logic;
	signal Valid        : std_logic;
	signal DataReceived : std_logic_vector(BITS - 1 downto 0);

	-- Shift register bus signals (between DUT and Model)
	signal ShiftLoad_n   : std_logic;
	signal SerialClock   : std_logic;
	signal ClockInhibit  : std_logic;
	signal SerialIn      : std_logic;
	signal SerialDataIn  : std_logic;
	signal SerialDataIn_n : std_logic;

	-- Model control signals
	signal ModelParallelIn : std_logic_vector(7 downto 0);

	-- Component declarations
	component io_ShiftRegister_PISO_TestController is
		port (
			Clock           : in  std_logic;
			Reset           : in  std_logic;
			Start           : out std_logic;
			Busy            : in  std_logic;
			Valid           : in  std_logic;
			DataReceived    : in  std_logic_vector(7 downto 0);
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
		Clk    => Clock_100,
		Period => TPERIOD_CLOCK
	);

	-- Reset generation using OSVVM
	Osvvm.ClockResetPkg.CreateReset(
		Reset       => Reset_100,
		ResetActive => '1',
		Clk         => Clock_100,
		Period      => 5 * TPERIOD_CLOCK,
		tpd         => 0 ns
	);

	-- Device Under Test: PISO Shift Register Controller
	DUT : entity PoC.io_ShiftRegister_PISO_Controller
		generic map (
			BITS                    => BITS,
			ACTIVE_LOW_LOAD         => TRUE,
			ACTIVE_LOW_CLK_INHIBIT  => FALSE,
			ACTIVE_LOW_DATA         => FALSE,
			ACTIVE_LOW_SERIAL_IN    => FALSE,
			CLOCK_FREQ              => CLOCK_FREQ,
			SHIFT_FREQ              => SHIFT_FREQ,
			ADD_INPUT_SYNCHRONIZERS => FALSE  -- Disable for faster simulation
		)
		port map (
			Clock        => Clock_100,
			Reset        => Reset_100,
			Start        => Start,
			Busy         => Busy,
			Valid        => Valid,
			DataReceived => DataReceived,
			ShiftLoad_n  => ShiftLoad_n,
			SerialClock  => SerialClock,
			ClockInhibit => ClockInhibit,
			SerialIn     => SerialIn,
			SerialDataIn => SerialDataIn
		);

	-- Verification Model: SN74AC165 Shift Register
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

	-- Test Controller
	TestCtrl : component io_ShiftRegister_PISO_TestController
		port map (
			Clock           => Clock_100,
			Reset           => Reset_100,
			Start           => Start,
			Busy            => Busy,
			Valid           => Valid,
			DataReceived    => DataReceived,
			ModelParallelIn => ModelParallelIn
		);

end architecture;
