# =============================================================================
# Authors:         Gustavo Martin
#
# Description:     Run all tests for the PISO shift register controller
#
# License:
# =============================================================================
# Copyright 2025-2025 The PoC-Library Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# =============================================================================

# Analyze the verification model
analyze SN74AC165_Model.vhdl

# =============================================================================
# Single Chip Tests (8-bit)
# =============================================================================

# Analyze the test controller entity
analyze io_ShiftRegister_PISO_TestController.vhdl

# Analyze the test harness
analyze io_ShiftRegister_PISO_TestHarness.vhdl

# Run single chip tests
RunTest io_ShiftRegister_PISO_Simple.vhdl

# =============================================================================
# Daisy Chain Tests (24-bit, 3 chips)
# =============================================================================

# Analyze the daisy chain test controller entity
analyze io_ShiftRegister_PISO_DaisyChain_TestController.vhdl

# Analyze the daisy chain test harness
analyze io_ShiftRegister_PISO_DaisyChain_TestHarness.vhdl

# Run daisy chain tests
RunTest io_ShiftRegister_PISO_DaisyChain.vhdl

# =============================================================================
# Fast Clock Tests (30 MHz shift clock)
# Uses ShiftFreqSel signal to select the 30 MHz DUT in the harness
# =============================================================================

# Single chip test at 30 MHz
RunTest io_ShiftRegister_PISO_Fast.vhdl

# Daisy chain test at 30 MHz
RunTest io_ShiftRegister_PISO_DaisyChain_Fast.vhdl

