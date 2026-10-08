// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title SIMDTEST
/// @notice Fixed-supply ERC-20. The constructor credits the entire supply to its caller.
/// @dev The external launch factory handles distribution and pool initialization.
contract SIMDTESTToken {
    string public constant name = "SIMDTEST";
    string public constant symbol = "SIMDTEST";
    uint8 public constant decimals = 18;
    uint256 public constant totalSupply = 1_000_000_000 * 10 ** 18;

    mapping(address account => uint256 balance) public balanceOf;
    mapping(address holder => mapping(address spender => uint256 amount)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    error ERC20InvalidSender(address sender);
    error ERC20InvalidReceiver(address receiver);
    error ERC20InvalidSpender(address spender);
    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);

    constructor() {
        balanceOf[msg.sender] = totalSupply;
        emit Transfer(address(0), msg.sender, totalSupply);
    }

    /// @notice Transfer exactly `value` units from the caller to a nonzero recipient.
    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    /// @notice Replace the caller's allowance for `spender` with `value`.
    /// @dev A maximum uint256 allowance is unlimited and is not reduced when spent.
    function approve(address spender, uint256 value) external returns (bool) {
        if (spender == address(0)) revert ERC20InvalidSpender(spender);
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    /// @notice Transfer exactly `value` units using an allowance granted to the caller.
    /// @dev Spending a finite allowance does not emit an additional Approval event.
    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 available = allowance[from][msg.sender];
        if (available != type(uint256).max) {
            if (available < value) revert ERC20InsufficientAllowance(msg.sender, available, value);
            allowance[from][msg.sender] = available - value;
        }
        _transfer(from, to, value);
        return true;
    }

    function _transfer(address from, address to, uint256 value) private {
        if (from == address(0)) revert ERC20InvalidSender(from);
        if (to == address(0)) revert ERC20InvalidReceiver(to);
        uint256 available = balanceOf[from];
        if (available < value) revert ERC20InsufficientBalance(from, available, value);

        balanceOf[from] = available - value;
        // Read after debiting so a transfer to oneself preserves the original balance.
        balanceOf[to] += value;
        emit Transfer(from, to, value);
    }
}
