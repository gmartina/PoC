-- EMACS settings: -*-  tab-width: 2; indent-tabs-mode: t -*-
-- vim: tabstop=2:shiftwidth=2:noexpandtab
-- kate: tab-width 2; replace-tabs off; indent-width 2;
-- =============================================================================
-- Authors:         Gustavo Martin
--
-- Entity:          io_ShiftRegister_SIPO_DaisyChain
--
-- Description:
-- -------------------------------------
-- Standard (5 MHz shift clock) daisy chain test case for the SIPO shift 
-- register controller with 3 chained SN74AC596 chips (24 bits total).
--
-- Uses ShiftFreqSel = 0 to select the 5 MHz DUT in the test harness.
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


architecture DaisyChain of io_ShiftRegister_SIPO_DaisyChain_TestController is
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
		constant TIMEOUT : time := 200 ms;  -- Longer timeout for daisy chain
	begin
		SetTestName("io_ShiftRegister_SIPO_DaisyChain");

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

		-- Test data patterns for 24-bit daisy chain
		type T_TEST_PATTERN is record
			Data        : std_logic_vector(23 downto 0);
			Description : string(1 to 40);
		end record;

		type T_TEST_PATTERN_ARRAY is array (natural range <>) of T_TEST_PATTERN;

		constant TEST_PATTERNS : T_TEST_PATTERN_ARRAY := (
			(x"000000", "All zeros                               "),
			(x"FFFFFF", "All ones                                "),
			(x"AAAAAA", "Alternating bits (101010...)            "),
			(x"555555", "Alternating bits (010101...)            "),
			(x"FF0000", "Byte 3 only                             "),
			(x"00FF00", "Byte 2 only                             "),
			(x"0000FF", "Byte 1 only                             "),
			(x"123456", "Sequential nibbles                      "),
			(x"FEDCBA", "Reverse sequential nibbles              "),
			(x"A5A5A5", "Pattern A5 in each byte                 "),
			(x"5A5A5A", "Pattern 5A in each byte                 "),
			(x"C3C3C3", "Pattern C3 in each byte                 "),
			(x"800001", "MSB and LSB set                         "),
			(x"7FFFFE", "All except MSB and LSB                  "),
			(x"0F0F0F", "Lower nibbles only                      "),
			(x"F0F0F0", "Upper nibbles only                      ")
		);

		-- Procedure to perform a single write test
		procedure TestWrite(
			constant TestData   : std_logic_vector(23 downto 0);
			constant TestName   : string
		) is
			variable ExpectedChip1 : std_logic_vector(7 downto 0);  -- Bits 7:0
			variable ExpectedChip2 : std_logic_vector(7 downto 0);  -- Bits 15:8
			variable ExpectedChip3 : std_logic_vector(7 downto 0);  -- Bits 23:16
		begin
			-- Calculate expected values for each chip
			ExpectedChip1 := TestData(7 downto 0);
			ExpectedChip2 := TestData(15 downto 8);
			ExpectedChip3 := TestData(23 downto 16);

			-- Set the data to send
			DataToSend <= TestData;

			-- Wait a few clock cycles for data to settle
			WaitForClock(Clock, 2);

			-- Initiate a write operation
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

			-- Wait for done signal
			wait until Done = '1';

			-- Wait for model propagation delay
			wait for 20 ns;

			-- Check all three chips received correct data
			AffirmIf(ProcID,
				ModelParallelOut1 = ExpectedChip1,
				TestName & ": Chip1 = 0x" & to_hstring(ModelParallelOut1),
				" Expected = 0x" & to_hstring(ExpectedChip1)
			);

			AffirmIf(ProcID,
				ModelParallelOut2 = ExpectedChip2,
				TestName & ": Chip2 = 0x" & to_hstring(ModelParallelOut2),
				" Expected = 0x" & to_hstring(ExpectedChip2)
			);

			AffirmIf(ProcID,
				ModelParallelOut3 = ExpectedChip3,
				TestName & ": Chip3 = 0x" & to_hstring(ModelParallelOut3),
				" Expected = 0x" & to_hstring(ExpectedChip3)
			);

			-- Wait a few cycles before next test
			WaitForClock(Clock, 5);
		end procedure;

	begin
		-- Initialize outputs
		Start        <= '0';
		DataToSend   <= (others => '0');
		ShiftFreqSel <= 0;  -- Use 5 MHz shift clock

		-- Wait for reset to deassert
		wait until Reset = '0';
		WaitForClock(Clock, 5);

		Log(ProcID, "Starting SIPO Daisy Chain Tests (5 MHz, 3 IC)", INFO);
		Log(ProcID, "=================================================", INFO);

		-- Run through all test patterns
		for i in TEST_PATTERNS'range loop
			Log(ProcID, "Test " & to_string(i) & ": " & TEST_PATTERNS(i).Description, INFO);
			TestWrite(TEST_PATTERNS(i).Data, "Pattern " & to_string(i));
		end loop;

		Log(ProcID, "=================================================", INFO);
		Log(ProcID, "All 5 MHz daisy chain tests completed!", INFO);

		-- Signal test completion
		WaitForBarrier(TestDone);
		wait;
	end process;

end architecture;


-- =============================================================================
-- Configuration: Binds the DaisyChain architecture to the test harness
-- =============================================================================
configuration io_ShiftRegister_SIPO_DaisyChain of io_ShiftRegister_SIPO_DaisyChain_TestHarness is
	for TestHarness
		for TestCtrl : io_ShiftRegister_SIPO_DaisyChain_TestController
			use entity work.io_ShiftRegister_SIPO_DaisyChain_TestController(DaisyChain);
		end for;
	end for;
end configuration;
