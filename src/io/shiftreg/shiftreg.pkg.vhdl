-- EMACS settings: -*-  tab-width: 2; indent-tabs-mode: t -*-
-- vim: tabstop=2:shiftwidth=2:noexpandtab
-- kate: tab-width 2; replace-tabs off; indent-width 2;
-- =============================================================================
-- Authors:         Gustavo Martin
--
-- Package:         VHDL package for component declarations, types and
--                  functions associated to the PoC.io.shiftreg namespace
--
-- Description:
-- -------------------------------------
-- This package provides types, constants, and component declarations for
-- shift register controllers, including:
--   - PISO (Parallel-In Serial-Out) controllers like SN74AC165
--   - SIPO (Serial-In Parallel-Out) controllers like SN74HC595
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

package shiftreg is

	----------------------------------
	-- Component Declarations
	----------------------------------

	-- PISO Controller for shift registers like SN74AC165
	component io_ShiftRegister_PISO_Controller is
		generic (
			BITS                    : positive := 8;
			ACTIVE_LOW_LOAD         : boolean  := TRUE;
			ACTIVE_LOW_CLK_INHIBIT  : boolean  := FALSE;
			ACTIVE_LOW_DATA         : boolean  := FALSE;
			ACTIVE_LOW_SERIAL_IN    : boolean  := FALSE;
			CLOCK_FREQ              : FREQ     := 100 MHz;
			SHIFT_FREQ              : FREQ     := 1 MHz;
			ADD_INPUT_SYNCHRONIZERS : boolean  := TRUE
		);
		port (
			Clock           : in  std_logic;
			Reset           : in  std_logic;
			Start           : in  std_logic;
			Busy            : out std_logic;
			Valid           : out std_logic;
			DataReceived    : out std_logic_vector(BITS - 1 downto 0);
			ShiftLoad_n     : out std_logic;
			SerialClock     : out std_logic;
			ClockInhibit    : out std_logic;
			SerialIn        : out std_logic;
			SerialDataIn    : in  std_logic
		);
	end component;

	-- SIPO Controller for shift registers like SN74AC596
	component io_ShiftRegister_SIPO_Controller is
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
			Clock       : in  std_logic;
			Reset       : in  std_logic;
			Start       : in  std_logic;
			Busy        : out std_logic;
			Done        : out std_logic;
			DataToSend  : in  std_logic_vector(BITS - 1 downto 0);
			SerialOut   : out std_logic;
			ShiftClock  : out std_logic;
			LatchClock  : out std_logic;
			Clear_n     : out std_logic
		);
	end component;

end package;


package body shiftreg is
	-- Package body (empty for now, can add functions later)
end package body;
