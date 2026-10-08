// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SIMDTESTToken} from "../src/SIMDTESTToken.sol";
import {TestSupport} from "./TestSupport.sol";

/// @dev A closed set of holders permits an exact conservation check. The token and
/// requested remainder address are receive-only sinks, never impersonated senders.
/// Expected balances/allowances are computed from inputs, never copied from token storage.
contract SIMDTESTHandler is TestSupport {
    uint256 public constant SUPPLY = 1_000_000_000 ether;
    uint256 public constant ACTIVE_ACTORS = 6;
    SIMDTESTToken public immutable token;
    address[8] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;
    uint256 public successfulTransfers;
    uint256 public successfulSpends;
    uint256 public rejectedCalls;

    constructor() {
        token = new SIMDTESTToken();
        actors = [
            address(this),
            address(0xA11CE),
            address(0xB0B),
            address(0x5EED),
            address(0xD157),
            0x000000000004444c5dc75cB358380D2e3dE08A90,
            address(token),
            0x000000000000000000000000000000000000dEaD
        ];
        expectedBalance[address(this)] = SUPPLY;
        // Seed funded callers and both finite and infinite allowances so random
        // spending explores nonzero amounts from the beginning of each sequence.
        for (uint256 i = 1; i < ACTIVE_ACTORS; ++i) {
            assertTrue(token.transfer(actors[i], SUPPLY / 10));
            _move(address(this), actors[i], SUPPLY / 10);
        }
        for (uint256 i; i < ACTIVE_ACTORS; ++i) {
            _approve(actors[i], actors[(i + 1) % ACTIVE_ACTORS], SUPPLY / 20);
            _approve(actors[i], actors[(i + 2) % ACTIVE_ACTORS], type(uint256).max);
        }
    }

    function transfer(uint8 fromSeed, uint8 toSeed, uint256 amountSeed, uint8 mode) external {
        address from = actors[fromSeed % ACTIVE_ACTORS];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[from];
        uint256 amount = amountSeed % (balance + 1);
        mode %= 6;
        if (mode == 1) amount = balance;
        if (mode == 2) amount = 0;
        if (mode == 3) amount = balance + 1;
        if (mode == 4) amount = type(uint256).max;
        if (mode == 5) to = address(0);

        bool valid = to != address(0) && amount <= balance;
        _call(from, abi.encodeCall(token.transfer, (to, amount)), valid);
        if (valid) {
            _move(from, to, amount);
            ++successfulTransfers;
        }
    }

    function approve(uint8 ownerSeed, uint8 spenderSeed, uint256 amount, uint8 mode) external {
        address owner = actors[ownerSeed % ACTIVE_ACTORS];
        address spender = actors[spenderSeed % actors.length];
        mode %= 5;
        if (mode == 1) amount = 0;
        if (mode == 2) amount = type(uint256).max;
        if (mode == 3) amount %= SUPPLY + 1;
        if (mode == 4) spender = address(0);
        bool valid = spender != address(0);
        _call(owner, abi.encodeCall(token.approve, (spender, amount)), valid);
        if (valid) expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint8 ownerSeed, uint8 spenderSeed, uint8 toSeed, uint256 amountSeed, uint8 mode) external {
        address owner = actors[ownerSeed % ACTIVE_ACTORS];
        address spender = actors[spenderSeed % ACTIVE_ACTORS];
        address to = actors[toSeed % actors.length];
        uint256 permitted = expectedAllowance[owner][spender];
        uint256 balance = expectedBalance[owner];
        uint256 limit = balance < permitted ? balance : permitted;
        uint256 amount = amountSeed % (limit + 1);
        mode %= 8;
        if (mode == 1) amount = limit;
        if (mode == 2) amount = 0;
        if (mode == 3) amount = balance + 1;
        if (mode == 4) amount = permitted == type(uint256).max ? type(uint256).max : permitted + 1;
        if (mode == 5) to = owner; // self-spending must still consume authorization
        if (mode == 6) to = address(0);
        if (mode == 7) {
            owner = address(0);
            amount = 0; // reaches the sender check without an allowance failure
        }

        bool valid = owner != address(0) && to != address(0) && amount <= balance && amount <= permitted;
        _call(spender, abi.encodeCall(token.transferFrom, (owner, to, amount)), valid);
        if (valid) {
            if (permitted != type(uint256).max) expectedAllowance[owner][spender] = permitted - amount;
            _move(owner, to, amount);
            ++successfulSpends;
        }
    }

    function privilegedCall(uint8 callerSeed, uint8 holderSeed, uint256 amount, uint8 selectorSeed) external {
        address caller = actors[callerSeed % ACTIVE_ACTORS];
        address holder = actors[holderSeed % actors.length];
        bytes memory data;
        uint8 choice = selectorSeed % 8;
        if (choice == 0) data = abi.encodeWithSignature("mint(address,uint256)", holder, amount);
        if (choice == 1) data = abi.encodeWithSignature("burn(uint256)", amount);
        if (choice == 2) data = abi.encodeWithSignature("burnFrom(address,uint256)", holder, amount);
        if (choice == 3) data = abi.encodeWithSignature("pause()");
        if (choice == 4) data = abi.encodeWithSignature("setBlacklist(address,bool)", holder, true);
        if (choice == 5) data = abi.encodeWithSignature("seize(address)", holder);
        if (choice == 6) data = abi.encodeWithSignature("upgradeTo(address)", holder);
        if (choice == 7) data = abi.encodeWithSignature("initialize(address)", holder);
        _call(caller, data, false);
    }

    function assertModel() external view {
        require(token.totalSupply() == SUPPLY, "fixed supply changed");
        require(token.balanceOf(address(0)) == 0, "zero address received tokens");
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            address holder = actors[i];
            uint256 balance = token.balanceOf(holder);
            require(balance == expectedBalance[holder], "balance differs from model");
            sum += balance;
            require(token.allowance(holder, address(0)) == 0, "zero spender acquired allowance");
            for (uint256 j; j < actors.length; ++j) {
                address spender = actors[j];
                require(
                    token.allowance(holder, spender) == expectedAllowance[holder][spender],
                    "allowance differs from model"
                );
            }
        }
        require(sum == SUPPLY, "balances do not conserve supply");
    }

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function _move(address from, address to, uint256 amount) private {
        // A net-zero balance change is independent of the implementation's debit/credit order.
        if (from == to) return;
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function _call(address caller, bytes memory data, bool expectedSuccess) private {
        vm.prank(caller);
        (bool success, bytes memory result) = address(token).call(data);
        require(success == expectedSuccess, "unexpected token call outcome");
        if (success) {
            require(result.length == 32 && abi.decode(result, (bool)), "ERC20 did not return true");
        } else {
            ++rejectedCalls;
        }
    }
}

