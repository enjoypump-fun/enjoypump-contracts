//SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
    Responsible for generating all contracts associated with a new project
    - Token Contract
    - Bonding Curve Contract

    Also adds these addresses and relevant information to the database
 */

import "./lib/Ownable.sol";
import "./interfaces/IBondingCurve.sol";
import "./interfaces/IEnjoyPumpToken.sol";
import "./interfaces/IEnjoyPumpGenerator.sol";
import "./interfaces/IDatabase.sol";
import "./interfaces/IICOManager.sol";
import "./interfaces/IICOBondingCurve.sol";

contract EnjoyPumpGenerator is IEnjoyPumpGenerator {

    IDatabase public immutable database;

    address public immutable icoManager;

    address public immutable icoBondingCurveMasterCopy;

    constructor(address _database, address _icoManager, address _icoBondingCurveMasterCopy) {
        database = IDatabase(_database);
        icoManager = _icoManager;
        icoBondingCurveMasterCopy = _icoBondingCurveMasterCopy;
    }

    /**
        Generates a token and bonding curve, initializes both and returns their addresses
     */
    function generateProject(bytes calldata tokenPayload, bytes calldata bondingCurvePayload_, address liquidityAdder) external override returns (address token, address bondingCurve) {
        require(msg.sender == address(database), "EnjoyPumpGenerator: Only database can call this function");

        // generate token
        token = generateToken();

        // decode the bonding curve payload to get the ICO payload and bonding curve payload
        (
            bytes memory icoPayload,
            bytes memory bondingCurvePayload
        ) = abi.decode(bondingCurvePayload_, (bytes, bytes));

        // decode the ICO payload to get the max amount per wallet and whitelisted addresses and amounts
        (
            uint256 maxAmountPerWallet, 
            uint256 duration,
            address[] memory whitelistedAddresses, 
        ) = abi.decode(icoPayload, (uint256, uint256, address[], uint256[]));

        // determine which bonding curve we are using - ICO or normal bonding curve
        // if maxAmountPerWallet is 0, whitelistedAddresses is empty and duration is 0, we are using a normal bonding curve
        if (maxAmountPerWallet == 0 && whitelistedAddresses.length == 0 && duration == 0) {

            // ICO is not active, this is a normal bonding curve
            bondingCurve = generateBondingCurve();
            IBondingCurve(bondingCurve).__init__(bondingCurvePayload, token, liquidityAdder);
        } else {

            // ICO is active, launch ICO Bonding Curve and launch the ICO through the icoManager
            bondingCurve = generateICOBondingCurve();
            IICOBondingCurve(bondingCurve).__init__(bondingCurvePayload, token, liquidityAdder, icoManager);

            // launch ICO through the icoManager
            IICOManager(icoManager).launchICO(token, icoPayload);
        }
        
        // initialize the token contract with the bonding curve address
        IEnjoyPumpToken(token).__init__(tokenPayload, bondingCurve);
        
        return (token, bondingCurve);
    }

    function generateToken() internal returns(address) {
        return _clone(database.getEnjoyPumpTokenMasterCopy());
    }

    function generateBondingCurve() internal returns(address) {
        return _clone(database.getBondingCurveMasterCopy());
    }

    function generateICOBondingCurve() internal returns(address) {
        return _clone(icoBondingCurveMasterCopy);
    }

    /**
     * @dev Deploys and returns the address of a clone that mimics the behaviour of `implementation`.
     *
     * This function uses the create opcode, which should never revert.
     */
    function _clone(address implementation) internal returns (address instance) {
        /// @solidity memory-safe-assembly
        assembly {
            //EIP-1167
            let ptr := mload(0x40)
            mstore(ptr, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(ptr, 0x14), shl(0x60, implementation))
            mstore(add(ptr, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            instance := create(0, ptr, 0x37)
        }
        require(instance != address(0), "ERC1167: create failed");
    }

}