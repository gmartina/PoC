-- EMACS settings: -*-  tab-width: 2; indent-tabs-mode: t -*-
-- vim: tabstop=2:shiftwidth=2:noexpandtab
-- kate: tab-width 2; replace-tabs off; indent-width 2;
-- =============================================================================
-- Authors:         Gustavo Martin
--
-- Entity:          io_ShiftRegister_PISO_DaisyChain_Fast
--
-- Description:
-- -------------------------------------
-- Fast (30 MHz shift clock) daisy chain test case for the PISO shift register
-- controller. This test verifies the controller operates correctly at higher
-- clock speeds with 3 cascaded SN74AC165 chips (24 bits total).
--
-- Sets ShiftFreqSel = 1 to select the 30 MHz DUT in the test harness.
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


architecture DaisyChainFast of io_ShiftRegister_PISO_DaisyChain_TestController is
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
		SetTestName("io_ShiftRegister_PISO_DaisyChain_Fast");

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

		-- Test data patterns (24 bits)
		type T_TEST_PATTERN is record
			Data        : std_logic_vector(23 downto 0);
			Description : string(1 to 40);
		end record;

		type T_TEST_PATTERN_ARRAY is array (natural range <>) of T_TEST_PATTERN;

		constant TEST_PATTERNS : T_TEST_PATTERN_ARRAY := (
			-- Basic patterns
			(x"000000", "All zeros                               "),
			(x"FFFFFF", "All ones                                "),
			(x"AAAAAA", "Alternating bits (101010...)            "),
			(x"555555", "Alternating bits (010101...)            "),

			-- Unique pattern per chip to verify ordering
			(x"123456", "Chip2=12, Chip1=34, Chip0=56            "),
			(x"ABCDEF", "Chip2=AB, Chip1=CD, Chip0=EF            "),
			(x"FEDCBA", "Chip2=FE, Chip1=DC, Chip0=BA            "),

			-- Single chip active patterns
			(x"0000FF", "Only Chip0 active (bits 7:0)            "),
			(x"00FF00", "Only Chip1 active (bits 15:8)           "),
			(x"FF0000", "Only Chip2 active (bits 23:16)          "),

			-- Boundary patterns
			(x"800000", "MSB only (bit 23)                       "),
			(x"000001", "LSB only (bit 0)                        "),
			(x"800001", "MSB and LSB only                        ")
		);

		-- Procedure to perform a single read test
		procedure TestRead(
			constant TestData   : std_logic_vector(23 downto 0);
			constant TestName   : string
		) is
		begin
			-- Set the parallel data on the models
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

		-- Procedure to test walking ones pattern
		procedure TestWalkingOnes is
			variable Pattern : std_logic_vector(23 downto 0);
		begin
			Log(ProcID, "Testing walking ones pattern across all 24 bits", INFO);
			for i in 0 to 23 loop
				Pattern := (others => '0');
				Pattern(i) := '1';
				TestRead(Pattern, "Walking one at bit " & to_string(i));
			end loop;
		end procedure;

	begin
		-- Initialize outputs
		Start           <= '0';
		ModelParallelIn <= (others => '0');
		ShiftFreqSel    <= 1;  -- Use 30 MHz shift clock

		-- Wait for reset to deassert
		wait until Reset = '0';
		WaitForClock(Clock, 5);

		Log(ProcID, "================================================================", INFO);
		Log(ProcID, "Starting PISO Shift Register Daisy Chain Tests (30 MHz)", INFO);
		Log(ProcID, "Configuration: 3 x SN74AC165 chips (24 bits total)", INFO);
		Log(ProcID, "================================================================", INFO);

		-- Run through all predefined test patterns
		Log(ProcID, "", INFO);
		Log(ProcID, "--- Predefined Pattern Tests ---", INFO);
		for i in TEST_PATTERNS'range loop
			Log(ProcID, "Test " & to_string(i) & ": " & TEST_PATTERNS(i).Description, INFO);
			TestRead(TEST_PATTERNS(i).Data, "Pattern " & to_string(i));
		end loop;

		-- Run walking ones test
		Log(ProcID, "", INFO);
		Log(ProcID, "--- Walking Ones Test ---", INFO);
		TestWalkingOnes;

		Log(ProcID, "", INFO);
		Log(ProcID, "================================================================", INFO);
		Log(ProcID, "All 30 MHz daisy chain tests completed successfully!", INFO);
		Log(ProcID, "================================================================", INFO);

		-- Signal test completion
		WaitForBarrier(TestDone);
		wait;
	end process;

end architecture;


-- =============================================================================
-- Configuration: Binds the DaisyChainFast architecture to the test harness
-- =============================================================================
configuration io_ShiftRegister_PISO_DaisyChain_Fast of io_ShiftRegister_PISO_DaisyChain_TestHarness is
	for TestHarness
		for TestCtrl : io_ShiftRegister_PISO_DaisyChain_TestController
			use entity work.io_ShiftRegister_PISO_DaisyChain_TestController(DaisyChainFast);
		end for;
	end for;
end configuration;
