-- EMACS settings: -*-  tab-width: 2; indent-tabs-mode: t -*-
-- vim: tabstop=2:shiftwidth=2:noexpandtab
-- kate: tab-width 2; replace-tabs off; indent-width 2;
-- =============================================================================
-- Authors:         Gustavo Martin
--
-- Entity:          SN74AC165_Model
--
-- Description:
-- -------------------------------------
-- Behavioral model of the SN74AC165-Q1 8-Bit Parallel Input Shift Register.
-- This verification component simulates the behavior of the TI SN74AC165-Q1
-- chip for testbench use.
--
-- The SN74AC165-Q1 is an 8-bit parallel-load shift register that shifts data
-- in the direction of QA toward QH. Parallel loading is accomplished by
-- applying a LOW signal to the Shift/Load (SH/LD) input while the clock
-- is held either HIGH or LOW.
--
-- Pin Description:
--   SH_LD_n     - Shift/Load input (active LOW for parallel load)
--   CLK         - Clock input (positive edge triggered for shift)
--   CLK_INH     - Clock inhibit (HIGH disables clocking)
--   SER         - Serial input for cascading
--   A to H      - Parallel data inputs (directly into the shift register)
--   QH          - Serial output (directly from the last flip-flop)
--   QH_n        - Complementary serial output
--
-- Function Table:
--   SH/LD | CLK_INH | CLK      | Function
--   ------+---------+----------+-----------------
--     L   |    X    |    X     | Load parallel data
--     H   |    L    | Rising   | Shift data
--     H   |    H    |    X     | Inhibit (no change)
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

library osvvm;
context osvvm.OsvvmContext;


entity SN74AC165_Model is
	generic (
		-- Timing parameters (from datasheet, typical values at VCC=5V, TA=25°C)
		TPD_SH_LD_TO_QH  : time := 12 ns;   -- Propagation delay from SH/LD to QH
		TPD_CLK_TO_QH    : time := 11 ns;   -- Propagation delay from CLK to QH
		TSU_DATA         : time := 10 ns;   -- Setup time, parallel data before SH/LD rising
		TH_DATA          : time := 0 ns;    -- Hold time, parallel data after SH/LD rising
		TSU_SER          : time := 10 ns;   -- Setup time, serial input before CLK rising
		TH_SER           : time := 0 ns;    -- Hold time, serial input after CLK rising
		TPW_CLK_HIGH     : time := 6 ns;    -- Minimum clock high pulse width
		TPW_CLK_LOW      : time := 6 ns;    -- Minimum clock low pulse width
		TPW_SH_LD_LOW    : time := 10 ns    -- Minimum SH/LD low pulse width
	);
	port (
		-- Parallel data inputs (directly to the flip-flops)
		A         : in  std_logic := '0';
		B         : in  std_logic := '0';
		C         : in  std_logic := '0';
		D         : in  std_logic := '0';
		E         : in  std_logic := '0';
		F         : in  std_logic := '0';
		G         : in  std_logic := '0';
		H         : in  std_logic := '0';

		-- Alternative parallel input as vector
		ParallelIn : in std_logic_vector(7 downto 0) := (others => '0');
		UseVector  : in boolean := TRUE;  -- If TRUE, use ParallelIn; if FALSE, use A-H

		-- Control inputs
		SH_LD_n   : in  std_logic := '1';  -- Shift/Load control (active LOW)
		CLK       : in  std_logic := '0';  -- Clock input
		CLK_INH   : in  std_logic := '0';  -- Clock inhibit
		SER       : in  std_logic := '0';  -- Serial input for cascading

		-- Serial outputs
		QH        : out std_logic;         -- Serial output
		QH_n      : out std_logic          -- Complementary serial output
	);
end entity;


architecture Behavioral of SN74AC165_Model is
	-- Internal shift register
	signal ShiftReg : std_logic_vector(7 downto 0) := (others => '0');

	-- Previous clock value for edge detection
	signal CLK_prev : std_logic := '0';

	-- Combined parallel input
	signal ParallelData : std_logic_vector(7 downto 0);

	-- Internal gated clock
	signal CLK_gated : std_logic;

	-- Alert log ID for this model
	constant ModelID : AlertLogIDType := NewID("SN74AC165_Model");

begin
	-- Select parallel input source
	ParallelData <= ParallelIn when UseVector else (H & G & F & E & D & C & B & A);

	-- Gated clock (CLK AND NOT CLK_INH)
	CLK_gated <= CLK and not CLK_INH;

	-- Main process: handles parallel load and shift operations
	process(SH_LD_n, CLK_gated, ParallelData)
		variable Rising_CLK : boolean;
	begin
		-- Detect rising edge on gated clock
		Rising_CLK := (CLK_gated = '1' and CLK_prev = '0');
		CLK_prev <= CLK_gated after 0 ns;

		-- Parallel load (asynchronous, when SH/LD_n is LOW)
		if SH_LD_n = '0' then
			ShiftReg <= ParallelData after TPD_SH_LD_TO_QH;
		-- Shift on rising edge of gated clock (when SH/LD_n is HIGH)
		elsif Rising_CLK then
			-- Shift left: SER goes into position 0 (A), and data shifts toward QH
			ShiftReg <= ShiftReg(6 downto 0) & SER after TPD_CLK_TO_QH;
		end if;
	end process;

	-- Output assignments
	-- QH is the MSB (position H, index 7)
	QH   <= ShiftReg(7);
	QH_n <= not ShiftReg(7);

	-- Timing checks (simulation only)
	-- synthesis translate_off
	process(SH_LD_n)
		variable LastFallingEdge : time := 0 ns;
	begin
		if falling_edge(SH_LD_n) then
			LastFallingEdge := now;
		elsif rising_edge(SH_LD_n) then
			if (now - LastFallingEdge) < TPW_SH_LD_LOW then
				AlertIf(ModelID, TRUE,
					"SH/LD low pulse width violation: " &
					to_string(now - LastFallingEdge) & " < " & to_string(TPW_SH_LD_LOW),
					WARNING);
			end if;
		end if;
	end process;

	process(CLK_gated)
		variable LastRisingEdge  : time := 0 ns;
		variable LastFallingEdge : time := 0 ns;
	begin
		if rising_edge(CLK_gated) then
			if LastFallingEdge > 0 ns and (now - LastFallingEdge) < TPW_CLK_LOW then
				AlertIf(ModelID, TRUE,
					"CLK low pulse width violation: " &
					to_string(now - LastFallingEdge) & " < " & to_string(TPW_CLK_LOW),
					WARNING);
			end if;
			LastRisingEdge := now;
		elsif falling_edge(CLK_gated) then
			if LastRisingEdge > 0 ns and (now - LastRisingEdge) < TPW_CLK_HIGH then
				AlertIf(ModelID, TRUE,
					"CLK high pulse width violation: " &
					to_string(now - LastRisingEdge) & " < " & to_string(TPW_CLK_HIGH),
					WARNING);
			end if;
			LastFallingEdge := now;
		end if;
	end process;
	-- synthesis translate_on

end architecture;
