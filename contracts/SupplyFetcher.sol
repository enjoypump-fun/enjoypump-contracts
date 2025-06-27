//SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./interfaces/IERC20.sol";
import "./interfaces/IDatabase.sol";

contract SupplyFetcher {
    function getSuppliesInCurve(address database, address[] calldata tokens) public view returns (uint256[] memory) {
        uint256 length = tokens.length;
        uint256[] memory supplies = new uint256[](length);

        for (uint i = 0; i < length;) {
            address token = tokens[i];
            supplies[i] = IERC20(token).balanceOf(IDatabase(database).getBondingCurveForToken(token));
            unchecked { ++i; }
        }
        return supplies;
    }
}