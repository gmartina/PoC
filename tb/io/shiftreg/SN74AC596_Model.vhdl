-- EMACS settings: -*-  tab-width: 2; indent-tabs-mode: t -*-
-- vim: tabstop=2:shiftwidth=2:noexpandtab
-- kate: tab-width 2; replace-tabs off; indent-width 2;
-- =============================================================================
-- Authors:         Gustavo Martin
--
-- Entity:          SN74AC596_Model
--
-- Description:
-- -------------------------------------
-- Behavioral verification model for the SN74AC596 8-Bit Shift Register
-- with Storage Register and Open-Drain Outputs.
--
-- This model simulates the behavior of the SN74AC596 for verification purposes.
-- It includes timing checks to ensure the DUT meets minimum timing requirements.
--
-- Pin Description:
--   SER     - Serial data input
--   SRCK    - Shift register clock (rising edge shifts data)
--   RCK     - Storage register clock (rising edge latches to outputs)
--   SCLR_n  - Shift register clear (active low, asynchronous)
--   QA-QH   - Parallel outputs (directly active, directly active low for open-drain)
--   QH'     - Serial output (directly active, connected to QH of shift register for cascading)
--
-- Functional Description:
--   - On SRCK rising edge: Shift register shifts, SER enters at QA position
--   - On RCK rising edge: Shift register contents transferred to storage register
--   - When SCLR_n is low: Shift register is cleared (storage register unaffected)
--   - QA-QH outputs reflect storage register contents
--   - QH' reflects shift register QH (for daisy chain cascading)
--
-- Timing Parameters (from datasheet, typical VCC=5V):
--   - tpd (SRCK to QH'): ~11 ns
--   - tpd (RCK to outputs): ~12 ns
--   - tpd (SCLR_n to QH'): ~10 ns
--   - tsu (SER setup to SRCK): ~10 ns
--   - th (SER hold after SRCK): ~0 ns
--   - tw (SRCK/RCK pulse width): ~6 ns
--   - tw (SCLR_n pulse width): ~10 ns
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

library osvvm;
context osvvm.OsvvmContext;


entity SN74AC596_Model is
	generic (
		-- Propagation delays
		TPD_SRCK_TO_QH_PRIME : time := 11 ns;  -- Shift clock to QH'
		TPD_RCK_TO_OUTPUTS   : time := 12 ns;  -- Latch clock to parallel outputs
		TPD_SCLR_TO_QH_PRIME : time := 10 ns;  -- Clear to QH'

		-- Setup and hold times
		TSU_SER              : time := 10 ns;  -- Serial data setup before SRCK
		TH_SER               : time := 0 ns;   -- Serial data hold after SRCK

		-- Minimum pulse widths
		TPW_SRCK_HIGH        : time := 6 ns;   -- Minimum SRCK high pulse
		TPW_SRCK_LOW         : time := 6 ns;   -- Minimum SRCK low pulse
		TPW_RCK_HIGH         : time := 6 ns;   -- Minimum RCK high pulse
		TPW_RCK_LOW          : time := 6 ns;   -- Minimum RCK low pulse
		TPW_SCLR_LOW         : time := 10 ns;  -- Minimum SCLR_n low pulse

		-- Alert log ID for timing violations (optional, can be set externally)
		ALERT_LOG_ID         : AlertLogIDType := ALERTLOG_DEFAULT_ID
	);
	port (
		-- Inputs
		SER      : in  std_logic := '0';  -- Serial data input
		SRCK     : in  std_logic := '0';  -- Shift register clock
		RCK      : in  std_logic := '0';  -- Storage register clock (latch)
		SCLR_n   : in  std_logic := '1';  -- Shift register clear (active low)

		-- Outputs - directly active (directly active low compatible for open-drain)
		QA       : out std_logic;         -- Parallel output A (LSB of storage register)
		QB       : out std_logic;         -- Parallel output B
		QC       : out std_logic;         -- Parallel output C
		QD       : out std_logic;         -- Parallel output D
		QE       : out std_logic;         -- Parallel output E
		QF       : out std_logic;         -- Parallel output F
		QG       : out std_logic;         -- Parallel output G
		QH       : out std_logic;         -- Parallel output H (MSB of storage register)

		-- Vector interface (alternative to individual pins)
		ParallelOut : out std_logic_vector(7 downto 0);  -- All outputs as vector

		-- Serial output for cascading
		QH_Prime : out std_logic          -- Serial output (MSB of shift register)
	);
end entity;


architecture Behavioral of SN74AC596_Model is
	-- Internal registers
	signal ShiftReg   : std_logic_vector(7 downto 0) := (others => '0');
	signal StorageReg : std_logic_vector(7 downto 0) := (others => '0');

	-- Timing tracking
	signal LastSRCK_Rising  : time := 0 ns;
	signal LastSRCK_Falling : time := 0 ns;
	signal LastRCK_Rising   : time := 0 ns;
	signal LastRCK_Falling  : time := 0 ns;
	signal LastSER_Change   : time := 0 ns;
	signal LastSCLR_Falling : time := 0 ns;

	-- Alert ID for this model
	constant ModelID : AlertLogIDType := NewID("SN74AC596_Model", ALERT_LOG_ID);

begin
	-- ==========================================================================
	-- Serial Data Input Tracking (for setup/hold checks)
	-- ==========================================================================
	process(SER)
	begin
		LastSER_Change <= now;
	end process;

	-- ==========================================================================
	-- Shift Register Clock (SRCK) - Shifts data on rising edge
	-- ==========================================================================
	process(SRCK, SCLR_n)
		variable SetupTime : time;
	begin
		-- Asynchronous clear
		if SCLR_n = '0' then
			ShiftReg <= (others => '0') after TPD_SCLR_TO_QH_PRIME;

		-- Shift on rising edge of SRCK
		elsif rising_edge(SRCK) then
			-- Check setup time
			SetupTime := now - LastSER_Change;
			if SetupTime < TSU_SER and now > 0 ns then
				Alert(ModelID, "SER setup time violation: " &
					to_string(SetupTime, 1 ns) & " < " & to_string(TSU_SER, 1 ns),
					WARNING);
			end if;

			-- Check SRCK low pulse width
			if now - LastSRCK_Falling < TPW_SRCK_LOW and LastSRCK_Falling > 0 ns then
				Alert(ModelID, "SRCK low pulse width violation: " &
					to_string(now - LastSRCK_Falling, 1 ns) & " < " & to_string(TPW_SRCK_LOW, 1 ns),
					WARNING);
			end if;

			-- Shift operation: SER -> QA, QA -> QB, ... QG -> QH
			ShiftReg <= ShiftReg(6 downto 0) & SER after TPD_SRCK_TO_QH_PRIME;

			LastSRCK_Rising <= now;

		elsif falling_edge(SRCK) then
			-- Check SRCK high pulse width
			if now - LastSRCK_Rising < TPW_SRCK_HIGH and LastSRCK_Rising > 0 ns then
				Alert(ModelID, "SRCK high pulse width violation: " &
					to_string(now - LastSRCK_Rising, 1 ns) & " < " & to_string(TPW_SRCK_HIGH, 1 ns),
					WARNING);
			end if;

			LastSRCK_Falling <= now;
		end if;
	end process;

	-- ==========================================================================
	-- Storage Register Clock (RCK) - Latches data on rising edge
	-- ==========================================================================
	process(RCK)
	begin
		if rising_edge(RCK) then
			-- Check RCK low pulse width
			if now - LastRCK_Falling < TPW_RCK_LOW and LastRCK_Falling > 0 ns then
				Alert(ModelID, "RCK low pulse width violation: " &
					to_string(now - LastRCK_Falling, 1 ns) & " < " & to_string(TPW_RCK_LOW, 1 ns),
					WARNING);
			end if;

			-- Latch shift register to storage register
			StorageReg <= ShiftReg after TPD_RCK_TO_OUTPUTS;

			LastRCK_Rising <= now;

		elsif falling_edge(RCK) then
			-- Check RCK high pulse width
			if now - LastRCK_Rising < TPW_RCK_HIGH and LastRCK_Rising > 0 ns then
				Alert(ModelID, "RCK high pulse width violation: " &
					to_string(now - LastRCK_Rising, 1 ns) & " < " & to_string(TPW_RCK_HIGH, 1 ns),
					WARNING);
			end if;

			LastRCK_Falling <= now;
		end if;
	end process;

	-- ==========================================================================
	-- Clear Signal Tracking
	-- ==========================================================================
	process(SCLR_n)
	begin
		if falling_edge(SCLR_n) then
			LastSCLR_Falling <= now;
		elsif rising_edge(SCLR_n) then
			-- Check SCLR_n low pulse width
			if now - LastSCLR_Falling < TPW_SCLR_LOW and LastSCLR_Falling > 0 ns then
				Alert(ModelID, "SCLR_n low pulse width violation: " &
					to_string(now - LastSCLR_Falling, 1 ns) & " < " & to_string(TPW_SCLR_LOW, 1 ns),
					WARNING);
			end if;
		end if;
	end process;

	-- ==========================================================================
	-- Output Assignments
	-- ==========================================================================

	-- Individual parallel outputs from storage register
	QA <= StorageReg(0);
	QB <= StorageReg(1);
	QC <= StorageReg(2);
	QD <= StorageReg(3);
	QE <= StorageReg(4);
	QF <= StorageReg(5);
	QG <= StorageReg(6);
	QH <= StorageReg(7);

	-- Vector output
	ParallelOut <= StorageReg;

	-- Serial output for cascading (from shift register, not storage register)
	QH_Prime <= ShiftReg(7);

end architecture;
