-- EMACS settings: -*-  tab-width: 2; indent-tabs-mode: t -*-
-- vim: tabstop=2:shiftwidth=2:noexpandtab
-- kate: tab-width 2; replace-tabs off; indent-width 2;
-- =============================================================================
-- Authors:         Gustavo Martin
--
-- Entity:          io_ShiftRegister_SIPO_Clear
--
-- Description:
-- -------------------------------------
-- Test case for verifying Clear_n signal behavior in the SIPO shift
-- register controller.
--
-- This test verifies:
--   1. Clear_n signal polarity with ACTIVE_LOW_CLEAR=TRUE (inactive = HIGH)
--   2. Clear_n signal polarity with ACTIVE_LOW_CLEAR=FALSE (inactive = LOW)
--   3. Clear_n remains stable (inactive) during shift operations
--   4. Data transfers correctly in both configurations
--
-- Note: The Clear_n output is intended for external shift registers that
-- support asynchronous clear. The DUT keeps it inactive during normal
-- operation. Future tests could verify clear functionality if implemented.
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


architecture Clear of io_ShiftRegister_SIPO_TestController is
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
		SetTestName("io_ShiftRegister_SIPO_Clear");

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

		-- Procedure to test Clear_n with active-low polarity (ACTIVE_LOW_CLEAR=TRUE)
		-- Expected: Clear_n = '1' (inactive) during idle and operation
		procedure TestClearActiveLow is
			variable clear_stayed_high : boolean := TRUE;
		begin
			Log(ProcID, "Testing Clear_n with ACTIVE_LOW_CLEAR=TRUE", INFO);

			-- Verify Clear_n is HIGH (inactive) during idle (before starting)
			AffirmIf(ProcID,
				Clear_n = '1',
				"Clear_n is HIGH (inactive) during idle",
				" Got: " & to_string(Clear_n)
			);

			-- Set the data to send
			DataToSend <= TEST_DATA;
			WaitForClock(Clock, 2);

			-- Initiate a write operation
			Start <= '1';
			WaitForClock(Clock);
			Start <= '0';

			-- Wait for busy to assert
			WaitForClock(Clock);
			AffirmIf(ProcID,
				Busy = '1',
				"Busy signal asserted after start"
			);

			-- Monitor Clear_n during shift operation
			-- It should stay HIGH (inactive) throughout
			while Busy = '1' loop
				if Clear_n /= '1' then
					clear_stayed_high := FALSE;
				end if;
				WaitForClock(Clock);
			end loop;

			AffirmIf(ProcID,
				clear_stayed_high,
				"Clear_n stayed HIGH (inactive) during entire shift operation"
			);

			-- Wait for done signal (only if not already high)
			if Done /= '1' then
				wait until Done = '1';
			end if;

			-- After operation completes, Clear_n should still be HIGH
			WaitForClock(Clock, 3);
			AffirmIf(ProcID,
				Clear_n = '1',
				"Clear_n is HIGH (inactive) after operation",
				" Got: " & to_string(Clear_n)
			);

			-- Verify data was sent correctly
			AffirmIf(ProcID,
				ModelParallelOut = TEST_DATA,
				"Data sent correctly: 0x" & to_hstring(ModelParallelOut),
				" Expected: 0x" & to_hstring(TEST_DATA)
			);

			WaitForClock(Clock, 5);
		end procedure;

		-- Procedure to test Clear_n with active-high polarity (ACTIVE_LOW_CLEAR=FALSE)
		-- Expected: Clear_n = '0' (inactive) during idle and operation
		procedure TestClearActiveHigh is
			variable clear_stayed_low : boolean := TRUE;
		begin
			Log(ProcID, "Testing Clear_n with ACTIVE_LOW_CLEAR=FALSE", INFO);

			-- Verify Clear_n is LOW (inactive) during idle (before starting)
			AffirmIf(ProcID,
				Clear_n = '0',
				"Clear_n is LOW (inactive) during idle (active-high mode)",
				" Got: " & to_string(Clear_n)
			);

			-- Set the data to send
			DataToSend <= TEST_DATA;
			WaitForClock(Clock, 2);

			-- Initiate a write operation
			Start <= '1';
			WaitForClock(Clock);
			Start <= '0';

			-- Wait for busy to assert
			WaitForClock(Clock);
			AffirmIf(ProcID,
				Busy = '1',
				"Busy signal asserted after start (active-high mode)"
			);

			-- Monitor Clear_n during shift operation
			-- It should stay LOW (inactive) throughout
			while Busy = '1' loop
				if Clear_n /= '0' then
					clear_stayed_low := FALSE;
				end if;
				WaitForClock(Clock);
			end loop;

			AffirmIf(ProcID,
				clear_stayed_low,
				"Clear_n stayed LOW (inactive) during entire shift operation (active-high mode)"
			);

			-- Wait for done signal (only if not already high)
			if Done /= '1' then
				wait until Done = '1';
			end if;

			-- After operation completes, Clear_n should still be LOW
			WaitForClock(Clock, 3);
			AffirmIf(ProcID,
				Clear_n = '0',
				"Clear_n is LOW (inactive) after operation (active-high mode)",
				" Got: " & to_string(Clear_n)
			);

			-- Verify data was sent correctly
			AffirmIf(ProcID,
				ModelParallelOut = TEST_DATA,
				"Data sent correctly (active-high mode): 0x" & to_hstring(ModelParallelOut),
				" Expected: 0x" & to_hstring(TEST_DATA)
			);

			WaitForClock(Clock, 5);
		end procedure;

	begin
		-- Initialize outputs
		Start        <= '0';
		DataToSend   <= (others => '0');
		ShiftFreqSel <= 0;  -- Use 5 MHz, ACTIVE_LOW_CLEAR=TRUE

		-- Wait for reset to deassert
		wait until Reset = '0';
		WaitForClock(Clock, 5);

		Log(ProcID, "========================================================", INFO);
		Log(ProcID, "SIPO Clear_n Signal Verification Tests", INFO);
		Log(ProcID, "========================================================", INFO);

		-- =====================================================================
		-- Test 1: Active-low polarity (ACTIVE_LOW_CLEAR=TRUE)
		-- =====================================================================
		Log(ProcID, "", INFO);
		Log(ProcID, "--- Test 1: Active-Low Polarity (DUT 0) ---", INFO);
		ShiftFreqSel <= 0;
		WaitForClock(Clock, 5);
		TestClearActiveLow;

		-- =====================================================================
		-- Test 2: Active-high polarity (ACTIVE_LOW_CLEAR=FALSE)
		-- =====================================================================
		Log(ProcID, "", INFO);
		Log(ProcID, "--- Test 2: Active-High Polarity (DUT 2) ---", INFO);
		ShiftFreqSel <= 2;
		WaitForClock(Clock, 5);
		TestClearActiveHigh;

		-- =====================================================================
		-- Test 3: Verify data integrity with multiple patterns
		-- =====================================================================
		Log(ProcID, "", INFO);
		Log(ProcID, "--- Test 3: Multiple Data Patterns ---", INFO);

		-- Test with DUT 0 (active-low clear)
		ShiftFreqSel <= 0;
		WaitForClock(Clock, 5);

		-- Pattern 0: 0xAA
		DataToSend <= x"AA";
		WaitForClock(Clock, 2);
		Start <= '1';
		WaitForClock(Clock);
		Start <= '0';
		wait until Done = '1';
		AffirmIf(ProcID, ModelParallelOut = x"AA", "Pattern 0 (active-low): 0x" & to_hstring(ModelParallelOut), " Expected: 0xAA");
		WaitForClock(Clock, 5);

		-- Pattern 1: 0x55
		DataToSend <= x"55";
		WaitForClock(Clock, 2);
		Start <= '1';
		WaitForClock(Clock);
		Start <= '0';
		wait until Done = '1';
		AffirmIf(ProcID, ModelParallelOut = x"55", "Pattern 1 (active-low): 0x" & to_hstring(ModelParallelOut), " Expected: 0x55");
		WaitForClock(Clock, 5);

		-- Pattern 2: 0xFF
		DataToSend <= x"FF";
		WaitForClock(Clock, 2);
		Start <= '1';
		WaitForClock(Clock);
		Start <= '0';
		wait until Done = '1';
		AffirmIf(ProcID, ModelParallelOut = x"FF", "Pattern 2 (active-low): 0x" & to_hstring(ModelParallelOut), " Expected: 0xFF");
		WaitForClock(Clock, 5);

		-- Pattern 3: 0x00
		DataToSend <= x"00";
		WaitForClock(Clock, 2);
		Start <= '1';
		WaitForClock(Clock);
		Start <= '0';
		wait until Done = '1';
		AffirmIf(ProcID, ModelParallelOut = x"00", "Pattern 3 (active-low): 0x" & to_hstring(ModelParallelOut), " Expected: 0x00");
		WaitForClock(Clock, 5);

		-- Test with DUT 2 (active-high clear)
		ShiftFreqSel <= 2;
		WaitForClock(Clock, 5);

		-- Pattern 0: 0xF0
		DataToSend <= x"F0";
		WaitForClock(Clock, 2);
		Start <= '1';
		WaitForClock(Clock);
		Start <= '0';
		wait until Done = '1';
		AffirmIf(ProcID, ModelParallelOut = x"F0", "Pattern 0 (active-high): 0x" & to_hstring(ModelParallelOut), " Expected: 0xF0");
		WaitForClock(Clock, 5);

		-- Pattern 1: 0x0F
		DataToSend <= x"0F";
		WaitForClock(Clock, 2);
		Start <= '1';
		WaitForClock(Clock);
		Start <= '0';
		wait until Done = '1';
		AffirmIf(ProcID, ModelParallelOut = x"0F", "Pattern 1 (active-high): 0x" & to_hstring(ModelParallelOut), " Expected: 0x0F");
		WaitForClock(Clock, 5);

		-- Pattern 2: 0x3C
		DataToSend <= x"3C";
		WaitForClock(Clock, 2);
		Start <= '1';
		WaitForClock(Clock);
		Start <= '0';
		wait until Done = '1';
		AffirmIf(ProcID, ModelParallelOut = x"3C", "Pattern 2 (active-high): 0x" & to_hstring(ModelParallelOut), " Expected: 0x3C");
		WaitForClock(Clock, 5);

		-- Pattern 3: 0xC3
		DataToSend <= x"C3";
		WaitForClock(Clock, 2);
		Start <= '1';
		WaitForClock(Clock);
		Start <= '0';
		wait until Done = '1';
		AffirmIf(ProcID, ModelParallelOut = x"C3", "Pattern 3 (active-high): 0x" & to_hstring(ModelParallelOut), " Expected: 0xC3");
		WaitForClock(Clock, 5);

		Log(ProcID, "", INFO);
		Log(ProcID, "========================================================", INFO);
		Log(ProcID, "All Clear_n tests completed successfully!", INFO);
		Log(ProcID, "========================================================", INFO);

		-- Signal test completion
		WaitForBarrier(TestDone);
		wait;
	end process;

end architecture;


-- =============================================================================
-- Configuration: Binds the Clear test architecture to the test harness
-- =============================================================================
configuration io_ShiftRegister_SIPO_Clear of io_ShiftRegister_SIPO_TestHarness is
	for TestHarness
		for TestCtrl : io_ShiftRegister_SIPO_TestController
			use entity work.io_ShiftRegister_SIPO_TestController(Clear);
		end for;
	end for;
end configuration;
