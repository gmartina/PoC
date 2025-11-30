-- EMACS settings: -*-  tab-width: 2; indent-tabs-mode: t -*-
-- vim: tabstop=2:shiftwidth=2:noexpandtab
-- kate: tab-width 2; replace-tabs off; indent-width 2;
-- =============================================================================
-- Authors:         Gustavo Martin
--
-- Entity:          io_ShiftRegister_PISO_ClockInhibit
--
-- Description:
-- -------------------------------------
-- Test case for verifying ClockInhibit signal behavior in the PISO shift
-- register controller.
--
-- This test verifies:
--   1. ClockInhibit signal is HIGH during idle state (ACTIVE_LOW_CLK_INHIBIT=FALSE)
--   2. ClockInhibit signal is LOW during shift operation (ACTIVE_LOW_CLK_INHIBIT=FALSE)
--   3. ClockInhibit signal is LOW during idle state (ACTIVE_LOW_CLK_INHIBIT=TRUE)
--   4. ClockInhibit signal is HIGH during shift operation (ACTIVE_LOW_CLK_INHIBIT=TRUE)
--   5. Data transfers correctly in both configurations
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
use     PoC.utils.all;
use     PoC.vectors.all;
use     PoC.strings.all;


architecture ClockInhibit of io_ShiftRegister_PISO_TestController is
	-- Test synchronization barrier
	signal TestDone : integer_barrier := 1;

	-- Alert log ID for this test controller
	constant TCID : AlertLogIDType := NewID("TestCtrl");