contract SIMDTESTTokenInvariantTest is TestSupport {
    SIMDTESTHandler internal handler;

    struct FuzzSelector {
        address addr;
        bytes4[] selectors;
    }

    function setUp() public {
        handler = new SIMDTESTHandler();
    }

    // Foundry's invariant targeting ABI, kept local to avoid a new dependency.
    function targetContracts() public view returns (address[] memory targets) {
        targets = new address[](1);
        targets[0] = address(handler);
    }

    function targetSelectors() public view returns (FuzzSelector[] memory targets) {
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = SIMDTESTHandler.transfer.selector;
        selectors[1] = SIMDTESTHandler.approve.selector;
        selectors[2] = SIMDTESTHandler.transferFrom.selector;
        selectors[3] = SIMDTESTHandler.privilegedCall.selector;
        targets = new FuzzSelector[](1);
        targets[0] = FuzzSelector(address(handler), selectors);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 128
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_SupplyBalancesAndAllowancesMatchIndependentModel() public view {
        handler.assertModel();
    }

    /// @dev Exercises the handler's nonzero success and rollback branches deterministically,
    /// guarding against accidentally vacuous random campaigns or ignored handler reverts.
    function testHandlerExercisesSpendingRevocationFailuresAndSelfTransfers() public {
        handler.transfer(0, 1, 7, 0);
        handler.transferFrom(0, 1, 2, 11, 0); // finite allowance
        handler.transferFrom(0, 2, 3, 13, 0); // infinite allowance
        handler.transferFrom(0, 1, 0, 5, 5); // self-transfer
        handler.approve(0, 1, 0, 1); // revoke
        handler.transferFrom(0, 1, 2, 1, 4); // cannot spend revoked allowance
        handler.approve(0, 1, type(uint256).max - 1, 0);
        handler.transferFrom(0, 1, 2, 0, 3); // balance failure must restore finite allowance
        handler.transferFrom(0, 2, 2, 0, 3); // same failure under infinite allowance
        handler.transfer(0, 1, 1, 5); // zero recipient
        handler.transfer(0, 0, 1, 3); // overdraw even when sending to self
        handler.privilegedCall(0, 1, 1, 0); // deployer cannot mint
        handler.transfer(0, 7, 1, 0); // explicit remainder destination does not burn
        handler.transfer(0, 6, 1, 0); // tokens held by the token itself remain in supply
        handler.assertModel();
        require(handler.successfulTransfers() == 3, "handler missed direct transfers");
        require(handler.successfulSpends() == 3, "handler missed delegated transfers");
        require(handler.rejectedCalls() == 6, "handler missed rejected calls");
    }
}
