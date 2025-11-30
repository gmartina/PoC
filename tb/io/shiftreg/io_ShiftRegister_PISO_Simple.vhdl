-- EMACS settings: -*-  tab-width: 2; indent-tabs-mode: t -*-
-- vim: tabstop=2:shiftwidth=2:noexpandtab
-- kate: tab-width 2; replace-tabs off; indent-width 2;
-- =============================================================================
-- Authors:         Gustavo Martin
--
-- Entity:          io_ShiftRegister_PISO_Simple
--
-- Description:
-- -------------------------------------
-- Simple test case for the PISO shift register controller.
-- This test verifies basic functionality:
--   1. Single read operation with known data
--   2. Multiple consecutive reads with different data patterns
--   3. Boundary value tests (all zeros, all ones, alternating bits)
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


architecture Simple of io_ShiftRegister_PISO_TestController is
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
		SetTestName("io_ShiftRegister_PISO_Simple");

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
		type T_TEST_PATTERN is record
			Data        : std_logic_vector(7 downto 0);
			Description : string(1 to 32);
		end record;

		type T_TEST_PATTERN_ARRAY is array (natural range <>) of T_TEST_PATTERN;

		constant TEST_PATTERNS : T_TEST_PATTERN_ARRAY := (
			(x"00", "All zeros                       "),
			(x"FF", "All ones                        "),
			(x"AA", "Alternating bits (10101010)     "),
			(x"55", "Alternating bits (01010101)     "),
			(x"0F", "Lower nibble ones               "),
			(x"F0", "Upper nibble ones               "),
			(x"81", "MSB and LSB set                 "),
			(x"42", "Scattered bits                  "),
			(x"A5", "Pattern A5                      "),
			(x"5A", "Pattern 5A                      "),
			(x"C3", "Pattern C3                      "),
			(x"3C", "Pattern 3C                      "),
			(x"01", "Single bit LSB                  "),
			(x"80", "Single bit MSB                  "),
			(x"12", "Random pattern 1                "),
			(x"ED", "Random pattern 2                ")
		);

		-- Procedure to perform a single read test
		procedure TestRead(
			constant TestData   : std_logic_vector(7 downto 0);
			constant TestName   : string
		) is
		begin
			-- Set the parallel data on the model
			ModelParallelIn <= TestData;

			-- Wait a few clock cycles for data to settle
			WaitForClock(Clock, 2);

			-- Initiate a read operation
			Start <= '1';
			WaitForClock(Clock);
			Start <= '0';

			-- Wait for operation to complete
			WaitForClock(Clock);
			-- Check busy is asserted
			AffirmIf(ProcID,
				Busy = '1',
				TestName & ": Busy signal asserted"
			);

			-- Wait for valid signal
			wait until Valid = '1';

			-- Check the result
			AffirmIf(ProcID,
				Valid = '1',
				TestName & ": Valid signal asserted"
			);

			AffirmIf(ProcID,
				DataReceived = TestData,
				TestName & ": Data = 0x" & to_hstring(DataReceived),
				" Expected = 0x" & to_hstring(TestData)
			);

			-- Wait a few cycles before next test
			WaitForClock(Clock, 5);
		end procedure;

	begin
		-- Initialize outputs
		Start           <= '0';
		ModelParallelIn <= (others => '0');

		-- Wait for reset to deassert
		wait until Reset = '0';
		WaitForClock(Clock, 5);

		Log(ProcID, "Starting PISO Shift Register Controller Tests", INFO);
		Log(ProcID, "==============================================", INFO);

		-- Run through all test patterns
		for i in TEST_PATTERNS'range loop
			Log(ProcID, "Test " & to_string(i) & ": " & TEST_PATTERNS(i).Description, INFO);
			TestRead(TEST_PATTERNS(i).Data, "Pattern " & to_string(i));
		end loop;

		Log(ProcID, "==============================================", INFO);
		Log(ProcID, "All tests completed successfully!", INFO);

		-- Signal test completion
		WaitForBarrier(TestDone);
		wait;
	end process;

end architecture;


-- =============================================================================
-- Configuration: Binds the Simple test architecture to the test harness
-- =============================================================================
configuration io_ShiftRegister_PISO_Simple of io_ShiftRegister_PISO_TestHarness is
	for TestHarness
		for TestCtrl : io_ShiftRegister_PISO_TestController
			use entity work.io_ShiftRegister_PISO_TestController(Simple);
		end for;
	end for;
end configuration;
