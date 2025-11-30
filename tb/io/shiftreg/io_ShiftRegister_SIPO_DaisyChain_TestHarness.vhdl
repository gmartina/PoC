-- EMACS settings: -*-  tab-width: 2; indent-tabs-mode: t -*-
-- vim: tabstop=2:shiftwidth=2:noexpandtab
-- kate: tab-width 2; replace-tabs off; indent-width 2;
-- =============================================================================
-- Authors:         Gustavo Martin
--
-- Entity:          io_ShiftRegister_SIPO_DaisyChain_TestHarness
--
-- Description:
-- -------------------------------------
-- Test harness for SIPO shift register controller verification with 3 daisy-
-- chained SN74AC596 chips (24 bits total).
--
-- This harness instantiates two DUT configurations (5 MHz and 30 MHz) and
-- multiplexes their outputs based on the ShiftFreqSel signal from the test
-- controller. This allows different test architectures to select which
-- configuration to test.
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


entity io_ShiftRegister_SIPO_DaisyChain_TestHarness is
end entity;


architecture TestHarness of io_ShiftRegister_SIPO_DaisyChain_TestHarness is
	-- =========================================================================
	-- Constants
	-- =========================================================================
	constant BITS           : positive := 24;  -- 3 IC x 8 bits
	constant CLOCK_FREQ     : freq     := 100 MHz;
	constant SHIFT_FREQ_SLOW: freq     := 5 MHz;
	constant SHIFT_FREQ_FAST: freq     := 30 MHz;

	-- =========================================================================
	-- Signals: Clock and Reset
	-- =========================================================================
	signal Clock : std_logic := '0';
	signal Reset : std_logic := '1';

	-- =========================================================================
	-- Signals: Test Controller Interface
	-- =========================================================================
	signal Start              : std_logic;
	signal DataToSend         : std_logic_vector(BITS-1 downto 0);
	signal ShiftFreqSel       : natural range 0 to 1;

	-- Muxed status signals to test controller
	signal Busy               : std_logic;
	signal Done               : std_logic;

	-- =========================================================================
	-- Signals: Slow DUT (5 MHz)
	-- =========================================================================
	signal Slow_Busy          : std_logic;
	signal Slow_Done          : std_logic;
	signal Slow_Serial_DataOut: std_logic;
	signal Slow_Serial_Clock  : std_logic;
	signal Slow_Latch         : std_logic;
	signal Slow_Clear_n       : std_logic;

	-- =========================================================================
	-- Signals: Fast DUT (30 MHz)
	-- =========================================================================
	signal Fast_Busy          : std_logic;
	signal Fast_Done          : std_logic;
	signal Fast_Serial_DataOut: std_logic;
	signal Fast_Serial_Clock  : std_logic;
	signal Fast_Latch         : std_logic;
	signal Fast_Clear_n       : std_logic;

	-- =========================================================================
	-- Signals: Muxed DUT outputs (active DUT based on ShiftFreqSel)
	-- =========================================================================
	signal Serial_DataOut     : std_logic;
	signal Serial_Clock       : std_logic;
	signal Latch              : std_logic;
	signal Clear_n            : std_logic;

	-- =========================================================================
	-- Signals: SN74AC596 Model Daisy Chain Connections
	-- =========================================================================
	signal Model1_QH_prime    : std_logic;  -- First chip serial out
	signal Model2_QH_prime    : std_logic;  -- Second chip serial out

	-- Parallel outputs from models
	signal ModelParallelOut1  : std_logic_vector(7 downto 0);  -- First chip
	signal ModelParallelOut2  : std_logic_vector(7 downto 0);  -- Second chip
	signal ModelParallelOut3  : std_logic_vector(7 downto 0);  -- Third chip

	-- =========================================================================
	-- Component Declarations
	-- =========================================================================
	component io_ShiftRegister_SIPO_DaisyChain_TestController is
		port (
			Clock             : in  std_logic;
			Reset             : in  std_logic;
			Start             : out std_logic;
			DataToSend        : out std_logic_vector(23 downto 0);
			Busy              : in  std_logic;
			Done              : in  std_logic;
			ModelParallelOut1 : in  std_logic_vector(7 downto 0);
			ModelParallelOut2 : in  std_logic_vector(7 downto 0);
			ModelParallelOut3 : in  std_logic_vector(7 downto 0);
			ShiftFreqSel      : out natural range 0 to 1
		);
	end component;

