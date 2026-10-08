// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SIMDTESTToken} from "../src/SIMDTESTToken.sol";
import {TestSupport} from "./TestSupport.sol";

/// @dev Local CREATE2 fixture, never an application contract in the launch manifest.
contract TokenFactoryFixture {
    function deploy(bytes32 salt) external returns (SIMDTESTToken) {
        return new SIMDTESTToken{salt: salt}();
    }
}

contract SIMDTESTTokenTest is TestSupport {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    // Local actors are fixtures only; no launch address is inferred from them.
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant SPENDER = address(0x5EED);
    address internal constant DISTRIBUTOR = address(0xD157);
    address internal constant POOL_MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;

    SIMDTESTToken internal token;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new SIMDTESTToken();
    }

    function testMetadataAndInitialSupply() public view {
        assertTrue(keccak256(bytes(token.name())) == keccak256("SIMDTEST"));
        assertTrue(keccak256(bytes(token.symbol())) == keccak256("SIMDTEST"));
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.allowance(address(this), SPENDER), 0);
    }

    function testConstructorEmitsMintEvent() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), address(this), SUPPLY);
        new SIMDTESTToken();
    }

    function testCreate2CreditsOnlyTheCreatingFactory() public {
        TokenFactoryFixture factory = new TokenFactoryFixture();
        vm.prank(ALICE);
        SIMDTESTToken deployed = factory.deploy(keccak256("launch fixture"));
        assertEq(deployed.totalSupply(), SUPPLY);
        assertEq(deployed.balanceOf(address(factory)), SUPPLY);
        assertEq(deployed.balanceOf(ALICE), 0);
        assertEq(deployed.balanceOf(address(this)), 0);
    }

    function testTransferEntireSupplyWithoutFeeOrLimit() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, SUPPLY);
        assertTrue(token.transfer(ALICE, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(ALICE), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testZeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function testSelfTransferPreservesBalance() public {
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testTransferRejectsInsufficientBalance() public {
        vm.expectRevert(abi.encodeWithSelector(SIMDTESTToken.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transfer(BOB, 1);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function testSelfTransferStillRequiresBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(SIMDTESTToken.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        token.transfer(address(this), SUPPLY + 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function testTransferRejectsZeroRecipientEvenForZeroValue() public {
        vm.expectRevert(abi.encodeWithSelector(SIMDTESTToken.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(SIMDTESTToken.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testApprovalEmitsAndReplacesAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), SPENDER, 100 ether);
        assertTrue(token.approve(SPENDER, 100 ether));
        assertTrue(token.approve(SPENDER, 7 ether));
        assertEq(token.allowance(address(this), SPENDER), 7 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function testApproveRejectsZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(SIMDTESTToken.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function testApprovalIsScopedToCallerAndSpender() public {
        token.approve(SPENDER, 10);
        vm.prank(ALICE);
        token.approve(SPENDER, 20);
        assertEq(token.allowance(address(this), SPENDER), 10);
        assertEq(token.allowance(ALICE, SPENDER), 20);
        vm.expectRevert(abi.encodeWithSelector(SIMDTESTToken.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        vm.prank(BOB);
        token.transferFrom(address(this), BOB, 1);
    }

    function testTransferFromConsumesAllowanceAndEmitsTransfer() public {
        token.approve(SPENDER, 10 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, 4 ether);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 4 ether));
        assertEq(token.allowance(address(this), SPENDER), 6 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 4 ether);
        assertEq(token.balanceOf(ALICE), 4 ether);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), BOB, 6 ether));
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.balanceOf(BOB), 6 ether);
    }

    function testInfiniteAllowanceIsPreserved() public {
        token.approve(SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), BOB, SUPPLY - 1));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(ALICE) + token.balanceOf(BOB), SUPPLY);
    }

    function testRevocationPreventsSpending() public {
        token.approve(SPENDER, type(uint256).max);
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), SPENDER, 0);
        token.approve(SPENDER, 0);
        vm.expectRevert(abi.encodeWithSelector(SIMDTESTToken.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function testTransferFromRejectsOverspendingAtomically() public {
        token.approve(SPENDER, 9);
        vm.expectRevert(abi.encodeWithSelector(SIMDTESTToken.ERC20InsufficientAllowance.selector, SPENDER, 9, 10));
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, 10);
        assertEq(token.allowance(address(this), SPENDER), 9);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function testTransferFromInsufficientBalanceRestoresAllowance() public {
        token.approve(SPENDER, SUPPLY + 1);
        vm.expectRevert(
            abi.encodeWithSelector(SIMDTESTToken.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        vm.prank(SPENDER);
        token.transferFrom(address(this), ALICE, SUPPLY + 1);
        assertEq(token.allowance(address(this), SPENDER), SUPPLY + 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function testTransferFromZeroRecipientRestoresAllowance() public {
        token.approve(SPENDER, 10);
        vm.expectRevert(abi.encodeWithSelector(SIMDTESTToken.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(address(this), address(0), 10);
        assertEq(token.allowance(address(this), SPENDER), 10);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function testTransferFromRejectsZeroSender() public {
        vm.expectRevert(abi.encodeWithSelector(SIMDTESTToken.ERC20InvalidSender.selector, address(0)));
        token.transferFrom(address(0), ALICE, 0);
    }

    function testZeroTransferFromNeedsNoAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, 0);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 0));
        assertEq(token.allowance(ALICE, SPENDER), 0);
    }

    function testTransferFromSelfConsumesAllowanceButPreservesBalance() public {
        token.approve(SPENDER, SUPPLY);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(address(this), SPENDER), 0);
    }

    function testDeployerCannotSpendHolderBalanceWithoutApproval() public {
        token.transfer(ALICE, 100 ether);
        vm.expectRevert(abi.encodeWithSelector(SIMDTESTToken.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(ALICE, address(this), 1);
        assertEq(token.balanceOf(ALICE), 100 ether);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 100 ether));
    }

    /// @dev Token-side launch and settlement accounting only, not a Uniswap swap simulation.
    function testLaunchDistributionClaimsAndPoolManagerTransfersAreExact() public {
        uint256 swarm = SUPPLY / 10;
        uint256 pool = SUPPLY * 9 / 10;
        assertTrue(token.transfer(DISTRIBUTOR, swarm));
        assertTrue(token.transfer(POOL_MANAGER, pool));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(DISTRIBUTOR), swarm);
        assertEq(token.balanceOf(POOL_MANAGER), pool);

        vm.prank(DISTRIBUTOR);
        assertTrue(token.transfer(ALICE, swarm));
        assertEq(token.balanceOf(DISTRIBUTOR), 0);
        assertEq(token.balanceOf(ALICE), swarm);

        vm.prank(POOL_MANAGER);
        assertTrue(token.transfer(BOB, 1_000 ether));
        assertEq(token.balanceOf(BOB), 1_000 ether);
        assertEq(token.balanceOf(POOL_MANAGER), pool - 1_000 ether);
        vm.prank(BOB);
        token.approve(SPENDER, 1_000 ether);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(BOB, POOL_MANAGER, 1_000 ether));
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(POOL_MANAGER), pool);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testTransfersToRequestedRemainderAddressDoNotBurnSupply() public {
        address remainder = 0x000000000000000000000000000000000000dEaD;
        assertTrue(token.transfer(remainder, 1));
        assertEq(token.balanceOf(remainder), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testNoMintBurnOrAdministrativeSelectors() public {
        bytes[] memory calls = new bytes[](18);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", ALICE, 1);
        calls[1] = abi.encodeWithSignature("mint(uint256)", 1);
        calls[2] = abi.encodeWithSignature("mint()");
        calls[3] = abi.encodeWithSignature("burn(uint256)", 1);
        calls[4] = abi.encodeWithSignature("burnFrom(address,uint256)", ALICE, 1);
        calls[5] = abi.encodeWithSignature("owner()");
        calls[6] = abi.encodeWithSignature("transferOwnership(address)", ALICE);
        calls[7] = abi.encodeWithSignature("setMinter(address)", ALICE);
        calls[8] = abi.encodeWithSignature("initialize(address)", ALICE);
        calls[9] = abi.encodeWithSignature("upgradeTo(address)", ALICE);
        calls[10] = abi.encodeWithSignature("pause()");
        calls[11] = abi.encodeWithSignature("unpause()");
        calls[12] = abi.encodeWithSignature("blacklist(address)", ALICE);
        calls[13] = abi.encodeWithSignature("freeze(address)", ALICE);
        calls[14] = abi.encodeWithSignature("seize(address)", ALICE);
        calls[15] = abi.encodeWithSignature("setFee(uint256)", 100);
        calls[16] = abi.encodeWithSignature("setOwner(address)", ALICE);
        calls[17] = abi.encodeWithSignature("setTransfersEnabled(bool)", false);
        token.transfer(ALICE, 100);
        for (uint256 i; i < calls.length; ++i) {
            (bool deployerSucceeded,) = address(token).call(calls[i]);
            assertTrue(!deployerSucceeded);
            vm.prank(BOB);
            (bool strangerSucceeded,) = address(token).call(calls[i]);
            assertTrue(!strangerSucceeded);
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(ALICE), 100);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 100));
    }

    function testRejectsEtherAndUnknownCalls() public {
        vm.deal(address(this), 1 ether);
        (bool received,) = address(token).call{value: 1}("");
        assertTrue(!received);
        (bool unknown,) = address(token).call(hex"ffffffff");
        assertTrue(!unknown);
        assertEq(address(token).balance, 0);
    }

    function testRuntimeHasNoForbiddenOpcodes() public view {
        bytes memory runtime = address(token).code;
        assertTrue(runtime.length > 0 && runtime.length <= 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff);
        }
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzzTransfersConserveSupply(uint256 rawAmount, address recipient) public {
        if (recipient == address(0) || recipient == address(this)) return;
        uint256 amount = rawAmount % (SUPPLY + 1);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(recipient) + token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzzAllowanceConservation(uint256 rawAllowance, uint256 rawSpend) public {
        uint256 approved = rawAllowance % (SUPPLY + 1);
        uint256 spend = rawSpend % (approved + 1);
        token.approve(SPENDER, approved);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, spend));
        assertEq(token.allowance(address(this), SPENDER), approved - spend);
        assertEq(token.balanceOf(ALICE), spend);
        assertEq(token.balanceOf(address(this)), SUPPLY - spend);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzzOverdrawRevertsWithoutChangingState(uint256 rawExcess) public {
        uint256 excessive = SUPPLY + 1 + rawExcess % (type(uint256).max - SUPPLY);
        vm.expectRevert(
            abi.encodeWithSelector(SIMDTESTToken.ERC20InsufficientBalance.selector, address(this), SUPPLY, excessive)
        );
        token.transfer(ALICE, excessive);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzzTransferSequenceConservesSupply(uint256[24] memory amounts) public {
        address[3] memory actors = [address(this), ALICE, BOB];
        for (uint256 i; i < amounts.length; ++i) {
            address from = actors[i % actors.length];
            address to = actors[(i + 1) % actors.length];
            uint256 amount = amounts[i] % (token.balanceOf(from) + 1);
            vm.prank(from);
            assertTrue(token.transfer(to, amount));
            assertEq(token.balanceOf(address(this)) + token.balanceOf(ALICE) + token.balanceOf(BOB), SUPPLY);
            assertEq(token.totalSupply(), SUPPLY);
        }
    }
}
