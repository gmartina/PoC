-- EMACS settings: -*-  tab-width: 2; indent-tabs-mode: t -*-
-- vim: tabstop=2:shiftwidth=2:noexpandtab
-- kate: tab-width 2; replace-tabs off; indent-width 2;
-- =============================================================================
-- Authors:         Gustavo Martin
--
-- Entity:          io_ShiftRegister_SIPO_OutputRegs
--
-- Description:
-- -------------------------------------
-- Test case for verifying ADD_OUTPUT_REGISTERS functionality in the SIPO
-- shift register controller.
--
-- This test verifies:
--   1. Data is sent correctly with output registers enabled
--   2. Multiple data patterns work correctly
--   3. Timing is maintained despite the register pipeline latency
--
-- The ADD_OUTPUT_REGISTERS generic adds output registers to all signals
-- going to the shift register IC, providing cleaner timing at the expense
-- of one clock cycle latency.
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


architecture OutputRegs of io_ShiftRegister_SIPO_TestController is
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
		SetTestName("io_ShiftRegister_SIPO_OutputRegs");

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

		-- Procedure to test data transfer with output registers
		procedure TestWithOutputRegs(
			constant TestData : std_logic_vector(7 downto 0);
			constant TestName : string
		) is
		begin
			-- Set the data to send
			DataToSend <= TestData;
			WaitForClock(Clock, 2);

			-- Initiate a write operation
			Start <= '1';
			WaitForClock(Clock);
			Start <= '0';

			-- Wait for operation to complete
			WaitForClock(Clock);
			AffirmIf(ProcID,
				Busy = '1',
				TestName & ": Busy signal asserted"
			);

			-- Wait for done signal
			wait until Done = '1';

			-- Wait for model to capture the data (propagation through output registers)
			WaitForClock(Clock, 3);

			-- Verify data sent correctly
			AffirmIf(ProcID,
				ModelParallelOut = TestData,
				TestName & ": Data = 0x" & to_hstring(ModelParallelOut),
				" Expected = 0x" & to_hstring(TestData)
			);

			-- Wait before next test
			WaitForClock(Clock, 5);
		end procedure;

		-- Procedure to compare behavior between DUT with and without output registers
		procedure CompareWithAndWithoutRegs(
			constant TestData : std_logic_vector(7 downto 0)
		) is
			variable time_without_regs : time;
			variable time_with_regs    : time;
			variable start_time        : time;
		begin
			-- Test without output registers (DUT 0)
			ShiftFreqSel <= 0;
			WaitForClock(Clock, 5);

			DataToSend <= TestData;
			WaitForClock(Clock, 2);

			start_time := now;
			Start <= '1';
			WaitForClock(Clock);
			Start <= '0';

			wait until Done = '1';
			time_without_regs := now - start_time;

			WaitForClock(Clock, 3);
			AffirmIf(ProcID,
				ModelParallelOut = TestData,
				"Without regs: Data = 0x" & to_hstring(ModelParallelOut),
				" Expected = 0x" & to_hstring(TestData)
			);
			WaitForClock(Clock, 5);

			-- Test with output registers (DUT 3)
			ShiftFreqSel <= 3;
			WaitForClock(Clock, 5);

			DataToSend <= TestData;
			WaitForClock(Clock, 2);

			start_time := now;
			Start <= '1';
			WaitForClock(Clock);
			Start <= '0';

			wait until Done = '1';
			time_with_regs := now - start_time;

			WaitForClock(Clock, 3);
			AffirmIf(ProcID,
				ModelParallelOut = TestData,
				"With regs: Data = 0x" & to_hstring(ModelParallelOut),
				" Expected = 0x" & to_hstring(TestData)
			);

			-- Log timing comparison (output registers add pipeline latency)
			Log(ProcID, "Timing comparison for 0x" & to_hstring(TestData) &
			    ": without=" & to_string(time_without_regs) &
			    ", with=" & to_string(time_with_regs), INFO);

			WaitForClock(Clock, 5);
		end procedure;

	begin
		-- Initialize outputs
		Start        <= '0';
		DataToSend   <= (others => '0');
		ShiftFreqSel <= 3;  -- Use DUT with ADD_OUTPUT_REGISTERS=TRUE

		-- Wait for reset to deassert
		wait until Reset = '0';
		WaitForClock(Clock, 5);

		Log(ProcID, "========================================================", INFO);
		Log(ProcID, "SIPO ADD_OUTPUT_REGISTERS Verification Tests", INFO);
		Log(ProcID, "========================================================", INFO);

		-- =====================================================================
		-- Test 1: Basic data transfer with output registers
		-- =====================================================================
		Log(ProcID, "", INFO);
		Log(ProcID, "--- Test 1: Basic Data Transfer (DUT 3, OutRegs Enabled) ---", INFO);
		ShiftFreqSel <= 3;
		WaitForClock(Clock, 5);

		for i in TEST_PATTERNS'range loop
			TestWithOutputRegs(TEST_PATTERNS(i), "Pattern " & to_string(i));
		end loop;

		-- =====================================================================
		-- Test 2: Compare timing with and without output registers
		-- =====================================================================
		Log(ProcID, "", INFO);
		Log(ProcID, "--- Test 2: Timing Comparison ---", INFO);

		CompareWithAndWithoutRegs(x"A5");
		CompareWithAndWithoutRegs(x"C3");

		-- =====================================================================
		-- Test 3: Verify data integrity with alternating patterns
		-- =====================================================================
		Log(ProcID, "", INFO);
		Log(ProcID, "--- Test 3: Alternating Patterns ---", INFO);
		ShiftFreqSel <= 3;
		WaitForClock(Clock, 5);

		-- Send alternating patterns
		for i in 0 to 7 loop
			if (i mod 2) = 0 then
				TestWithOutputRegs(x"AA", "Alternating " & to_string(i));
			else
				TestWithOutputRegs(x"55", "Alternating " & to_string(i));
			end if;
		end loop;

		Log(ProcID, "", INFO);
		Log(ProcID, "========================================================", INFO);
		Log(ProcID, "All ADD_OUTPUT_REGISTERS tests completed!", INFO);
		Log(ProcID, "========================================================", INFO);

		-- Signal test completion
		WaitForBarrier(TestDone);
		wait;
	end process;

end architecture;


-- =============================================================================
-- Configuration: Binds the OutputRegs test architecture to the test harness
-- =============================================================================
configuration io_ShiftRegister_SIPO_OutputRegs of io_ShiftRegister_SIPO_TestHarness is
	for TestHarness
		for TestCtrl : io_ShiftRegister_SIPO_TestController
			use entity work.io_ShiftRegister_SIPO_TestController(OutputRegs);
		end for;
	end for;
end configuration;
