//SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
    Token Master Copy, all tokens will be created from this contract
 */

import "./interfaces/IEnjoyPumpToken.sol";
import "./interfaces/IBondingCurve.sol";

contract EnjoyPumpTokenData {

    // total supply
    uint256 internal _totalSupply;

    // token data
    string internal _name;
    string internal _symbol;
    uint8  internal _decimals;

    // bonding curve contract
    address internal bondingCurve;

    // balances
    mapping (address => uint256) internal _balances;
    mapping (address => mapping (address => uint256)) internal _allowances;

    modifier allowExternalTransfer() {
        if (IBondingCurve(bondingCurve).isBonded()) {
            _;
        } else {
            require(
                IBondingCurve(bondingCurve).allowEarlyTransfer(msg.sender), 
                'Not Authorized'
            );
            _;
        }
    }
}

contract EnjoyPumpToken is EnjoyPumpTokenData, IEnjoyPumpToken {

    function __init__(bytes calldata payload, address bondingCurve_) external override {
        require(bondingCurve == address(0), 'Already Initialized');
        require(bondingCurve_ != address(0), 'Zero Bonding Curve');

        // decode payload
        (
            _name,
            _symbol
        ) = abi.decode(payload, (string, string));
        
        // set bonding curve
        bondingCurve = bondingCurve_;

        // set token metadata
        _decimals = 18;
        _totalSupply = 1_000_000_000 * 10**_decimals;

        // allocate initial balance to be the total supply
        _balances[bondingCurve] = _totalSupply;
        emit Transfer(address(0), bondingCurve, _totalSupply);        
    }

    function totalSupply() external view override returns (uint256) { return _totalSupply; }
    function balanceOf(address account) public view override returns (uint256) { return _balances[account]; }
    function allowance(address holder, address spender) external view override returns (uint256) { return _allowances[holder][spender]; }
    
    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /** Transfer Function */
    function transfer(address recipient, uint256 amount) external override allowExternalTransfer returns (bool) {
        return _transferFrom(msg.sender, recipient, amount);
    }

    /** Transfer Function */
    function transferFrom(address sender, address recipient, uint256 amount) external override allowExternalTransfer returns (bool) {
        require(
            amount <= _allowances[sender][msg.sender],
            'Insufficient Allowance'
        );
        unchecked {
            _allowances[sender][msg.sender] -= amount;
        }
        return _transferFrom(sender, recipient, amount);
    }

    /** Transfer Function For Bonding Curve Only */
    function bondingCurveTransferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        require(
            msg.sender == bondingCurve,
            'Only Bonding Curve'
        );
        require(
            IBondingCurve(bondingCurve).isBonded() == false,
            'Already Bonded'
        );
        return _transferFrom(sender, recipient, amount);
    }

    function burn(uint256 qty) external {
        require(_balances[msg.sender] >= qty, 'Insufficient Balance');
        require(qty > 0, 'Zero Amount');
        unchecked {
            _balances[msg.sender] -= qty;
            _totalSupply -= qty;
        }
        emit Transfer(msg.sender, address(0), qty);
    }

    /** Internal Transfer */
    function _transferFrom(address sender, address recipient, uint256 amount) internal returns (bool) {
        require(
            recipient != address(0),
            'Zero Recipient'
        );
        require(
            amount > 0,
            'Zero Amount'
        );
        require(
            amount <= _balances[sender],
            'Insufficient Balance'
        );
        
        // decrement sender balance
        unchecked {
            _balances[sender] -= amount;
            _balances[recipient] += amount;
        }

        // emit transfer
        emit Transfer(sender, recipient, amount);
        return true;
    }

    function getBondingCurve() external view returns (address) {
        return bondingCurve;
    }

}