//SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./interfaces/IICOManager.sol";
import "./interfaces/IICOBondingCurve.sol";
import "./lib/Ownable.sol";
import "./interfaces/IDatabase.sol";
import "./lib/EnumerableSet.sol";
import "./interfaces/IEnjoyPumpToken.sol";

contract ICOManager is IICOManager, Ownable {

    // database
    IDatabase public database;

    // Generator
    address public generator;

    // max ico raise
    uint256 public MAX_RAISE = 4.2 ether;

    // max ico duration
    uint256 public MAX_DURATION = 1 days;

    struct ICO {
        uint256 startTime;
        uint256 endTime;
        bool isComplete;
        ICOConfig config;
        ICOStatus status;
    }

    struct ICOConfig {
        uint256 maxAmountPerWallet;
        EnumerableSet.AddressSet whitelistedAddresses;
        mapping ( address => uint256 ) whitelistedAmounts;
    }

    struct ICOStatus {
        uint256 totalRaised;
        uint256 totalTokensReceived;
        address[] contributors;
        mapping ( address => uint256 ) contributions;
    }

    // maps a token to an ICO
    mapping( address => ICO ) private icos;

    event ICOStarted(address indexed token, uint256 startTime, uint256 endTime);

    constructor(address _database) {
        database = IDatabase(_database);
    }

    function setGenerator(address _generator) external onlyOwner {
        generator = _generator;
    }

    function setDatabase(address _database) external onlyOwner {
        database = IDatabase(_database);
    }

    function setMaxRaise(uint256 _maxRaise) external onlyOwner {
        MAX_RAISE = _maxRaise;
    }

    function setMaxDuration(uint256 _maxDuration) external onlyOwner {
        MAX_DURATION = _maxDuration;
    }

    function claimTokens(address token) external {
        require(icos[token].isComplete, "ICO is not complete");
        require(icos[token].status.contributions[msg.sender] > 0, "No contributions found");

        // get amount of tokens to claim
        uint256 claimAmount = ( icos[token].status.contributions[msg.sender] * icos[token].status.totalTokensReceived ) / icos[token].status.totalRaised;

        // reset contribution
        icos[token].status.contributions[msg.sender] = 0;

        // send tokens to claimer
        IEnjoyPumpToken(token).transfer(msg.sender, claimAmount);
    }

    function endICO(address token) external {
        require(
            icos[token].isComplete == false && 
            icos[token].startTime != 0 && 
            ( block.timestamp >= icos[token].endTime || icos[token].status.totalRaised >= MAX_RAISE ),
            "ICO is not ready to be ended"
        );

        // set ICO as complete
        icos[token].isComplete = true;

        // get bonding curve address
        address bondingCurve = database.getBondingCurveForToken(token);
        require(bondingCurve != address(0), "Bonding curve not found");

        // start trading on bonding curve
        uint256 totalOut = IICOBondingCurve(bondingCurve).startTrading{ value: icos[token].status.totalRaised }();

        // set total tokens received - to be split amongst contributors
        icos[token].status.totalTokensReceived = totalOut;
    }

    function contribute(address token) external payable {
        require(
            icos[token].isComplete == false && 
            icos[token].startTime != 0 && 
            block.timestamp < icos[token].endTime,
            "ICO is not active"
        );
        require(
            msg.value > 0,
            "Contribution must be greater than 0"
        );

        if (isPrivateICO(token)) {
            require(
                EnumerableSet.contains(icos[token].config.whitelistedAddresses, msg.sender),
                "Not whitelisted"
            );

            // add user to contributors list if not already present
            if (icos[token].status.contributions[msg.sender] == 0) {
                icos[token].status.contributors.push(msg.sender);
            }

            // add value to contribution
            unchecked {
                icos[token].status.contributions[msg.sender] += msg.value;
                icos[token].status.totalRaised += msg.value;
            }

            // ensure contribution does not exceed whitelisted amount
            require(
                icos[token].config.whitelistedAmounts[msg.sender] >= icos[token].status.contributions[msg.sender],
                "Contribution exceeds whitelisted amount"
            );
        } else {

            // add user to contributors list if not already present
            if (icos[token].status.contributions[msg.sender] == 0) {
                icos[token].status.contributors.push(msg.sender);
            }

            // add value to contribution
            unchecked {
                icos[token].status.contributions[msg.sender] += msg.value;
                icos[token].status.totalRaised += msg.value;
            }

            // ensure contribution does not exceed max amount per wallet
            require(
                icos[token].config.maxAmountPerWallet >= icos[token].status.contributions[msg.sender],
                "Contribution exceeds max amount per wallet"
            );
        }

        require(
            icos[token].status.totalRaised <= MAX_RAISE,
            "ICO raise limit exceeded"
        );
    }

    function launchICO(
        address token,
        bytes calldata payload
    ) external override {
        require(msg.sender == generator, "Only Enjoy Pump Generator can launch ICOs");
        require(icos[token].startTime == 0, "ICO already exists for this token");

        // decode ICO configuration payload
        (
            uint256 maxAmountPerWallet, 
            uint256 duration,
            address[] memory whitelistedAddresses, 
            uint256[] memory whitelistedAmounts
        ) = abi.decode(payload, (uint256, uint256, address[], uint256[]));

        // ensure whitelisted addresses and amounts are the same length
        require(whitelistedAddresses.length == whitelistedAmounts.length, "Invalid payload: length mismatch");

        // ensure duration is valid
        require(duration > 60, "Min Duration is 1 minute");
        require(duration <= MAX_DURATION, "ICO duration exceeds maximum limit");
        
        uint len = whitelistedAddresses.length;
        for (uint i = 0; i < len;) {
            if (EnumerableSet.contains(icos[token].config.whitelistedAddresses, whitelistedAddresses[i]) == false) {
                EnumerableSet.add(icos[token].config.whitelistedAddresses, whitelistedAddresses[i]);
                icos[token].config.whitelistedAmounts[whitelistedAddresses[i]] = whitelistedAmounts[i];
            }
            unchecked { ++i; }
        }

        // set max amount per wallet
        icos[token].config.maxAmountPerWallet = maxAmountPerWallet;

        // set ICO details
        icos[token].startTime = block.timestamp;
        icos[token].endTime = block.timestamp + duration;
        icos[token].isComplete = false;

        emit ICOStarted(token, block.timestamp, block.timestamp + duration);
    }

    function remainingTime(address token) external view override returns (uint256) {
        if (icos[token].isComplete) {
            return 0;
        } else if (block.timestamp > icos[token].endTime) {
            return 0;
        } else {
            return icos[token].endTime - block.timestamp;
        }
    }

    function remainingBuyAmount(address token) external view returns (uint256) {
        if (icos[token].isComplete) {
            return 0;
        } else if (block.timestamp > icos[token].endTime) {
            return 0;
        } else {
            return MAX_RAISE > icos[token].status.totalRaised ? MAX_RAISE - icos[token].status.totalRaised : 0;
        }
    }

    function listContributors(address token) external view returns (address[] memory) {
        return icos[token].status.contributors;
    }

    function listContributorsAndContributions(address token) external view returns (address[] memory, uint256[] memory) {
        uint256 len = icos[token].status.contributors.length;
        uint256[] memory contributions_ = new uint256[](len);
        for (uint i = 0; i < len;) {
            contributions_[i] = icos[token].status.contributions[icos[token].status.contributors[i]];
            unchecked { ++i; }
        }
        return (icos[token].status.contributors, contributions_);
    }

    function getICOStatus(address token) external view returns (uint256, uint256, address[] memory, uint256[] memory) {
        uint256 len = icos[token].status.contributors.length;
        uint256[] memory contributions_ = new uint256[](len);
        for (uint i = 0; i < len;) {
            contributions_[i] = icos[token].status.contributions[icos[token].status.contributors[i]];
            unchecked { ++i; }
        }
        return (icos[token].status.totalRaised, icos[token].status.totalTokensReceived, icos[token].status.contributors, contributions_);
    }

    function getICOConfig(address token) external view returns (address[] memory, uint256[] memory, uint256) {
        uint256 len = EnumerableSet.length(icos[token].config.whitelistedAddresses);
        address[] memory whitelistedAddresses = new address[](len);
        uint256[] memory whitelistedAmounts = new uint256[](len);
        for (uint i = 0; i < len;) {
            whitelistedAddresses[i] = EnumerableSet.at(icos[token].config.whitelistedAddresses, i);
            whitelistedAmounts[i] = icos[token].config.whitelistedAmounts[whitelistedAddresses[i]];
            unchecked { ++i; }
        }
        return (whitelistedAddresses, whitelistedAmounts, icos[token].config.maxAmountPerWallet);
    }

    function getICOInfo(address token) external view returns (uint256, uint256, bool) {
        return (icos[token].startTime, icos[token].endTime, icos[token].isComplete);
    }

    function getICOInfoAndStatus(address token) external view returns (
        uint256 startTime,
        uint256 endTime,
        bool isComplete,
        uint256 totalRaised,
        uint256 totalTokensReceived,
        address[] memory contributors,
        uint256[] memory contributions_
    ) {
        uint256 len = icos[token].status.contributors.length;
        contributions_ = new uint256[](len);
        for (uint i = 0; i < len;) {
            contributions_[i] = icos[token].status.contributions[icos[token].status.contributors[i]];
            unchecked { ++i; }
        }
        return (
            icos[token].startTime,
            icos[token].endTime,
            icos[token].isComplete,
            icos[token].status.totalRaised, 
            icos[token].status.totalTokensReceived, 
            icos[token].status.contributors, 
            contributions_
        );
    }
    
    function isActive(address token) external view override returns (bool) {
        return icos[token].isComplete == false && icos[token].startTime != 0 && block.timestamp < icos[token].endTime;
    }

    function isICO(address token) external view override returns (bool) {
        return icos[token].startTime != 0;
    }

    function isPrivateICO(address token) public view returns (bool) {
        return EnumerableSet.length(icos[token].config.whitelistedAddresses) > 0;
    }

}