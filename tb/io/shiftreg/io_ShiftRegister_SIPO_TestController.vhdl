-- EMACS settings: -*-  tab-width: 2; indent-tabs-mode: t -*-
-- vim: tabstop=2:shiftwidth=2:noexpandtab
-- kate: tab-width 2; replace-tabs off; indent-width 2;
-- =============================================================================
-- Authors:         Gustavo Martin
--
-- Entity:          io_ShiftRegister_SIPO_TestController
--
-- Description:
-- -------------------------------------
-- Test controller entity for the SIPO shift register controller.
-- This entity defines the interface for test architectures.
--
-- The test controller drives:
--   - ShiftFreqSel: Selects which DUT frequency to use (0=5MHz, 1=30MHz)
--   - Start: Initiates a write operation
--   - DataToSend: Data to be shifted out to the model
--
-- And monitors:
--   - Busy: DUT is performing a shift operation
--   - Done: DUT has completed the operation
--   - ModelParallelOut: Data captured by the model (for verification)
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


entity io_ShiftRegister_SIPO_TestController is
	port (
		-- System signals
		Clock           : in  std_logic;
		Reset           : in  std_logic;

		-- DUT selection:
		--   0 = 5 MHz shift clock, ACTIVE_LOW_CLEAR=TRUE
		--   1 = 30 MHz shift clock, ACTIVE_LOW_CLEAR=TRUE
		--   2 = 5 MHz shift clock, ACTIVE_LOW_CLEAR=FALSE
		ShiftFreqSel    : out natural range 0 to 2 := 0;

		-- DUT control interface
		Start           : out std_logic := '0';
		Busy            : in  std_logic;
		Done            : in  std_logic;
		DataToSend      : out std_logic_vector(7 downto 0) := (others => '0');

		-- Shift register bus signals (directly observable)
		Clear_n         : in  std_logic;

		-- Model readback interface (from SN74AC596 model)
		ModelParallelOut : in  std_logic_vector(7 downto 0)
	);
end entity;
