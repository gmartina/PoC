-- EMACS settings: -*-  tab-width: 2; indent-tabs-mode: t -*-
-- vim: tabstop=2:shiftwidth=2:noexpandtab
-- kate: tab-width 2; replace-tabs off; indent-width 2;
-- =============================================================================
-- Authors:         Gustavo Martin
--
-- Entity:          io_ShiftRegister_SIPO_DaisyChain_TestController
--
-- Description:
-- -------------------------------------
-- Test controller entity for SIPO shift register daisy chain verification.
-- This entity defines the interface between the test harness and the test
-- architectures. Different test architectures can be bound to this entity
-- for various test scenarios with 3 daisy-chained chips (24 bits total).
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


entity io_ShiftRegister_SIPO_DaisyChain_TestController is
	port (
		-- System signals from harness
		Clock           : in  std_logic;
		Reset           : in  std_logic;

		-- Control signals to DUT
		Start           : out std_logic;
		DataToSend      : out std_logic_vector(23 downto 0);

		-- Status signals from DUT
		Busy            : in  std_logic;
		Done            : in  std_logic;

		-- Data from SN74AC596 models (parallel outputs)
		ModelParallelOut1 : in  std_logic_vector(7 downto 0);  -- First chip in chain
		ModelParallelOut2 : in  std_logic_vector(7 downto 0);  -- Second chip in chain
		ModelParallelOut3 : in  std_logic_vector(7 downto 0);  -- Third chip in chain

		-- Select which shift frequency configuration to use
		-- 0 = 5 MHz, 1 = 30 MHz
		ShiftFreqSel    : out natural range 0 to 1
	);
end entity;