begin
	-- ==========================================================================
	-- Control Process: Manages test execution and reporting
	-- ==========================================================================
	ControlProc : process
		constant ProcID  : AlertLogIDType := NewID("ControlProc", TCID);
		constant TIMEOUT : time := 100 ms;
	begin
		SetTestName("io_ShiftRegister_PISO_ClockInhibit");

		-- Configure logging
		SetLogEnable(PASSED, FALSE);
		SetLogEnable(INFO,   FALSE);
		SetLogEnable(DEBUG,  FALSE);
		wait for 0 ns; wait for 0 ns;

		TranscriptOpen;
		SetTranscriptMirror(TRUE);

		-- Wait for reset to deassert
		wait until Reset = '0';
		ClearAlerts;

		-- Wait for test completion or timeout
		WaitForBarrier(TestDone, TIMEOUT);
		AlertIf(ProcID, now >= TIMEOUT,     "Test finished due to timeout");
		AlertIf(ProcID, GetAffirmCount < 1, "Test is not Self-Checking");

		EndOfTestReports(ReportAll => TRUE);
		std.env.stop;
	end process;

	-- ==========================================================================
	-- Checker Process: Performs the actual testing
	-- ==========================================================================
	CheckerProc : process
		constant ProcID : AlertLogIDType := NewID("CheckerProc", TCID);

		-- Test data pattern
		constant TEST_DATA : std_logic_vector(7 downto 0) := x"A5";

		-- Procedure to test ClockInhibit with normal polarity (ACTIVE_LOW_CLK_INHIBIT=FALSE)
		-- Expected: ClockInhibit = '1' during idle, '0' during shift
		procedure TestClockInhibitNormal is
			variable saw_low_during_busy : boolean := FALSE;
		begin
			Log(ProcID, "Testing ClockInhibit with ACTIVE_LOW_CLK_INHIBIT=FALSE", INFO);

			-- Verify ClockInhibit is HIGH during idle (before starting)
			AffirmIf(ProcID,
				ClockInhibit = '1',
				"ClockInhibit is HIGH during idle (before start)",
				" Got: " & to_string(ClockInhibit)
			);

			-- Set the parallel data on the model
			ModelParallelIn <= TEST_DATA;
			WaitForClock(Clock, 2);

			-- Initiate a read operation
			Start <= '1';
			WaitForClock(Clock);
			Start <= '0';

			-- Wait for busy to assert
			WaitForClock(Clock);
			AffirmIf(ProcID,
				Busy = '1',
				"Busy signal asserted after start"
			);

			-- Monitor ClockInhibit during shift operation
			-- It should go LOW at some point during the shift
			while Busy = '1' loop
				if ClockInhibit = '0' then
					saw_low_during_busy := TRUE;
				end if;
				WaitForClock(Clock);
			end loop;

			AffirmIf(ProcID,
				saw_low_during_busy,
				"ClockInhibit went LOW during shift operation"
			);

			-- Wait for valid signal (only if not already high)
			if Valid /= '1' then
				wait until Valid = '1';
			end if;

			-- After operation completes, ClockInhibit should return to HIGH
			WaitForClock(Clock, 3);
			AffirmIf(ProcID,
				ClockInhibit = '1',
				"ClockInhibit returned to HIGH after operation",
				" Got: " & to_string(ClockInhibit)
			);

			-- Verify data was received correctly
			AffirmIf(ProcID,
				DataReceived = TEST_DATA,
				"Data received correctly: 0x" & to_hstring(DataReceived),
				" Expected: 0x" & to_hstring(TEST_DATA)
			);

			WaitForClock(Clock, 5);
		end procedure;

		-- Procedure to test ClockInhibit with inverted polarity (ACTIVE_LOW_CLK_INHIBIT=TRUE)
		-- Expected: ClockInhibit = '0' during idle, '1' during shift
		procedure TestClockInhibitActiveLow is
			variable saw_high_during_busy : boolean := FALSE;
		begin
			Log(ProcID, "Testing ClockInhibit with ACTIVE_LOW_CLK_INHIBIT=TRUE", INFO);

			-- Verify ClockInhibit is LOW during idle (before starting)
			AffirmIf(ProcID,
				ClockInhibit = '0',
				"ClockInhibit is LOW during idle (active-low mode, before start)",
				" Got: " & to_string(ClockInhibit)
			);

			-- Set the parallel data on the model
			ModelParallelIn <= TEST_DATA;
			WaitForClock(Clock, 2);

			-- Initiate a read operation
			Start <= '1';
			WaitForClock(Clock);
			Start <= '0';

			-- Wait for busy to assert
			WaitForClock(Clock);
			AffirmIf(ProcID,
				Busy = '1',
				"Busy signal asserted after start (active-low mode)"
			);

			-- Monitor ClockInhibit during shift operation
			-- It should go HIGH at some point during the shift (inverted polarity)
			while Busy = '1' loop
				if ClockInhibit = '1' then
					saw_high_during_busy := TRUE;
				end if;
				WaitForClock(Clock);
			end loop;

			AffirmIf(ProcID,
				saw_high_during_busy,
				"ClockInhibit went HIGH during shift operation (active-low mode)"
			);

			-- Wait for valid signal (only if not already high)
			if Valid /= '1' then
				wait until Valid = '1';
			end if;

			-- After operation completes, ClockInhibit should return to LOW
			WaitForClock(Clock, 3);
			AffirmIf(ProcID,
				ClockInhibit = '0',
				"ClockInhibit returned to LOW after operation (active-low mode)",
				" Got: " & to_string(ClockInhibit)
			);

			-- Verify data was received correctly
			AffirmIf(ProcID,
				DataReceived = TEST_DATA,
				"Data received correctly (active-low mode): 0x" & to_hstring(DataReceived),
				" Expected: 0x" & to_hstring(TEST_DATA)
			);

			WaitForClock(Clock, 5);
		end procedure;

	begin
		-- Initialize outputs
		Start           <= '0';
		ModelParallelIn <= (others => '0');
		ShiftFreqSel    <= 0;  -- Use 5 MHz, ACTIVE_LOW_CLK_INHIBIT=FALSE

		-- Wait for reset to deassert
		wait until Reset = '0';
		WaitForClock(Clock, 5);

		Log(ProcID, "========================================================", INFO);
		Log(ProcID, "PISO ClockInhibit Signal Verification Tests", INFO);
		Log(ProcID, "========================================================", INFO);

		-- =====================================================================
		-- Test 1: Normal polarity (ACTIVE_LOW_CLK_INHIBIT=FALSE)
		-- =====================================================================
		Log(ProcID, "", INFO);
		Log(ProcID, "--- Test 1: Normal Polarity (DUT 0) ---", INFO);
		ShiftFreqSel <= 0;
		WaitForClock(Clock, 5);
		TestClockInhibitNormal;

		-- =====================================================================
		-- Test 2: Inverted polarity (ACTIVE_LOW_CLK_INHIBIT=TRUE)
		-- =====================================================================
		Log(ProcID, "", INFO);
		Log(ProcID, "--- Test 2: Active-Low Polarity (DUT 2) ---", INFO);
		ShiftFreqSel <= 2;
		WaitForClock(Clock, 5);
		TestClockInhibitActiveLow;

		-- =====================================================================
		-- Test 3: Verify data integrity with multiple patterns
		-- =====================================================================
		Log(ProcID, "", INFO);
		Log(ProcID, "--- Test 3: Multiple Data Patterns ---", INFO);

		-- Test with DUT 0 (normal polarity)
		ShiftFreqSel <= 0;
		WaitForClock(Clock, 5);

		-- Pattern 0: 0xAA
		ModelParallelIn <= x"AA";
		WaitForClock(Clock, 2);
		Start <= '1';
		WaitForClock(Clock);
		Start <= '0';
		wait until Valid = '1';
		AffirmIf(ProcID, DataReceived = x"AA", "Pattern 0 (normal): 0x" & to_hstring(DataReceived), " Expected: 0xAA");
		WaitForClock(Clock, 5);

		-- Pattern 1: 0x55
		ModelParallelIn <= x"55";
		WaitForClock(Clock, 2);
		Start <= '1';
		WaitForClock(Clock);
		Start <= '0';
		wait until Valid = '1';
		AffirmIf(ProcID, DataReceived = x"55", "Pattern 1 (normal): 0x" & to_hstring(DataReceived), " Expected: 0x55");
		WaitForClock(Clock, 5);

		-- Pattern 2: 0xFF
		ModelParallelIn <= x"FF";
		WaitForClock(Clock, 2);
		Start <= '1';
		WaitForClock(Clock);
		Start <= '0';
		wait until Valid = '1';
		AffirmIf(ProcID, DataReceived = x"FF", "Pattern 2 (normal): 0x" & to_hstring(DataReceived), " Expected: 0xFF");
		WaitForClock(Clock, 5);

		-- Pattern 3: 0x00
		ModelParallelIn <= x"00";
		WaitForClock(Clock, 2);
		Start <= '1';
		WaitForClock(Clock);
		Start <= '0';
		wait until Valid = '1';
		AffirmIf(ProcID, DataReceived = x"00", "Pattern 3 (normal): 0x" & to_hstring(DataReceived), " Expected: 0x00");
		WaitForClock(Clock, 5);

		-- Test with DUT 2 (active-low polarity)
		ShiftFreqSel <= 2;
		WaitForClock(Clock, 5);

		-- Pattern 0: 0xF0
		ModelParallelIn <= x"F0";
		WaitForClock(Clock, 2);
		Start <= '1';
		WaitForClock(Clock);
		Start <= '0';
		wait until Valid = '1';
		AffirmIf(ProcID, DataReceived = x"F0", "Pattern 0 (active-low): 0x" & to_hstring(DataReceived), " Expected: 0xF0");
		WaitForClock(Clock, 5);

		-- Pattern 1: 0x0F
		ModelParallelIn <= x"0F";
		WaitForClock(Clock, 2);
		Start <= '1';
		WaitForClock(Clock);
		Start <= '0';
		wait until Valid = '1';
		AffirmIf(ProcID, DataReceived = x"0F", "Pattern 1 (active-low): 0x" & to_hstring(DataReceived), " Expected: 0x0F");
		WaitForClock(Clock, 5);

		-- Pattern 2: 0x3C
		ModelParallelIn <= x"3C";
		WaitForClock(Clock, 2);
		Start <= '1';
		WaitForClock(Clock);
		Start <= '0';
		wait until Valid = '1';
		AffirmIf(ProcID, DataReceived = x"3C", "Pattern 2 (active-low): 0x" & to_hstring(DataReceived), " Expected: 0x3C");
		WaitForClock(Clock, 5);

		-- Pattern 3: 0xC3
		ModelParallelIn <= x"C3";
		WaitForClock(Clock, 2);
		Start <= '1';
		WaitForClock(Clock);
		Start <= '0';
		wait until Valid = '1';
		AffirmIf(ProcID, DataReceived = x"C3", "Pattern 3 (active-low): 0x" & to_hstring(DataReceived), " Expected: 0xC3");
		WaitForClock(Clock, 5);

		Log(ProcID, "", INFO);
		Log(ProcID, "========================================================", INFO);
		Log(ProcID, "All ClockInhibit tests completed successfully!", INFO);
		Log(ProcID, "========================================================", INFO);

		-- Signal test completion
		WaitForBarrier(TestDone);
		wait;
	end process;

end architecture;


-- =============================================================================
-- Configuration: Binds the ClockInhibit test architecture to the test harness
-- =============================================================================
configuration io_ShiftRegister_PISO_ClockInhibit of io_ShiftRegister_PISO_TestHarness is
	for TestHarness
		for TestCtrl : io_ShiftRegister_PISO_TestController
			use entity work.io_ShiftRegister_PISO_TestController(ClockInhibit);
		end for;
	end for;
end configuration;
