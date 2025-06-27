//SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./lib/TransferHelper.sol";
import "./lib/Ownable.sol";

contract INFFeeReceiver is Ownable {

    // list of all recipients
    address[] public recipients;

    // maps address to allocation of points
    mapping ( address => uint256 ) public allocation;

    // total points allocated
    uint256 public totalAllocation;

    constructor() {
        allocation[0x82A4a81c6d4D4C2c727D9ff0A83839AeAd2F1928] = 2;
        allocation[0x633940e1E8fC7731A610Ae8113a7219eB024c3A9] = 1;
        allocation[0x2b739b02e899cee1f077C6a81717884D9eaa5426] = 1;
        allocation[0xC9C46598cc854f2857199e17f747e8A7F6f9c7E3] = 1;
        allocation[0x98973020B7E67A48834D1c5CF6fE5ed9E1763EA9] = 2;
        allocation[0x4262C8ba078ddc8587c70d6BBbaA1A71717515bA] = 93;
        totalAllocation = 100;

        recipients.push(0x82A4a81c6d4D4C2c727D9ff0A83839AeAd2F1928);
        recipients.push(0x633940e1E8fC7731A610Ae8113a7219eB024c3A9);
        recipients.push(0x2b739b02e899cee1f077C6a81717884D9eaa5426);
        recipients.push(0xC9C46598cc854f2857199e17f747e8A7F6f9c7E3);
        recipients.push(0x98973020B7E67A48834D1c5CF6fE5ed9E1763EA9);
        recipients.push(0x4262C8ba078ddc8587c70d6BBbaA1A71717515bA);
    }

    function withdraw(address token, address to, uint256 amount) external onlyOwner {
        TransferHelper.safeTransfer(token, to, amount);
    }

    function withdrawETH(address to, uint256 amount) external onlyOwner {
        _sendETH(to, amount);
    }

    function addRecipient(address newRecipient, uint256 newAllocation) external onlyOwner {
        require(
            allocation[newRecipient] == 0,
            'Already Added'
        );

        // add to list
        recipients.push(newRecipient);

        // set allocation and increase total allocation
        allocation[newRecipient] = newAllocation;
        unchecked {
            totalAllocation += newAllocation;
        }
    }

    function removeRecipient(address recipient) external onlyOwner {

        // ensure recipient is in the system
        uint256 allocation_ = allocation[recipient];
        require(
            allocation_ > 0,
            'User Not Present'
        );

        // delete allocation, subtract from total allocation
        delete allocation[recipient];
        unchecked {
            totalAllocation -= allocation_;
        }

        // remove address from array
        uint index = recipients.length;
        for (uint i = 0; i < recipients.length;) {
            if (recipients[i] == recipient) {
                index = i;
                break;
            }
            unchecked { ++i; }
        }
        require(
            index < recipients.length,
            'Recipient Not Found'
        );

        // swap positions with last element then pop last element off
        recipients[index] = recipients[recipients.length - 1];
        recipients.pop();
    }

    function setAllocation(address recipient, uint256 newAllocation) external onlyOwner {

        // ensure recipient is in the system
        uint256 allocation_ = allocation[recipient];
        require(
            allocation_ > 0,
            'User Not Present'
        );

        // adjust their allocation and the total allocation
        allocation[recipient] = ( allocation[recipient] + newAllocation ) - allocation_;
        totalAllocation = ( totalAllocation + newAllocation ) - allocation_;
    }

    function triggerETH() external {

        // Ensure an ETH balance
        require(
            address(this).balance > 0,
            'Zero Amount'
        );

        // split balance into distributions
        uint256[] memory distributions = splitAmount(address(this).balance);

        // transfer distributions to each recipient
        uint len = distributions.length;
        for (uint i = 0; i < len;) {
            _sendETH(recipients[i], distributions[i]);
            unchecked { ++i; }
        }
    }

    function _sendETH(address to, uint amount) internal {
        TransferHelper.safeTransferETH(to, amount);
    }

    function getRecipients() external view returns (address[] memory) {
        return recipients;
    }

    function splitAmount(uint256 amount) public view returns (uint256[] memory distributions) {

        // length of recipient list
        uint256 len = recipients.length;
        distributions = new uint256[](len);

        // loop through recipients, setting their allocations
        for (uint i = 0; i < len;) {
            distributions[i] = ( ( amount * allocation[recipients[i]] ) / totalAllocation );
            unchecked { ++i; }
        }
    }

    receive() external payable {}
}