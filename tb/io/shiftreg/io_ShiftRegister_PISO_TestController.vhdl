-- EMACS settings: -*-  tab-width: 2; indent-tabs-mode: t -*-
-- vim: tabstop=2:shiftwidth=2:noexpandtab
-- kate: tab-width 2; replace-tabs off; indent-width 2;
-- =============================================================================
-- Authors:         Gustavo Martin
--
-- Entity:          io_ShiftRegister_PISO_TestController
--
-- Description:
-- -------------------------------------
-- Test controller for the PISO shift register controller.
-- This entity defines the interface for test architectures.
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


entity io_ShiftRegister_PISO_TestController is
	port (
		-- System signals
		Clock           : in  std_logic;
		Reset           : in  std_logic;

		-- DUT selection:
		--   0 = 5 MHz shift clock, ACTIVE_LOW_CLK_INHIBIT=FALSE
		--   1 = 30 MHz shift clock, ACTIVE_LOW_CLK_INHIBIT=FALSE
		--   2 = 5 MHz shift clock, ACTIVE_LOW_CLK_INHIBIT=TRUE
		ShiftFreqSel    : out natural range 0 to 2 := 0;

		-- DUT control interface
		Start           : out std_logic := '0';
		Busy            : in  std_logic;
		Valid           : in  std_logic;
		DataReceived    : in  std_logic_vector(7 downto 0);

		-- Shift register bus signals (directly observable)
		ClockInhibit    : in  std_logic;

		-- Model control interface
		ModelParallelIn : out std_logic_vector(7 downto 0) := (others => '0')
	);
end entity;
