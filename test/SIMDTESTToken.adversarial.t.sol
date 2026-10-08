// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SIMDTESTToken} from "../src/SIMDTESTToken.sol";
import {TestSupport} from "./TestSupport.sol";

interface TimeVm {
    function warp(uint256 timestamp) external;
    function roll(uint256 blockNumber) external;
    function chainId(uint256 chainId) external;
}

/// @dev Plain ERC-20 transfers must not invoke recipients, even contracts that reject calls.
contract RejectingTokenRecipient {
    fallback() external {
        revert("recipient must not be called");
    }
}

contract SIMDTESTTokenAdversarialTest is TestSupport {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant SPENDER = address(0x5EED);
    SIMDTESTToken internal token;

    function setUp() public {
        token = new SIMDTESTToken();
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_ExactAllowanceCannotBeSpentTwice(uint256 rawAmount) public {
        uint256 amount = 1 + rawAmount % SUPPLY;
        token.approve(SPENDER, amount);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, amount));
        vm.expectRevert(abi.encodeWithSelector(SIMDTESTToken.ERC20InsufficientAllowance.selector, SPENDER, 0, amount));
        vm.prank(SPENDER);
        token.transferFrom(address(this), BOB, amount);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_ReplacingPartiallySpentAllowanceDiscardsOldBudget(
        uint256 firstSeed,
        uint256 spendSeed,
        uint256 replacementSeed
    ) public {
        uint256 first = 1 + firstSeed % SUPPLY;
        uint256 spent = spendSeed % (first + 1);
        token.approve(SPENDER, first);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, spent));

        uint256 replacement = replacementSeed % (SUPPLY - spent + 1);
        token.approve(SPENDER, replacement);
        assertEq(token.allowance(address(this), SPENDER), replacement);
        vm.expectRevert(
            abi.encodeWithSelector(
                SIMDTESTToken.ERC20InsufficientAllowance.selector, SPENDER, replacement, replacement + 1
            )
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), BOB, replacement + 1);
        assertEq(token.allowance(address(this), SPENDER), replacement);

        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), BOB, replacement));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - spent - replacement);
        assertEq(token.balanceOf(ALICE), spent);
        assertEq(token.balanceOf(BOB), replacement);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_InfiniteApprovalCannotSpendBeyondBalance(uint256 balanceSeed, uint256 excessSeed) public {
        uint256 held = balanceSeed % (SUPPLY + 1);
        token.transfer(ALICE, held);
        vm.prank(ALICE);
        token.approve(SPENDER, type(uint256).max);
        uint256 excessive = held + 1 + excessSeed % (type(uint256).max - held);
        vm.expectRevert(abi.encodeWithSelector(SIMDTESTToken.ERC20InsufficientBalance.selector, ALICE, held, excessive));
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, excessive);
        assertEq(token.allowance(ALICE, SPENDER), type(uint256).max);
        assertEq(token.balanceOf(ALICE), held);
        assertEq(token.balanceOf(BOB), 0);

        // A rejected spend must not lock the holder out of a subsequent valid spend.
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, held));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), held);
        assertEq(token.balanceOf(address(this)), SUPPLY - held);
        assertEq(token.allowance(ALICE, SPENDER), type(uint256).max);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumFiniteAllowanceIsNotUnlimited() public {
        token.approve(SPENDER, type(uint256).max - 1);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max - 2);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), BOB, SUPPLY - 1));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max - 1 - SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(ALICE) + token.balanceOf(BOB), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_SelfSpenderRequiresApprovalAndCannotReplayIt(uint256 amountSeed) public {
        uint256 amount = 1 + amountSeed % SUPPLY;
        vm.expectRevert(
            abi.encodeWithSelector(SIMDTESTToken.ERC20InsufficientAllowance.selector, address(this), 0, amount)
        );
        token.transferFrom(address(this), ALICE, amount);
        token.approve(address(this), amount);
        assertTrue(token.transferFrom(address(this), address(this), amount));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(address(this), address(this)), 0);
        vm.expectRevert(
            abi.encodeWithSelector(SIMDTESTToken.ERC20InsufficientAllowance.selector, address(this), 0, amount)
        );
        token.transferFrom(address(this), ALICE, amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_TruncatedStateChangingCallsRevertAtomically(uint8 methodSeed, uint8 lengthSeed) public {
        token.approve(SPENDER, SUPPLY);
        bytes memory complete;
        uint8 method = methodSeed % 3;
        if (method == 0) complete = abi.encodeCall(token.transfer, (ALICE, SUPPLY));
        if (method == 1) complete = abi.encodeCall(token.approve, (ALICE, type(uint256).max));
        if (method == 2) complete = abi.encodeCall(token.transferFrom, (address(this), ALICE, SUPPLY));
        bytes memory truncated = new bytes(uint256(lengthSeed) % complete.length);
        for (uint256 i; i < truncated.length; ++i) {
            truncated[i] = complete[i];
        }
        // Each complete call would succeed; failure must result from the missing calldata.
        vm.prank(method == 2 ? SPENDER : address(this));
        (bool ok,) = address(token).call(truncated);
        assertTrue(!ok);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.allowance(address(this), SPENDER), SUPPLY);
        assertEq(token.allowance(address(this), ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_AllERC20EntryPointsRejectEtherAtomically() public {
        token.approve(address(this), 17);
        bytes[] memory calls = new bytes[](9);
        calls[0] = abi.encodeWithSignature("name()");
        calls[1] = abi.encodeWithSignature("symbol()");
        calls[2] = abi.encodeWithSignature("decimals()");
        calls[3] = abi.encodeWithSignature("totalSupply()");
        calls[4] = abi.encodeCall(token.balanceOf, (address(this)));
        calls[5] = abi.encodeCall(token.allowance, (address(this), address(this)));
        calls[6] = abi.encodeCall(token.transfer, (ALICE, 1));
        calls[7] = abi.encodeCall(token.approve, (ALICE, 1));
        calls[8] = abi.encodeCall(token.transferFrom, (address(this), ALICE, 1));
        vm.deal(address(this), calls.length);
        for (uint256 i; i < calls.length; ++i) {
            (bool success,) = address(token).call{value: 1}(calls[i]);
            assertTrue(!success);
        }
        assertEq(address(token).balance, 0);
        assertEq(address(this).balance, calls.length);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.allowance(address(this), address(this)), 17);
        assertEq(token.allowance(address(this), ALICE), 0);
    }

    function test_ContractRecipientsNeedNoCallbackOrOptIn() public {
        RejectingTokenRecipient recipient = new RejectingTokenRecipient();
        assertTrue(token.transfer(address(recipient), SUPPLY / 2));
        token.approve(SPENDER, SUPPLY / 2);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), address(recipient), SUPPLY / 2));
        assertEq(token.balanceOf(address(recipient)), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_FullSupplyRoundTripsHaveNoCooldownOrExpiry() public {
        TimeVm time = TimeVm(address(vm));
        time.chainId(1);
        for (uint256 i; i < 4; ++i) {
            assertTrue(token.transfer(ALICE, SUPPLY));
            vm.prank(ALICE);
            assertTrue(token.transfer(address(this), SUPPLY));
        }
        token.approve(SPENDER, SUPPLY);
        time.warp(block.timestamp + 3650 days);
        time.roll(block.number + 30_000_000);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, SUPPLY));
        vm.prank(ALICE);
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