begin
	-- =========================================================================
	-- Clock and Reset Generation (using OSVVM)
	-- =========================================================================
	CreateClock(Clock, 10 ns);    -- 100 MHz clock
	CreateReset(Reset, '1', Clock, 100 ns, 0 ns);

	-- =========================================================================
	-- Test Controller Instance
	-- =========================================================================
	TestCtrl : io_ShiftRegister_SIPO_DaisyChain_TestController
		port map (
			Clock             => Clock,
			Reset             => Reset,
			Start             => Start,
			DataToSend        => DataToSend,
			Busy              => Busy,
			Done              => Done,
			ModelParallelOut1 => ModelParallelOut1,
			ModelParallelOut2 => ModelParallelOut2,
			ModelParallelOut3 => ModelParallelOut3,
			ShiftFreqSel      => ShiftFreqSel
		);

	-- =========================================================================
	-- DUT Instance: Slow (5 MHz Shift Frequency)
	-- =========================================================================
	DUT_Slow : entity PoC.io_ShiftRegister_SIPO_Controller
		generic map (
			BITS                 => BITS,
			CLOCK_FREQ           => CLOCK_FREQ,
			SHIFT_FREQ           => SHIFT_FREQ_SLOW,
			ACTIVE_LOW_CLEAR     => TRUE,
			ADD_OUTPUT_REGISTERS => FALSE
		)
		port map (
			Clock       => Clock,
			Reset       => Reset,
			Start       => Start,
			Busy        => Slow_Busy,
			Done        => Slow_Done,
			DataToSend  => DataToSend,
			SerialOut   => Slow_Serial_DataOut,
			ShiftClock  => Slow_Serial_Clock,
			LatchClock  => Slow_Latch,
			Clear_n     => Slow_Clear_n
		);

	-- =========================================================================
	-- DUT Instance: Fast (30 MHz Shift Frequency)
	-- =========================================================================
	DUT_Fast : entity PoC.io_ShiftRegister_SIPO_Controller
		generic map (
			BITS                 => BITS,
			CLOCK_FREQ           => CLOCK_FREQ,
			SHIFT_FREQ           => SHIFT_FREQ_FAST,
			ACTIVE_LOW_CLEAR     => TRUE,
			ADD_OUTPUT_REGISTERS => FALSE
		)
		port map (
			Clock       => Clock,
			Reset       => Reset,
			Start       => Start,
			Busy        => Fast_Busy,
			Done        => Fast_Done,
			DataToSend  => DataToSend,
			SerialOut   => Fast_Serial_DataOut,
			ShiftClock  => Fast_Serial_Clock,
			LatchClock  => Fast_Latch,
			Clear_n     => Fast_Clear_n
		);

	-- =========================================================================
	-- Multiplexer: Select active DUT outputs based on ShiftFreqSel
	-- =========================================================================
	Busy           <= Slow_Busy           when ShiftFreqSel = 0 else Fast_Busy;
	Done           <= Slow_Done           when ShiftFreqSel = 0 else Fast_Done;
	Serial_DataOut <= Slow_Serial_DataOut when ShiftFreqSel = 0 else Fast_Serial_DataOut;
	Serial_Clock   <= Slow_Serial_Clock   when ShiftFreqSel = 0 else Fast_Serial_Clock;
	Latch          <= Slow_Latch          when ShiftFreqSel = 0 else Fast_Latch;
	Clear_n        <= Slow_Clear_n        when ShiftFreqSel = 0 else Fast_Clear_n;

	-- =========================================================================
	-- SN74AC596 Model Daisy Chain
	-- 
	-- Data flow: FPGA shifts MSB first -> Model3 -> Model2 -> Model1
	-- After 24 shifts:
	--   - Model1 (end of chain) contains bits 23:16 (MSBs, first bits shifted)
	--   - Model2 (middle)       contains bits 15:8
	--   - Model3 (FPGA side)    contains bits 7:0 (LSBs, last bits shifted)
	--
	-- Test expects:
	--   - ModelParallelOut1 = bits 7:0    -> connected to Model3
	--   - ModelParallelOut2 = bits 15:8   -> connected to Model2
	--   - ModelParallelOut3 = bits 23:16  -> connected to Model1
	-- =========================================================================

	-- Model at FPGA side - receives data directly, ends up with LSBs (bits 7:0)
	Model_FPGA_Side : entity work.SN74AC596_Model
		generic map (
			TPD_SRCK_TO_QH_PRIME => 8 ns,
			TPD_RCK_TO_OUTPUTS   => 10 ns,
			TPW_SRCK_HIGH        => 6 ns,
			TPW_SRCK_LOW         => 6 ns,
			TPW_RCK_HIGH         => 6 ns,
			TPW_RCK_LOW          => 6 ns,
			TPW_SCLR_LOW         => 6 ns
		)
		port map (
			SER         => Serial_DataOut,   -- Input from FPGA controller
			SRCK        => Serial_Clock,
			RCK         => Latch,
			SCLR_n      => Clear_n,
			ParallelOut => ModelParallelOut1,  -- bits 7:0 (LSBs)
			QH_Prime    => Model2_QH_prime     -- Serial out to middle chip
		);

	-- Model in middle - receives from FPGA side chip
	Model_Middle : entity work.SN74AC596_Model
		generic map (
			TPD_SRCK_TO_QH_PRIME => 8 ns,
			TPD_RCK_TO_OUTPUTS   => 10 ns,
			TPW_SRCK_HIGH        => 6 ns,
			TPW_SRCK_LOW         => 6 ns,
			TPW_RCK_HIGH         => 6 ns,
			TPW_RCK_LOW          => 6 ns,
			TPW_SCLR_LOW         => 6 ns
		)
		port map (
			SER         => Model2_QH_prime,  -- Input from FPGA-side chip
			SRCK        => Serial_Clock,
			RCK         => Latch,
			SCLR_n      => Clear_n,
			ParallelOut => ModelParallelOut2,  -- bits 15:8
			QH_Prime    => Model1_QH_prime     -- Serial out to end chip
		);

	-- Model at end of chain - ends up with MSBs (bits 23:16)
	Model_End : entity work.SN74AC596_Model
		generic map (
			TPD_SRCK_TO_QH_PRIME => 8 ns,
			TPD_RCK_TO_OUTPUTS   => 10 ns,
			TPW_SRCK_HIGH        => 6 ns,
			TPW_SRCK_LOW         => 6 ns,
			TPW_RCK_HIGH         => 6 ns,
			TPW_RCK_LOW          => 6 ns,
			TPW_SCLR_LOW         => 6 ns
		)
		port map (
			SER         => Model1_QH_prime,  -- Input from middle chip
			SRCK        => Serial_Clock,
			RCK         => Latch,
			SCLR_n      => Clear_n,
			ParallelOut => ModelParallelOut3,  -- bits 23:16 (MSBs)
			QH_Prime    => open                -- End of chain
		);

end architecture;
