-- EMACS settings: -*-  tab-width: 2; indent-tabs-mode: t -*-
-- vim: tabstop=2:shiftwidth=2:noexpandtab
-- kate: tab-width 2; replace-tabs off; indent-width 2;
-- =============================================================================
-- Authors:         Gustavo Martin
--
-- Entity:          io_ShiftRegister_PISO_InputSync
--
-- Description:
-- -------------------------------------
-- Test case for verifying ADD_INPUT_SYNCHRONIZERS functionality in the PISO
-- shift register controller.
--
-- This test verifies:
--   1. Data is received correctly with input synchronizers enabled
--   2. Multiple data patterns work correctly
--   3. Timing is maintained despite the synchronizer latency
--
-- The ADD_INPUT_SYNCHRONIZERS generic adds a 2-stage synchronizer to the
-- SerialDataIn input to prevent metastability when the input comes from
-- an asynchronous domain.
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


architecture InputSync of io_ShiftRegister_PISO_TestController is
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
		SetTestName("io_ShiftRegister_PISO_InputSync");

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

		-- Test data patterns
		type DataPatternArray is array (natural range <>) of std_logic_vector(7 downto 0);
		constant TEST_PATTERNS : DataPatternArray := (
			x"A5", x"5A", x"FF", x"00", x"F0", x"0F", x"AA", x"55"
		);

		-- Procedure to test data transfer with input synchronizers
		procedure TestWithInputSync(
			constant TestData : std_logic_vector(7 downto 0);
			constant TestName : string
		) is
		begin
			-- Set the parallel data on the model
			ModelParallelIn <= TestData;
			WaitForClock(Clock, 2);

			-- Initiate a read operation
			Start <= '1';
			WaitForClock(Clock);
			Start <= '0';

			-- Wait for operation to complete
			WaitForClock(Clock);
			AffirmIf(ProcID,
				Busy = '1',
				TestName & ": Busy signal asserted"
			);

			-- Wait for valid signal
			wait until Valid = '1';

			-- Verify data received correctly
			AffirmIf(ProcID,
				DataReceived = TestData,
				TestName & ": Data = 0x" & to_hstring(DataReceived),
				" Expected = 0x" & to_hstring(TestData)
			);

			-- Wait before next test
			WaitForClock(Clock, 5);
		end procedure;

		-- Procedure to compare behavior between DUT with and without synchronizers
		procedure CompareWithAndWithoutSync(
			constant TestData : std_logic_vector(7 downto 0)
		) is
			variable time_without_sync : time;
			variable time_with_sync    : time;
			variable start_time        : time;
		begin
			-- Test without synchronizers (DUT 0)
			ShiftFreqSel <= 0;
			WaitForClock(Clock, 5);

			ModelParallelIn <= TestData;
			WaitForClock(Clock, 2);

			start_time := now;
			Start <= '1';
			WaitForClock(Clock);
			Start <= '0';

			wait until Valid = '1';
			time_without_sync := now - start_time;

			AffirmIf(ProcID,
				DataReceived = TestData,
				"Without sync: Data = 0x" & to_hstring(DataReceived),
				" Expected = 0x" & to_hstring(TestData)
			);
			WaitForClock(Clock, 5);

			-- Test with synchronizers (DUT 3)
			ShiftFreqSel <= 3;
			WaitForClock(Clock, 5);

			ModelParallelIn <= TestData;
			WaitForClock(Clock, 2);

			start_time := now;
			Start <= '1';
			WaitForClock(Clock);
			Start <= '0';

			wait until Valid = '1';
			time_with_sync := now - start_time;

			AffirmIf(ProcID,
				DataReceived = TestData,
				"With sync: Data = 0x" & to_hstring(DataReceived),
				" Expected = 0x" & to_hstring(TestData)
			);

			-- Log timing comparison (synchronizers add ~2 clock cycles latency)
			Log(ProcID, "Timing comparison for 0x" & to_hstring(TestData) &
			    ": without=" & to_string(time_without_sync) &
			    ", with=" & to_string(time_with_sync), INFO);

			WaitForClock(Clock, 5);
		end procedure;

	begin
		-- Initialize outputs
		Start           <= '0';
		ModelParallelIn <= (others => '0');
		ShiftFreqSel    <= 3;  -- Use DUT with ADD_INPUT_SYNCHRONIZERS=TRUE

		-- Wait for reset to deassert
		wait until Reset = '0';
		WaitForClock(Clock, 5);

		Log(ProcID, "========================================================", INFO);
		Log(ProcID, "PISO ADD_INPUT_SYNCHRONIZERS Verification Tests", INFO);
		Log(ProcID, "========================================================", INFO);

		-- =====================================================================
		-- Test 1: Basic data transfer with input synchronizers
		-- =====================================================================
		Log(ProcID, "", INFO);
		Log(ProcID, "--- Test 1: Basic Data Transfer (DUT 3, Sync Enabled) ---", INFO);
		ShiftFreqSel <= 3;
		WaitForClock(Clock, 5);

		for i in TEST_PATTERNS'range loop
			TestWithInputSync(TEST_PATTERNS(i), "Pattern " & to_string(i));
		end loop;

		-- =====================================================================
		-- Test 2: Compare timing with and without synchronizers
		-- =====================================================================
		Log(ProcID, "", INFO);
		Log(ProcID, "--- Test 2: Timing Comparison ---", INFO);

		CompareWithAndWithoutSync(x"A5");
		CompareWithAndWithoutSync(x"C3");

		-- =====================================================================
		-- Test 3: Verify data integrity with alternating patterns
		-- =====================================================================
		Log(ProcID, "", INFO);
		Log(ProcID, "--- Test 3: Alternating Patterns ---", INFO);
		ShiftFreqSel <= 3;
		WaitForClock(Clock, 5);

		-- Send alternating patterns to stress the synchronizers
		for i in 0 to 7 loop
			if (i mod 2) = 0 then
				TestWithInputSync(x"AA", "Alternating " & to_string(i));
			else
				TestWithInputSync(x"55", "Alternating " & to_string(i));
			end if;
		end loop;

		Log(ProcID, "", INFO);
		Log(ProcID, "========================================================", INFO);
		Log(ProcID, "All ADD_INPUT_SYNCHRONIZERS tests completed!", INFO);
		Log(ProcID, "========================================================", INFO);

		-- Signal test completion
		WaitForBarrier(TestDone);
		wait;
	end process;

end architecture;


-- =============================================================================
-- Configuration: Binds the InputSync test architecture to the test harness
-- =============================================================================
configuration io_ShiftRegister_PISO_InputSync of io_ShiftRegister_PISO_TestHarness is
	for TestHarness
		for TestCtrl : io_ShiftRegister_PISO_TestController
			use entity work.io_ShiftRegister_PISO_TestController(InputSync);
		end for;
	end for;
end configuration;
